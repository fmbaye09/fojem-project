<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\Trips\SearchTripsRequest;
use App\Http\Requests\Trips\StoreTripRequest;
use App\Models\Booking;
use App\Models\PlatformSetting;
use App\Models\Trip;
use App\Models\Vehicle;
use App\Services\MatchingService;
use App\Services\NotificationService;
use App\Services\TripCancellationService;
use App\Services\TripLifecycleService;
use App\Services\TripStopPlanner;
use App\Services\WalletService;
use Carbon\CarbonImmutable;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class TripController extends Controller
{
    /**
     * Publish a new trip. Blocked unless the authenticated user has an
     * approved driver profile - a pending/rejected driver cannot publish.
     */
    public function store(StoreTripRequest $request, MatchingService $matching, NotificationService $notifications, TripStopPlanner $planner)
    {
        $user = $request->user();
        $driver = $user->driver;

        if (! $driver || ! $driver->isApproved()) {
            return response()->json([
                'message' => 'Votre profil chauffeur doit etre approuve avant de publier un trajet.',
            ], 403);
        }

        $vehicle = Vehicle::where('id', $request->input('vehicle_id'))
            ->where('driver_id', $driver->id)
            ->firstOrFail();

        $departureAt = $request->input('departure_type') === 'scheduled'
            ? CarbonImmutable::parse($request->input('scheduled_at'))
            : CarbonImmutable::now();
        $rawStops = $request->has('stops')
            ? $request->input('stops')
            : $planner->fromLegacyFields($request->all());
        $stops = $planner->plan($rawStops, $departureAt, (float) $request->input('price_per_seat'));
        $first = $stops[0];
        $last = $stops[count($stops) - 1];
        $intermediate = array_slice($stops, 1, -1);

        $trip = DB::transaction(function () use ($request, $driver, $vehicle, $departureAt, $stops, $first, $last, $intermediate) {
            $trip = new Trip([
                'driver_id' => $driver->id,
                'vehicle_id' => $vehicle->id,
                'departure_type' => $request->input('departure_type'),
                'scheduled_at' => $departureAt,
                'price_per_seat' => $request->input('price_per_seat'),
                'toll_fees' => $request->input('toll_fees', 0),
                'seats_available' => $request->input('seats_available'),
                'is_recurring' => $request->boolean('is_recurring'),
                'recurrence_rule' => $request->input('recurrence_rule'),
                'status' => Trip::STATUS_OPEN,
                'women_only' => $request->boolean('women_only'),
                // Denormalised from the first/last stop for the map, admin
                // views and older app versions that don't read `stops`.
                'origin_name' => $first['name'],
                'destination_name' => $last['name'],
                'waypoints' => array_map(fn ($s) => ['name' => $s['name'], 'lat' => $s['lat'], 'lng' => $s['lng']], $intermediate) ?: null,
                'current_lat' => $first['lat'],
                'current_lng' => $first['lng'],
                'location_updated_at' => now(),
            ]);

            $trip->setOriginPoint($first['lat'], $first['lng']);
            $trip->setDestinationPoint($last['lat'], $last['lng']);
            $trip->save();
            $trip->stops()->createMany($stops);

            return $trip;
        });

        $freshTrip = Trip::withLatLng()->with('vehicle', 'driverProfile.user')->findOrFail($trip->id);

        // Auto-match against open ride requests and notify passengers when score >= 65%
        try {
            $matchedRequests = $matching->bestRideRequestsForTrip($freshTrip, 25000, 65.0);
            $tripLabel = ($freshTrip->origin_name ?? 'Départ') . ' → ' . ($freshTrip->destination_name ?? 'Arrivée');
            foreach ($matchedRequests as $req) {
                if ($req->passenger && $req->passenger_id !== $user->id) {
                    $pct = (int) round((float) $req->getAttribute('compatibility_score'));
                    $notifications->system(
                        $req->passenger,
                        "Trajet compatible à {$pct}% trouvé !",
                        "Un chauffeur vient de publier un trajet {$tripLabel} correspondant à votre demande.",
                        [
                            'type' => 'trip_match',
                            'trip_id' => $freshTrip->id,
                            'ride_request_id' => $req->id,
                            'compatibility_score' => $pct,
                        ]
                    );
                }
            }
        } catch (\Throwable $e) {
            // Do not fail trip creation if notification fails
        }

        return response()->json(['trip' => $freshTrip], 201);
    }

    /** The authenticated driver's own trips. */
    public function mine(Request $request)
    {
        TripLifecycleService::sync();

        $driver = $request->user()->driver;

        if (! $driver) {
            return response()->json(['message' => 'Pas de profil chauffeur.'], 403);
        }

        $trips = Trip::withLatLng()
            ->where('driver_id', $driver->id)
            ->orderByDesc('created_at')
            ->paginate(20);

        return response()->json($trips);
    }

    public function show(Trip $trip)
    {
        TripLifecycleService::sync();

        $trip = Trip::withLatLng()->with('vehicle', 'driverProfile.user')->findOrFail($trip->id);
        $trip->setAttribute('occupied_seats', Booking::occupiedSeatNumbers($trip->id));

        return response()->json(['trip' => $trip]);
    }

    /**
     * Public search, BlaBlaCar style: the passenger travels to the driver's
     * meeting points. A trip matches when one of its stops lies within
     * radius_m of the passenger's departure and a LATER stop lies within
     * radius_m of their destination. Each result carries a `match` with the
     * best boarding/alighting pair, how far those points are from the
     * passenger, and the segment price.
     *
     * When nothing matches, `suggestions` holds matches within a wider
     * radius on any date, then any upcoming trip.
     */
    public function search(SearchTripsRequest $request)
    {
        TripLifecycleService::sync();

        $radius = (int) $request->input('radius_m', 15000);
        $criteria = [
            'origin_lat' => (float) $request->input('origin_lat'),
            'origin_lng' => (float) $request->input('origin_lng'),
            'destination_lat' => (float) $request->input('destination_lat'),
            'destination_lng' => (float) $request->input('destination_lng'),
            'seats' => (int) $request->input('seats', 1),
            'women_only' => $request->boolean('women_only'),
        ];

        $trips = $this->matchTripsByStops($criteria + ['radius' => $radius, 'date' => $request->input('date')]);

        $suggestions = collect();
        if ($trips->isEmpty()) {
            $suggestions = $this->matchTripsByStops($criteria + ['radius' => min($radius * 3, 50000), 'date' => null], 6);

            if ($suggestions->isEmpty()) {
                $suggestions = Trip::query()
                    ->withLatLng()
                    ->where('status', Trip::STATUS_OPEN)
                    ->where('seats_available', '>=', $criteria['seats'])
                    ->with('vehicle', 'driverProfile.user')
                    ->orderBy('scheduled_at')
                    ->limit(6)
                    ->get();
            }
        }

        return response()->json([
            'trips' => $trips,
            'suggestions' => $suggestions,
        ]);
    }

    /**
     * @param  array{origin_lat: float, origin_lng: float, destination_lat: float, destination_lng: float, seats: int, women_only: bool, radius: int, date: ?string}  $c
     * @return \Illuminate\Support\Collection<int, Trip>
     */
    private function matchTripsByStops(array $c, ?int $limit = null)
    {
        $where = ["t.deleted_at IS NULL", "t.status = 'open'", 't.seats_available >= ?'];
        $bindings = [$c['origin_lng'], $c['origin_lat'], $c['destination_lng'], $c['destination_lat'], $c['seats']];

        $where[] = 'ST_DWithin(b.location_geom, o.pt, ?)';
        $where[] = 'ST_DWithin(a.location_geom, d.pt, ?)';
        array_push($bindings, $c['radius'], $c['radius']);

        if ($c['women_only']) {
            $where[] = 't.women_only = true';
        }
        if ($c['date']) {
            // Legacy stops may lack a time: fall back to the trip's departure.
            $where[] = 'COALESCE(b.scheduled_at, t.scheduled_at, t.created_at)::date = ?::date';
            $bindings[] = $c['date'];
        }

        // One row per trip: the boarding/alighting pair closest to the
        // passenger's two points, boarding strictly before alighting.
        $rows = DB::select(
            'SELECT DISTINCT ON (b.trip_id)
                    b.trip_id,
                    b.id AS boarding_stop_id,
                    a.id AS alighting_stop_id,
                    ST_Distance(b.location_geom, o.pt) AS boarding_distance_m,
                    ST_Distance(a.location_geom, d.pt) AS alighting_distance_m,
                    a.price_from_origin - b.price_from_origin AS segment_price
               FROM trip_stops b
               JOIN trip_stops a ON a.trip_id = b.trip_id AND a.position > b.position
               JOIN trips t ON t.id = b.trip_id
              CROSS JOIN (SELECT ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography AS pt) o
              CROSS JOIN (SELECT ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography AS pt) d
              WHERE ' . implode(' AND ', $where) . '
              ORDER BY b.trip_id, ST_Distance(b.location_geom, o.pt) + ST_Distance(a.location_geom, d.pt)',
            $bindings,
        );

        if ($rows === []) {
            return collect();
        }

        $trips = Trip::query()
            ->withLatLng()
            ->with('vehicle', 'driverProfile.user')
            ->whereIn('id', array_column($rows, 'trip_id'))
            ->get()
            ->keyBy('id');

        $results = collect($rows)
            ->map(function ($row) use ($trips) {
                $trip = $trips->get($row->trip_id);
                if (! $trip) {
                    return null;
                }
                $boarding = $trip->stops->firstWhere('id', $row->boarding_stop_id);
                $alighting = $trip->stops->firstWhere('id', $row->alighting_stop_id);
                $trip->setAttribute('match', [
                    'boarding_stop' => $boarding,
                    'alighting_stop' => $alighting,
                    'boarding_distance_m' => (int) round($row->boarding_distance_m),
                    'alighting_distance_m' => (int) round($row->alighting_distance_m),
                    'segment_price' => number_format((float) $row->segment_price, 2, '.', ''),
                ]);

                return $trip;
            })
            ->filter()
            ->sortBy(fn (Trip $t) => $t->match['boarding_stop']?->scheduled_at ?? $t->scheduled_at)
            ->values();

        return $limit ? $results->take($limit)->values() : $results;
    }

    /** Driver cancels their own trip. */
    public function cancel(Request $request, Trip $trip, TripCancellationService $cancellation)
    {
        $driver = $request->user()->driver;

        if (! $driver || $trip->driver_id !== $driver->id) {
            return response()->json(['message' => 'Non autorise.'], 403);
        }

        if (in_array($trip->status, [Trip::STATUS_COMPLETED, Trip::STATUS_CANCELLED], true)) {
            return response()->json(['message' => 'Ce trajet ne peut plus etre annule.'], 422);
        }

        $cancellation->cancel($trip, 'driver');

        return response()->json(['trip' => $trip->fresh()]);
    }

    /** Driver starts the trip. */
    public function start(Request $request, Trip $trip, NotificationService $notifications)
    {
        $driver = $request->user()->driver;

        if (! $driver || $trip->driver_id !== $driver->id) {
            return response()->json(['message' => 'Non autorise.'], 403);
        }

        if (in_array($trip->status, [Trip::STATUS_COMPLETED, Trip::STATUS_CANCELLED], true)) {
            return response()->json(['message' => 'Ce trajet ne peut plus etre demarre.'], 422);
        }

        $originCoords = DB::selectOne(
            'SELECT ST_Y(origin_geom::geometry) as lat, ST_X(origin_geom::geometry) as lng FROM trips WHERE id = ?',
            [$trip->id]
        );

        $trip->update([
            'status' => Trip::STATUS_IN_PROGRESS,
            'current_lat' => $trip->current_lat ?? ($originCoords ? (float) $originCoords->lat : null),
            'current_lng' => $trip->current_lng ?? ($originCoords ? (float) $originCoords->lng : null),
            'location_updated_at' => now(),
        ]);

        // Notifier les passagers avec une réservation confirmée
        $bookings = Booking::where('trip_id', $trip->id)
            ->where('status', Booking::STATUS_CONFIRMED)
            ->with('passenger')
            ->get();

        $tripLabel = ($trip->origin_name ?? 'Départ') . ' → ' . ($trip->destination_name ?? 'Arrivée');
        foreach ($bookings as $b) {
            if ($b->passenger) {
                $notifications->system(
                    $b->passenger,
                    'Trajet démarré !',
                    "Votre trajet $tripLabel vient de démarrer. Suivez la position du chauffeur en direct !",
                    ['trip_id' => $trip->id, 'booking_id' => $b->id]
                );
            }
        }

        return response()->json(['trip' => Trip::withLatLng()->with('vehicle', 'driverProfile.user')->findOrFail($trip->id)]);
    }

    /** Driver updates live GPS position during an active trip. */
    public function updateLocation(Request $request, Trip $trip)
    {
        $driver = $request->user()->driver;

        if (! $driver || $trip->driver_id !== $driver->id) {
            return response()->json(['message' => 'Non autorise.'], 403);
        }

        $validated = $request->validate([
            'lat' => ['required', 'numeric', 'between:-90,90'],
            'lng' => ['required', 'numeric', 'between:-180,180'],
            'heading' => ['sometimes', 'nullable', 'numeric'],
        ]);

        $trip->update([
            'current_lat' => (float) $validated['lat'],
            'current_lng' => (float) $validated['lng'],
            'current_heading' => isset($validated['heading']) ? (float) $validated['heading'] : $trip->current_heading,
            'location_updated_at' => now(),
        ]);

        return response()->json([
            'current_lat' => $trip->current_lat,
            'current_lng' => $trip->current_lng,
            'current_heading' => $trip->current_heading,
            'location_updated_at' => $trip->location_updated_at?->toIso8601String(),
        ]);
    }

    /** Driver completes the trip and settles all remaining confirmed bookings. */
    public function complete(Request $request, Trip $trip, WalletService $wallets, NotificationService $notifications)
    {
        $driver = $request->user()->driver;

        if (! $driver || $trip->driver_id !== $driver->id) {
            return response()->json(['message' => 'Non autorise.'], 403);
        }

        if ($trip->status === Trip::STATUS_COMPLETED) {
            return response()->json(['trip' => $trip]);
        }

        DB::transaction(function () use ($trip, $wallets, $notifications) {
            $trip->update(['status' => Trip::STATUS_COMPLETED]);

            $bookings = Booking::where('trip_id', $trip->id)
                ->where('status', Booking::STATUS_CONFIRMED)
                ->with('passenger')
                ->get();

            $commissionPct = (float) (PlatformSetting::query()->value('commission_pct') ?? 0);
            $wallet = $trip->driverProfile?->user?->wallet;

            foreach ($bookings as $b) {
                $b->update([
                    'status' => Booking::STATUS_COMPLETED,
                    'started_at' => $b->started_at ?? now(),
                    'completed_at' => now(),
                ]);

                if ($wallet) {
                    $net = bcmul((string) $b->price_charged, (string) (1 - $commissionPct / 100), 2);
                    $wallets->credit(
                        $wallet,
                        'payment',
                        (float) $net,
                        'wallet',
                        'booking_payment:'.$b->id,
                        $b->id,
                    );
                }

                if ($b->passenger) {
                    $notifications->bookingCompleted($b->passenger, [
                        'booking_id' => $b->id,
                        'trip_id'    => $trip->id,
                        'trip_label' => ($trip->origin_name ?? 'Départ') . ' → ' . ($trip->destination_name ?? 'Arrivée'),
                    ]);
                }
            }
        });

        return response()->json(['trip' => $trip->fresh()]);
    }
}
