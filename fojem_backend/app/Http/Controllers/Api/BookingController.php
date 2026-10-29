<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\Bookings\StoreBookingRequest;
use App\Models\Booking;
use App\Models\LuggagePhoto;
use App\Models\PlatformSetting;
use App\Models\RideRequest;
use App\Models\Trip;
use App\Services\NotificationService;
use App\Services\TripLifecycleService;
use App\Services\WalletService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class BookingController extends Controller
{
    public function __construct(private readonly NotificationService $notifications)
    {
    }
    /**
     * Passenger requests a seat on a trip. Does NOT touch seats_available
     * yet - the seat is only actually blocked when the driver accepts
     * (see accept()), so a flood of pending requests can't starve a trip.
     */
    public function store(StoreBookingRequest $request)
    {
        $trip = Trip::findOrFail($request->input('trip_id'));

        if ($trip->status !== Trip::STATUS_OPEN) {
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
        $boarding = $request->filled('boarding_stop_id')
            ? $stops->firstWhere('id', $request->input('boarding_stop_id'))
            : $stops->first();
        $alighting = $request->filled('alighting_stop_id')
            ? $stops->firstWhere('id', $request->input('alighting_stop_id'))
            : $stops->last();

        if (! $boarding || ! $alighting || $boarding->position >= $alighting->position) {
            throw ValidationException::withMessages([
                'alighting_stop_id' => 'Choisissez un arrêt de montée situé avant votre arrêt de descente, sur ce trajet.',
            ]);
        }

        $segmentPrice = bcsub((string) $alighting->price_from_origin, (string) $boarding->price_from_origin, 2);

        // The seat conflict check and the insert run under a lock on the
        // trip, so two passengers tapping the same seat at once can't both
        // get it.
        $booking = DB::transaction(function () use ($request, $trip, $seatNumbers, $seatCount, $hasHeavyLuggage, $boarding, $alighting, $segmentPrice) {
            Trip::whereKey($trip->id)->lockForUpdate()->first();

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
                'boarding_stop_id' => $boarding->id,
                'alighting_stop_id' => $alighting->id,
                'ride_request_id' => $request->input('ride_request_id'),
                'passenger_id' => $request->user()->id,
                'seat_count' => $seatCount,
                'seat_numbers' => $seatNumbers,
                'has_heavy_luggage' => $hasHeavyLuggage,
                'status' => Booking::STATUS_PENDING_DRIVER,
                'departure_code' => Booking::generateDepartureCode(),
                'price_charged' => bcmul($segmentPrice, (string) $seatCount, 2),
            ]);

            // The passenger is picked up at the boarding stop.
            $booking->setPickupPoint($boarding->lat, $boarding->lng);
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

        // Notify the trip's driver about the new booking request
        $driverUser = $trip->driverProfile?->user;
        if ($driverUser) {
            $this->notifications->bookingNew($driverUser, [
                'booking_id'        => $booking->id,
                'trip_id'           => $trip->id,
                // The passenger's own segment: the driver needs to know
                // where they board.
                'trip_label'        => "{$boarding->name} → {$alighting->name}",
                'passenger_name'    => $request->user()->full_name,
                'has_heavy_luggage' => $hasHeavyLuggage,
            ]);
        }

        return response()->json(['booking' => $booking->fresh()->load('luggagePhotos')], 201);
    }

    public function mine(Request $request)
    {
        TripLifecycleService::sync();

        $bookings = Booking::where('passenger_id', $request->user()->id)
            ->with(['trip.driverProfile.user', 'trip.vehicle', 'luggagePhotos'])
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

        return response()->json($query->paginate($request->integer('per_page', 20)));
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

        return response()->json($query->paginate($request->integer('per_page', 20)));
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

        DB::transaction(function () use ($booking) {
            $trip = Trip::where('id', $booking->trip_id)->lockForUpdate()->firstOrFail();

            if ($trip->seats_available < $booking->seat_count) {
                throw ValidationException::withMessages(['seats' => ['Plus assez de places.']]);
            }

            $trip->seats_available -= $booking->seat_count;
            $trip->status = $trip->seats_available === 0 ? Trip::STATUS_FULL : $trip->status;
            $trip->save();

            $booking->update(['status' => Booking::STATUS_CONFIRMED, 'confirmed_at' => now()]);
        });

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

        if (in_array($booking->status, [Booking::STATUS_COMPLETED, Booking::STATUS_NO_SHOW], true)) {
            return response()->json(['message' => 'Cette reservation ne peut plus etre annulee.'], 422);
        }

        $wasConfirmed = $booking->status === Booking::STATUS_CONFIRMED;
        $newStatus = $isPassenger ? Booking::STATUS_CANCELLED_PASSENGER : Booking::STATUS_CANCELLED_DRIVER;

        DB::transaction(function () use ($booking, $wasConfirmed, $newStatus) {
            if ($wasConfirmed) {
                // give the seat back
                Trip::where('id', $booking->trip_id)->lockForUpdate()->increment('seats_available', $booking->seat_count);
                Trip::where('id', $booking->trip_id)->where('status', Trip::STATUS_FULL)->update(['status' => Trip::STATUS_OPEN]);
            }

            $booking->update(['status' => $newStatus]);
        });

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
