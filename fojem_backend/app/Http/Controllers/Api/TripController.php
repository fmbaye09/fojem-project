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
use App\Services\TripLifecycleService;
use App\Services\WalletService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class TripController extends Controller
{
    /**
     * Publish a new trip. Blocked unless the authenticated user has an
     * approved driver profile - a pending/rejected driver cannot publish.
     */
    public function store(StoreTripRequest $request, MatchingService $matching, NotificationService $notifications)
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

        $originLat = (float) $request->input('origin_lat');
        $originLng = (float) $request->input('origin_lng');
        $destLat = (float) $request->input('destination_lat');
        $destLng = (float) $request->input('destination_lng');

        $trip = new Trip([
            'driver_id' => $driver->id,
            'vehicle_id' => $vehicle->id,
            'departure_type' => $request->input('departure_type'),
            'scheduled_at' => $request->input('scheduled_at'),
            'price_per_seat' => $request->input('price_per_seat'),
            'toll_fees' => $request->input('toll_fees', 0),
            'seats_available' => $request->input('seats_available'),
            'is_recurring' => $request->boolean('is_recurring'),
            'recurrence_rule' => $request->input('recurrence_rule'),
            'status' => Trip::STATUS_OPEN,
            'women_only' => $request->boolean('women_only'),
            'origin_name' => $request->input('origin_name'),
            'destination_name' => $request->input('destination_name'),
            'waypoints' => $request->input('waypoints'),
            'current_lat' => $originLat,
            'current_lng' => $originLng,
            'location_updated_at' => now(),
        ]);

        $trip->setOriginPoint($originLat, $originLng);
        $trip->setDestinationPoint($destLat, $destLng);
        $trip->save();

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

        return response()->json(['trip' => $trip]);
    }

    /**
     * Public search: trips whose origin AND destination both lie within
     * radius_m (default 5km) of the requested points, open and departing
     * soon or now.
     */
    public function search(SearchTripsRequest $request)
    {
        TripLifecycleService::sync();

        $radius = (int) $request->input('radius_m', 5000);

        $originLat = (float) $request->input('origin_lat');
        $originLng = (float) $request->input('origin_lng');
        $destLat   = (float) $request->input('destination_lat');
        $destLng   = (float) $request->input('destination_lng');

        $query = Trip::query()
            ->withLatLng()
            ->where('status', Trip::STATUS_OPEN)
            ->where('seats_available', '>', 0)
            ->near(
                $originLat,
                $originLng,
                $destLat,
                $destLng,
                $radius
            )
            ->with('vehicle', 'driverProfile.user');

        if ($request->boolean('women_only')) {
            $query->where('women_only', true);
        }

        $trips = $query->orderBy('scheduled_at')->get();

        // Include open trips with intermediate waypoints that match the requested path in order
        $waypointCandidates = Trip::query()
            ->withLatLng()
            ->where('status', Trip::STATUS_OPEN)
            ->where('seats_available', '>', 0)
            ->whereNotNull('waypoints')
            ->when($request->boolean('women_only'), fn ($q) => $q->where('women_only', true))
            ->whereNotIn('id', $trips->pluck('id'))
            ->with('vehicle', 'driverProfile.user')
            ->orderBy('scheduled_at')
            ->get()
            ->filter(fn (Trip $t) => $t->matchesPathWithWaypoints($originLat, $originLng, $destLat, $destLng, $radius));

        if ($waypointCandidates->isNotEmpty()) {
            $trips = $trips->concat($waypointCandidates)->sortBy('scheduled_at')->values();
        }

        $suggestions = collect();
        if ($trips->isEmpty()) {

            // Suggestions : trajets dont l'origine OU la destination est dans un rayon élargi (35 km)
            $wider = Trip::query()
                ->withLatLng()
                ->where('status', Trip::STATUS_OPEN)
                ->where('seats_available', '>', 0)
                ->where(function ($q) use ($originLat, $originLng, $destLat, $destLng) {
                    $q->whereRaw('ST_DWithin(origin_geom, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, 35000)', [$originLng, $originLat])
                      ->orWhereRaw('ST_DWithin(destination_geom, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, 35000)', [$destLng, $destLat]);
                })
                ->with('vehicle', 'driverProfile.user')
                ->orderBy('scheduled_at')
                ->limit(6)
                ->get();

            if ($wider->isNotEmpty()) {
                $suggestions = $wider;
            } else {
                // Autres trajets disponibles à venir
                $suggestions = Trip::query()
                    ->withLatLng()
                    ->where('status', Trip::STATUS_OPEN)
                    ->where('seats_available', '>', 0)
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

    /** Driver cancels their own trip. */
    public function cancel(Request $request, Trip $trip)
    {
        $driver = $request->user()->driver;

        if (! $driver || $trip->driver_id !== $driver->id) {
            return response()->json(['message' => 'Non autorise.'], 403);
        }

        if (in_array($trip->status, [Trip::STATUS_COMPLETED, Trip::STATUS_CANCELLED], true)) {
            return response()->json(['message' => 'Ce trajet ne peut plus etre annule.'], 422);
        }

        $trip->update(['status' => Trip::STATUS_CANCELLED, 'closed_by' => 'driver']);

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
