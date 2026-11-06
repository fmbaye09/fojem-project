<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\Bookings\StoreBookingRequest;
use App\Models\Booking;
use App\Models\LuggagePhoto;
use App\Models\PlatformSetting;
use App\Models\RideRequest;
use App\Models\Trip;
use App\Models\TripStop;
use App\Services\NotificationService;
use App\Services\ReputationService;
use App\Services\StopInsertionPlanner;
use App\Services\TripLifecycleService;
use App\Services\TripProgressService;
use App\Services\WalletService;
use Carbon\CarbonImmutable;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class BookingController extends Controller
{
    /** Une position plus ancienne ne prouve pas que le chauffeur est sur place. */
    private const NO_SHOW_FIX_SECONDS = 120;

    public function __construct(
        private readonly NotificationService $notifications,
        private readonly ReputationService $reputation,
        private readonly TripProgressService $progress,
        private readonly StopInsertionPlanner $stopInsertion,
    ) {
    }
    /**
     * Passenger requests a seat on a trip. Does NOT touch seats_available
     * yet - the seat is only actually blocked when the driver accepts
     * (see accept()), so a flood of pending requests can't starve a trip.
     *
     * A trip already on the road (if its driver accepts it) is booked at a
     * stop not reached yet; the booking is confirmed at once and its seats
     * taken, so the driver has nothing to accept while driving.
     */
    public function store(StoreBookingRequest $request)
    {
        $trip = Trip::findOrFail($request->input('trip_id'));
        $enRoute = $trip->status === Trip::STATUS_IN_PROGRESS && $trip->accepts_en_route;

        if ($trip->status !== Trip::STATUS_OPEN && ! $enRoute) {
            return response()->json(['message' => 'Ce trajet n\'accepte plus de reservations.'], 422);
        }

        $user = $request->user();

        // Le chauffeur ne peut pas reserver son propre trajet
        if ($user->driver && $trip->driver_id === $user->driver->id) {
            return response()->json(['message' => 'Vous ne pouvez pas réserver votre propre trajet.'], 422);
        }

        // Le client ne doit pas pouvoir reserver 2 fois la meme voiture / le meme trajet
        $existingBooking = Booking::where('trip_id', $trip->id)
            ->where('passenger_id', $user->id)
            ->whereIn('status', [Booking::STATUS_PENDING_DRIVER, Booking::STATUS_CONFIRMED])
            ->first();

        if ($existingBooking) {
            if ($existingBooking->status === Booking::STATUS_PENDING_DRIVER) {
                return response()->json([
                    'booking' => $existingBooking->load('luggagePhotos'),
                ], 200);
            }

            return response()->json(['message' => 'Vous avez déjà une réservation confirmée sur ce trajet.'], 422);
        }

        // Seats picked on the vehicle plan; when present they define the
        // seat count. Older clients only send seat_count.
        $seatNumbers = $request->has('seat_numbers')
            ? array_values(array_map('strval', $request->input('seat_numbers')))
            : null;
        $seatCount = $seatNumbers !== null ? count($seatNumbers) : (int) $request->input('seat_count', 1);

        if ($seatCount > $trip->seats_available) {
            return response()->json(['message' => 'Pas assez de places disponibles.'], 422);
        }

        $hasHeavyLuggage = $request->boolean('has_heavy_luggage');

        // Passengers board and leave at the driver's meeting points. Without
        // explicit stops (older app versions) the booking spans the whole trip.
        $stops = $trip->ensureStops()->stops;

        // Or at a point they propose instead (before departure only); the
        // stop is created if the driver accepts.
        $proposal = null;
        if ($request->filled('proposed_stop')) {
            if ($enRoute) {
                throw ValidationException::withMessages([
                    'proposed_stop' => 'Le trajet est déjà parti : choisissez un de ses arrêts.',
                ]);
            }
            $input = $request->input('proposed_stop');
            $proposal = $this->stopInsertion->preview(
                $trip, $input['role'], (float) $input['lat'], (float) $input['lng'], $input['name'] ?? null, $input['address'] ?? null,
            );
        }
        $proposedRole = $proposal['role'] ?? null;

        $boarding = $proposedRole === StopInsertionPlanner::ROLE_BOARDING ? null : ($request->filled('boarding_stop_id')
            ? $stops->firstWhere('id', $request->input('boarding_stop_id'))
            : $stops->first());
        $alighting = $proposedRole === StopInsertionPlanner::ROLE_ALIGHTING ? null : ($request->filled('alighting_stop_id')
            ? $stops->firstWhere('id', $request->input('alighting_stop_id'))
            : $stops->last());

        // The proposed point sits just after the stop it follows.
        $proposalRank = $proposal ? $stops->firstWhere('id', $proposal['after_stop_id'])->position + 0.5 : null;
        $boardingRank = $boarding?->position ?? ($proposedRole === StopInsertionPlanner::ROLE_BOARDING ? $proposalRank : null);
        $alightingRank = $alighting?->position ?? ($proposedRole === StopInsertionPlanner::ROLE_ALIGHTING ? $proposalRank : null);

        if ($boardingRank === null || $alightingRank === null || $boardingRank >= $alightingRank) {
            throw ValidationException::withMessages([
                'alighting_stop_id' => 'Choisissez un arrêt de montée situé avant votre arrêt de descente, sur ce trajet.',
            ]);
        }
        $boardingName = $boarding?->name ?? $proposal['name'];
        $alightingName = $alighting?->name ?? $proposal['name'];

        if ($enRoute) {
            if (! $this->progress->canBoardEnRoute($trip, $boarding)) {
                throw ValidationException::withMessages([
                    'boarding_stop_id' => "Le chauffeur passe trop tôt à {$boarding->name} : choisissez un arrêt plus loin sur son trajet.",
                ]);
            }
            if ($this->reputation->recentNoShows($user) >= ReputationService::NO_SHOW_LIMIT) {
                return response()->json([
                    'message' => 'Après plusieurs absences récentes, vous ne pouvez plus réserver un trajet déjà parti. Réservez un trajet avant son départ.',
                ], 422);
            }
        }

        $segmentPrice = bcsub(
            (string) ($alighting?->price_from_origin ?? $proposal['price_from_origin']),
            (string) ($boarding?->price_from_origin ?? $proposal['price_from_origin']),
            2,
        );

        // The seat conflict check and the insert run under a lock on the
        // trip, so two passengers tapping the same seat at once can't both
        // get it.
        $booking = DB::transaction(function () use ($request, $trip, $seatNumbers, $seatCount, $hasHeavyLuggage, $boarding, $alighting, $segmentPrice, $enRoute, $proposal) {
            $locked = Trip::whereKey($trip->id)->lockForUpdate()->first();

            if ($enRoute) {
                if ($locked->seats_available < $seatCount) {
                    throw ValidationException::withMessages(['seats' => 'Pas assez de places disponibles.']);
                }
                $locked->decrement('seats_available', $seatCount);
            }

            if ($seatNumbers !== null) {
                $taken = array_values(array_intersect($seatNumbers, Booking::occupiedSeatNumbers($trip->id)));
                if ($taken !== []) {
                    throw ValidationException::withMessages([
                        'seat_numbers' => count($taken) === 1
                            ? "La place {$taken[0]} vient d'être réservée. Choisissez-en une autre."
                            : 'Les places ' . implode(', ', $taken) . " viennent d'être réservées. Choisissez-en d'autres.",
                    ]);
                }
            }

            $booking = new Booking([
                'trip_id' => $trip->id,
                'boarding_stop_id' => $boarding?->id,
                'alighting_stop_id' => $alighting?->id,
                'proposed_stop' => $proposal,
                'ride_request_id' => $request->input('ride_request_id'),
                'passenger_id' => $request->user()->id,
                'seat_count' => $seatCount,
                'seat_numbers' => $seatNumbers,
                'has_heavy_luggage' => $hasHeavyLuggage,
                'status' => $enRoute ? Booking::STATUS_CONFIRMED : Booking::STATUS_PENDING_DRIVER,
                'confirmed_at' => $enRoute ? now() : null,
                'departure_code' => Booking::generateDepartureCode(),
                'price_charged' => bcmul($segmentPrice, (string) $seatCount, 2),
            ]);

            // The passenger is picked up at the boarding stop.
            $booking->setPickupPoint($boarding?->lat ?? $proposal['lat'], $boarding?->lng ?? $proposal['lng']);
            $booking->save();

            return $booking;
        });

        // Enregistrement des photos de bagages si fournies
        if ($request->hasFile('luggage_photos')) {
            $folder = "luggage-photos/{$booking->id}";
            foreach ($request->file('luggage_photos') as $photoFile) {
                if ($photoFile && $photoFile->isValid()) {
                    $path = $photoFile->store($folder, 'public');
                    $photoUrl = $request->schemeAndHttpHost() . '/storage/' . $path;
                    LuggagePhoto::create([
                        'booking_id' => $booking->id,
                        'photo_url' => $photoUrl,
                        'uploaded_at' => now(),
                    ]);
                }
            }
        }

        if ($rideRequestId = $request->input('ride_request_id')) {
            RideRequest::where('id', $rideRequestId)
                ->where('passenger_id', $request->user()->id)
                ->update(['status' => RideRequest::STATUS_MATCHED]);
        }

        $driverUser = $trip->driverProfile?->user;
        if ($enRoute) {
            // Rien à valider en roulant : le chauffeur est seulement prévenu.
            $eta = $this->progress->etaFor($trip, $boarding);
            if ($driverUser) {
                $this->notifications->system(
                    $driverUser,
                    '🚗 Nouveau passager en route',
                    "{$user->full_name} monte à {$boarding->name}".($eta ? ' vers '.$eta->format('H:i') : '').'. Réservation confirmée automatiquement.',
                    ['booking_id' => $booking->id, 'trip_id' => $trip->id],
                );
            }
            $this->notifications->bookingConfirmed($user, [
                'booking_id' => $booking->id,
                'trip_id' => $trip->id,
                'trip_label' => "{$boarding->name} → {$alighting->name}",
            ]);
        } elseif ($driverUser) {
            // Notify the trip's driver about the new booking request
            $this->notifications->bookingNew($driverUser, [
                'booking_id'        => $booking->id,
                'trip_id'           => $trip->id,
                // The passenger's own segment: the driver needs to know
                // where they board.
                'trip_label'        => "{$boardingName} → {$alightingName}",
                'passenger_name'    => $request->user()->full_name,
                'has_heavy_luggage' => $hasHeavyLuggage,
            ] + ($proposal ? [
                'proposed_stop_name' => $proposal['name'],
                'detour_minutes'     => $proposal['detour_minutes'],
            ] : []));
        }

        return response()->json(['booking' => $booking->fresh()->load('luggagePhotos')], 201);
    }

    public function mine(Request $request)
    {
        TripLifecycleService::sync();

        // review_exists : l'app n'ouvre pas la notation d'un trajet déjà noté.
        $bookings = Booking::where('passenger_id', $request->user()->id)
            ->with(['trip.driverProfile.user', 'trip.vehicle', 'luggagePhotos'])
            ->withExists('review')
            ->orderByDesc('created_at')
            ->paginate(20);

        return response()->json($bookings);
    }

    /**
     * All bookings on every trip belonging to the authenticated driver -
     * a global "requests received" dashboard, since bookings/mine only
     * ever covers the passenger side of the relation.
     */
    public function received(Request $request)
    {
        TripLifecycleService::sync();

        $driver = $request->user()->driver;

        if (! $driver) {
            return response()->json(['message' => 'Profil chauffeur requis.'], 403);
        }

        $query = Booking::whereHas('trip', fn ($q) => $q->where('driver_id', $driver->id))
            ->with(['passenger', 'trip', 'luggagePhotos'])
            ->orderByDesc('created_at');

        if ($status = $request->string('status')->value()) {
            $query->where('status', $status);
        }

        $page = $query->paginate($request->integer('per_page', 20));
        $this->reputation->attachTo($page->getCollection());

        return response()->json($page);
    }

    /** Bookings on one specific trip - only that trip's driver may list them. */
    public function forTrip(Request $request, Trip $trip)
    {
        TripLifecycleService::sync();

        $driver = $request->user()->driver;

        if (! $driver || $trip->driver_id !== $driver->id) {
            return response()->json(['message' => 'Non autorise.'], 403);
        }

        $query = Booking::where('trip_id', $trip->id)
            ->with(['passenger', 'luggagePhotos'])
            ->orderByDesc('created_at');

        if ($status = $request->string('status')->value()) {
            $query->where('status', $status);
        }

        $page = $query->paginate($request->integer('per_page', 20));
        $this->reputation->attachTo($page->getCollection());

        return response()->json($page);
    }

    /** A single booking - visible to its passenger or the trip's driver only. */
    public function show(Request $request, Booking $booking)
    {
        $user = $request->user();
        $isPassenger = $booking->passenger_id === $user->id;
        $isDriver = $user->driver && $booking->trip->driver_id === $user->driver->id;

        if (! $isPassenger && ! $isDriver) {
            return response()->json(['message' => 'Non autorise.'], 403);
        }

        $booking->load(['passenger', 'trip.driverProfile.user', 'trip.vehicle', 'luggagePhotos']);

        return response()->json(['booking' => $booking]);
    }

    /**
     * Driver accepts a booking: locks the trip row, re-checks seat
     * availability, decrements seats_available, marks the trip full if it
     * hits zero. All inside one DB transaction to avoid overselling seats
     * under concurrent accepts.
     */
    public function accept(Request $request, Booking $booking)
    {
        $this->authorizeDriverForBooking($request, $booking);

        if ($booking->status !== Booking::STATUS_PENDING_DRIVER) {
            return response()->json(['message' => 'Cette reservation ne peut plus etre acceptee.'], 422);
        }

        // Un arrêt proposé par le passager s'ajoute au trajet, avant le départ seulement.
        $proposal = $booking->proposed_stop;
        $addsStop = is_array($proposal) && empty($proposal['inserted_stop_id']);
        if ($addsStop && ! in_array($booking->trip->status, [Trip::STATUS_OPEN, Trip::STATUS_FULL], true)) {
            return response()->json(['message' => 'Le trajet est déjà parti : l’arrêt proposé ne peut plus être ajouté.'], 422);
        }

        $inserted = null;
        DB::transaction(function () use ($booking, $addsStop, $proposal, &$inserted) {
            $trip = Trip::where('id', $booking->trip_id)->lockForUpdate()->firstOrFail();

            if ($trip->seats_available < $booking->seat_count) {
                throw ValidationException::withMessages(['seats' => ['Plus assez de places.']]);
            }

            if ($addsStop) {
                $inserted = $this->stopInsertion->insert($trip, $proposal);
                $this->attachInsertedStop($booking, $proposal, $inserted);
            }

            $trip->seats_available -= $booking->seat_count;
            // Un trajet déjà parti reste « en cours », même plein.
            if ($trip->seats_available === 0 && $trip->status === Trip::STATUS_OPEN) {
                $trip->status = Trip::STATUS_FULL;
            }
            $trip->save();

            $booking->fill(['status' => Booking::STATUS_CONFIRMED, 'confirmed_at' => now()])->save();
        });

        if ($inserted !== null && $inserted['shift_minutes'] > 0) {
            $this->notifyLaterPassengers($booking, $inserted['stop'], $inserted['shift_minutes']);
        }

        // Notify the passenger
        $passenger = $booking->passenger;
        if ($passenger) {
            $trip = $booking->trip;
            $this->notifications->bookingConfirmed($passenger, [
                'booking_id' => $booking->id,
                'trip_id'    => $trip->id,
                'trip_label' => ($trip->origin_name ?? 'Départ') . ' → ' . ($trip->destination_name ?? 'Arrivée'),
            ]);
        }

        return response()->json(['booking' => $booking->fresh()]);
    }

    public function reject(Request $request, Booking $booking)
    {
        $this->authorizeDriverForBooking($request, $booking);

        if ($booking->status !== Booking::STATUS_PENDING_DRIVER) {
            return response()->json(['message' => 'Cette reservation ne peut plus etre refusee.'], 422);
        }

        $booking->update(['status' => Booking::STATUS_REJECTED]);

        // Notify the passenger
        $passenger = $booking->passenger;
        if ($passenger) {
            $trip = $booking->trip;
            $this->notifications->bookingRejected($passenger, [
                'booking_id' => $booking->id,
                'trip_id'    => $trip->id,
                'trip_label' => ($trip->origin_name ?? 'Départ') . ' → ' . ($trip->destination_name ?? 'Arrivée'),
            ]);
        }

        return response()->json(['booking' => $booking->fresh()]);
    }

    /** Cancellable by either the passenger or the trip's driver. */
    public function cancel(Request $request, Booking $booking)
    {
        $user = $request->user();
        $isPassenger = $booking->passenger_id === $user->id;
        $isDriver = $user->driver && $booking->trip->driver_id === $user->driver->id;

        if (! $isPassenger && ! $isDriver) {
            return response()->json(['message' => 'Non autorise.'], 403);
        }

        if (in_array($booking->status, [Booking::STATUS_COMPLETED, Booking::STATUS_NO_SHOW, Booking::STATUS_MISSED], true)) {
            return response()->json(['message' => 'Cette reservation ne peut plus etre annulee.'], 422);
        }

        $wasConfirmed = $booking->status === Booking::STATUS_CONFIRMED;
        $newStatus = $isPassenger ? Booking::STATUS_CANCELLED_PASSENGER : Booking::STATUS_CANCELLED_DRIVER;

        DB::transaction(function () use ($booking, $wasConfirmed, $newStatus) {
            if ($wasConfirmed) {
                $this->releaseSeats($booking);
            }

            $booking->update(['status' => $newStatus, 'cancelled_at' => now()]);
        });

        // L'arrêt ajouté pour ce passager quitte le trajet si personne d'autre n'y monte ou n'y descend.
        $insertedStopId = $booking->proposed_stop['inserted_stop_id'] ?? null;
        if ($insertedStopId) {
            $this->stopInsertion->removeIfUnused($booking->trip, $insertedStopId);
        }

        // Une annulation de dernière minute pèse sur la fiabilité du passager.
        if ($isPassenger) {
            $this->reputation->refresh($user);
        }

        // Notify the other party
        $trip = $booking->trip;
        $tripLabel = ($trip->origin_name ?? 'Départ') . ' → ' . ($trip->destination_name ?? 'Arrivée');
        if ($isPassenger) {
            $driverUser = $trip->driverProfile?->user;
            if ($driverUser) {
                $this->notifications->bookingCancelled($driverUser, $user->full_name, [
                    'booking_id' => $booking->id,
                    'trip_id'    => $trip->id,
                    'trip_label' => $tripLabel,
                ]);
            }
        } else {
            $passenger = $booking->passenger;
            if ($passenger) {
                $this->notifications->bookingCancelled($passenger, 'Le chauffeur', [
                    'booking_id' => $booking->id,
                    'trip_id'    => $trip->id,
                    'trip_label' => $tripLabel,
                ]);
            }
        }

        return response()->json(['booking' => $booking->fresh()]);
    }

    public function complete(Request $request, Booking $booking, WalletService $wallets)
    {
        $this->authorizeDriverForBooking($request, $booking);

        if ($booking->status !== Booking::STATUS_CONFIRMED) {
            return response()->json(['message' => 'Seule une reservation confirmee peut etre terminee.'], 422);
        }

        DB::transaction(function () use ($booking, $wallets) {
            $booking->update([
                'status' => Booking::STATUS_COMPLETED,
                'started_at' => $booking->started_at ?? now(),
                'completed_at' => now(),
            ]);

            $this->creditDriverForBooking($booking, $wallets);
        });

        // Notify the passenger the trip is done
        $passenger = $booking->passenger;
        if ($passenger) {
            $this->reputation->refresh($passenger);
            $trip = $booking->trip;
            $this->notifications->bookingCompleted($passenger, [
                'booking_id' => $booking->id,
                'trip_id'    => $trip->id,
                'trip_label' => ($trip->origin_name ?? 'Départ') . ' → ' . ($trip->destination_name ?? 'Arrivée'),
            ]);
        }

        return response()->json(['booking' => $booking->fresh()]);
    }

    /**
     * Le chauffeur déclare un passager absent. Il doit être au point de
     * rendez-vous (position récente, que l'app envoie juste avant) et y avoir
     * attendu 5 min, comptées depuis l'heure prévue ou depuis son arrivée si
     * elle est plus tardive : un chauffeur en retard ne peut pas déclarer
     * absent un passager qui l'a attendu.
     */
    public function noShow(Request $request, Booking $booking)
    {
        $this->authorizeDriverForBooking($request, $booking);

        if ($booking->status !== Booking::STATUS_CONFIRMED || $booking->started_at !== null) {
            return response()->json(['message' => 'Seul un passager confirmé, pas encore à bord, peut être déclaré absent.'], 422);
        }

        $trip = $booking->trip;
        $stop = $booking->boardingStop ?? $trip->ensureStops()->stops->first();
        $now = CarbonImmutable::now();

        $fixAt = $trip->location_updated_at ? CarbonImmutable::instance($trip->location_updated_at) : null;
        $onSite = $stop?->reached_at !== null
            && $fixAt !== null
            && $trip->current_lat !== null
            && $fixAt->diffInSeconds($now, true) <= self::NO_SHOW_FIX_SECONDS
            && Trip::haversineMeters((float) $trip->current_lat, (float) $trip->current_lng, $stop->lat, $stop->lng)
                <= TripProgressService::STOP_REACHED_METERS;

        $allowedAt = $stop?->waitUntil($trip->scheduled_at);
        $leftAt = $stop?->left_at ? CarbonImmutable::instance($stop->left_at) : null;
        // Reparti une fois l'attente écoulée : la preuve reste acquise en route.
        $waitedThenLeft = $leftAt !== null && $allowedAt !== null && $leftAt->greaterThanOrEqualTo($allowedAt);

        if (! $onSite && ! $waitedThenLeft) {
            return response()->json([
                'message' => $leftAt !== null && $allowedAt !== null
                    ? "Vous avez quitté {$stop->name} à {$leftAt->format('H:i')}, avant la fin de l'attente ({$allowedAt->format('H:i')}) : ce passager ne peut pas être déclaré absent."
                    : 'Rendez-vous au point de rendez-vous ('.($stop?->name ?? 'montée').') avec la localisation activée pour déclarer une absence.',
            ], 422);
        }

        if (! $waitedThenLeft && $now->lessThan($allowedAt)) {
            $minutes = (int) ceil($now->diffInSeconds($allowedAt, true) / 60);

            return response()->json([
                'message' => "Attendez encore {$minutes} min : le passager a jusqu'à {$allowedAt->format('H:i')} pour vous rejoindre.",
                'allowed_at' => $allowedAt->toIso8601String(),
            ], 422);
        }

        DB::transaction(function () use ($booking) {
            $this->releaseSeats($booking);
            $booking->update(['status' => Booking::STATUS_NO_SHOW, 'no_show_at' => now()]);
        });

        $passenger = $booking->passenger;
        if ($passenger) {
            $this->reputation->refresh($passenger);
            $this->notifications->system(
                $passenger,
                '🚫 Absence signalée',
                "Le chauffeur ne vous a pas trouvé au point de rendez-vous ({$stop->name}) et a repris la route. Votre réservation est annulée.",
                ['booking_id' => $booking->id, 'trip_id' => $trip->id],
            );
        }

        return response()->json(['booking' => $booking->fresh()]);
    }

    /**
     * La réservation monte ou descend désormais à l'arrêt ajouté pour elle :
     * son prix suit celui de l'arrêt, et le tronçon doit rester dans l'ordre.
     */
    private function attachInsertedStop(Booking $booking, array $proposal, array $inserted): void
    {
        $stop = $inserted['stop'];
        if ($proposal['role'] === StopInsertionPlanner::ROLE_BOARDING) {
            $booking->boarding_stop_id = $stop->id;
            $booking->setPickupPoint($stop->lat, $stop->lng);
        } else {
            $booking->alighting_stop_id = $stop->id;
        }
        $booking->unsetRelation('boardingStop')->unsetRelation('alightingStop');

        $boarding = TripStop::find($booking->boarding_stop_id);
        $alighting = TripStop::find($booking->alighting_stop_id);
        if (! $boarding || ! $alighting || $boarding->position >= $alighting->position) {
            throw ValidationException::withMessages([
                'proposed_stop' => 'L’arrêt proposé ne tombe plus entre la montée et la descente du passager : refusez la demande.',
            ]);
        }

        $booking->price_charged = bcmul(
            bcsub((string) $alighting->price_from_origin, (string) $boarding->price_from_origin, 2),
            (string) $booking->seat_count,
            2,
        );
        $booking->proposed_stop = [
            ...$proposal,
            'inserted_stop_id' => $stop->id,
            'detour_minutes' => $inserted['shift_minutes'],
        ];
    }

    /** Les passagers qui montent après le nouvel arrêt apprennent leur nouvelle heure. */
    private function notifyLaterPassengers(Booking $booking, TripStop $stop, int $minutes): void
    {
        $others = Booking::where('trip_id', $booking->trip_id)
            ->whereKeyNot($booking->id)
            ->where('status', Booking::STATUS_CONFIRMED)
            ->with('passenger')
            ->get();

        foreach ($others as $other) {
            $boarding = $other->boardingStop;
            if (! $other->passenger || ! $boarding || $boarding->position <= $stop->position) {
                continue;
            }
            $this->notifications->system(
                $other->passenger,
                '🕒 Horaire modifié',
                "Le chauffeur ajoute un arrêt à {$stop->name}. Il passera à {$boarding->name}"
                    .($boarding->scheduled_at ? ' vers '.$boarding->scheduled_at->format('H:i') : '')
                    .", environ {$minutes} min plus tard que prévu.",
                ['booking_id' => $other->id, 'trip_id' => $other->trip_id],
            );
        }
    }

    /** Rend les places d'une réservation confirmée ; un trajet parti reste « en cours ». */
    private function releaseSeats(Booking $booking): void
    {
        Trip::where('id', $booking->trip_id)->lockForUpdate()->increment('seats_available', $booking->seat_count);
        Trip::where('id', $booking->trip_id)->where('status', Trip::STATUS_FULL)->update(['status' => Trip::STATUS_OPEN]);
    }

    /**
     * Credits the driver's wallet for a just-completed booking, net of the
     * applicable zone commission, via WalletService (the only allowed
     * write path into wallets.balance - never duplicated here).
     *
     * There is no geo-zone <-> trip linkage anywhere in the schema yet
     * (platform_settings.zone_name is a free-text label; trips carry no
     * zone_id/zone reference), so as a documented simplification we use
     * the commission_pct of the first platform_settings row found, and
     * default to a 0% commission - crediting the driver the full
     * price_charged - when no platform_settings row exists at all, rather
     * than failing the completion transaction over missing pricing
     * config.
     */
    private function creditDriverForBooking(Booking $booking, WalletService $wallets): void
    {
        $driver = $booking->trip->driverProfile;
        $wallet = $driver?->user?->wallet;

        if (! $wallet) {
            return;
        }

        $commissionPct = (float) (PlatformSetting::query()->value('commission_pct') ?? 0);
        $net = bcmul((string) $booking->price_charged, (string) (1 - $commissionPct / 100), 2);

        $wallets->credit(
            $wallet,
            'payment',
            (float) $net,
            'wallet',
            'booking_payment:'.$booking->id,
            $booking->id,
        );
    }

    /**
     * Driver validates passenger onboarding via QR code or 6-digit departure code.
     */
    public function boardPassenger(Request $request, Trip $trip)
    {
        $driver = $request->user()->driver;
        abort_unless($driver && $trip->driver_id === $driver->id, 403, 'Non autorisé.');

        $request->validate(['code' => 'required|string']);
        $rawCode = trim($request->input('code'));

        // Formats acceptés : "FOJEM:{booking_id}:{departure_code}", l'id brut
        // de la réservation, ou le code de départ dicté par le passager.
        $bookingId = null;
        $code = $rawCode;
        if (str_contains($rawCode, ':')) {
            $parts = explode(':', $rawCode);
            $code = trim((string) end($parts));
            foreach ($parts as $part) {
                if (\Illuminate\Support\Str::isUuid(trim($part))) {
                    $bookingId = trim($part);
                }
            }
        } elseif (\Illuminate\Support\Str::isUuid($rawCode)) {
            $bookingId = $rawCode;
        }
        $code = strtoupper($code);

        // Ne JAMAIS comparer la colonne uuid `id` à une valeur non-uuid :
        // PostgreSQL lève "invalid input syntax for type uuid" (erreur 500).
        $booking = Booking::with('passenger')
            ->where('trip_id', $trip->id)
            ->where(function ($q) use ($code, $bookingId) {
                if ($bookingId) {
                    $q->where('id', $bookingId);
                } else {
                    $q->where('departure_code', $code);
                }
            })
            ->first();

        if (! $booking) {
            return response()->json(['message' => 'Code ou QR code invalide. Aucun passager correspondant trouvé pour ce trajet.'], 422);
        }

        if ($booking->status === Booking::STATUS_PENDING_DRIVER) {
            return response()->json(['message' => 'Cette réservation n\'a pas encore été acceptée. Acceptez-la avant de valider l\'embarquement.'], 422);
        }

        if ($booking->status === Booking::STATUS_COMPLETED) {
            return response()->json([
                'message' => 'Ce trajet et cette réservation sont déjà terminés.',
                'already_completed' => true,
            ], 422);
        }

        if ($booking->status !== Booking::STATUS_CONFIRMED) {
            return response()->json(['message' => 'Cette réservation n\'est pas active (statut : '.$booking->status.').'], 422);
        }

        if ($booking->started_at !== null) {
            $passengerName = $booking->passenger?->full_name ?? $booking->passenger?->name ?? 'Ce passager';
            return response()->json([
                'message' => "$passengerName a déjà été scanné et est déjà marqué à bord.",
                'already_boarded' => true,
                'booking' => $booking,
            ]);
        }

        $booking->update(['started_at' => now()]);

        // Notifier le passager
        $passenger = $booking->passenger;
        if ($passenger) {
            $tripLabel = ($trip->origin_name ?? 'Départ') . ' → ' . ($trip->destination_name ?? 'Arrivée');
            $this->notifications->system(
                $passenger,
                '🎫 Présence confirmée à bord',
                "Votre présence à bord du trajet $tripLabel a été validée par le chauffeur. Bon voyage !",
                ['booking_id' => $booking->id, 'trip_id' => $trip->id]
            );
        }

        return response()->json([
            'message' => 'Présence validée avec succès pour ' . ($passenger->name ?? 'le passager') . ' !',
            'booking' => $booking->fresh()->load('passenger'),
        ]);
    }

    /**
     * Driver manually toggles boarding for a confirmed booking.
     */
    public function board(Request $request, Booking $booking)
    {
        $this->authorizeDriverForBooking($request, $booking);

        if ($booking->status !== Booking::STATUS_CONFIRMED) {
            return response()->json(['message' => 'Seule une réservation confirmée peut être validée à bord.'], 422);
        }

        $booking->update(['started_at' => now()]);

        return response()->json([
            'message' => 'Présence validée avec succès.',
            'booking' => $booking->fresh()->load('passenger'),
        ]);
    }

    private function authorizeDriverForBooking(Request $request, Booking $booking): void
    {
        $driver = $request->user()->driver;

        abort_unless($driver && $booking->trip->driver_id === $driver->id, 403, 'Non autorise.');
    }
}
