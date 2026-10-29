<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Booking;
use App\Models\Trip;
use App\Models\TripStop;
use App\Services\TripProgressService;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

/**
 * Ce que le passager partage pendant son trajet :
 *  - sa position avec le chauffeur (sur son choix, jusqu'à l'embarquement) ;
 *  - un lien de suivi du trajet pour un proche (page web publique).
 */
class TripSharingController extends Controller
{
    /** Le lien reste valable jusqu'à 24 h après le départ. */
    private const SHARE_VALID_HOURS = 24;

    public function shareLocation(Request $request, Booking $booking)
    {
        $this->authorizePassenger($request, $booking);
        abort_unless($booking->status === Booking::STATUS_CONFIRMED && ! $booking->started_at, 422,
            'La position ne se partage qu\'avant l\'embarquement, sur une réservation confirmée.');

        $data = $request->validate([
            'lat' => ['required', 'numeric', 'between:-90,90'],
            'lng' => ['required', 'numeric', 'between:-180,180'],
        ]);
        $booking->update([
            'passenger_lat' => $data['lat'],
            'passenger_lng' => $data['lng'],
            'passenger_location_at' => now(),
        ]);

        return response()->json(['passenger_location' => $booking->fresh()->passenger_location]);
    }

    public function stopLocation(Request $request, Booking $booking)
    {
        $this->authorizePassenger($request, $booking);
        $booking->update(['passenger_lat' => null, 'passenger_lng' => null, 'passenger_location_at' => null]);

        return response()->json(['passenger_location' => null]);
    }

    /** Crée (ou renvoie) le lien de suivi à envoyer à un proche. */
    public function createLink(Request $request, Booking $booking)
    {
        $this->authorizePassenger($request, $booking);
        abort_unless(in_array($booking->status, [Booking::STATUS_PENDING_DRIVER, Booking::STATUS_CONFIRMED], true), 422,
            'Cette réservation n\'est plus active.');

        if (! $booking->shareIsActive()) {
            $departure = $booking->boardingStop?->scheduled_at ?? $booking->trip?->scheduled_at ?? now();
            $booking->update([
                'share_token' => Str::random(40),
                'share_expires_at' => max(now(), $departure)->copy()->addHours(self::SHARE_VALID_HOURS),
            ]);
        }

        return response()->json([
            'url' => url("/suivi/{$booking->share_token}"),
            'expires_at' => $booking->share_expires_at->toIso8601String(),
        ]);
    }

    /**
     * Données publiques du lien de suivi : trajet, chauffeur (prénom),
     * véhicule, position du véhicule et heures estimées. Jamais de
     * téléphone ni la position du passager.
     */
    public function publicShow(string $token, TripProgressService $progress)
    {
        $booking = Booking::where('share_token', $token)->first();
        abort_unless($booking && $booking->shareIsActive(), 404, 'Lien de suivi expiré ou invalide.');

        $trip = Trip::withLatLng()->with('vehicle', 'driverProfile.user', 'stops')->findOrFail($booking->trip_id);
        $live = $progress->live($trip);
        $etas = collect($live['etas'])->pluck('eta', 'stop_id');
        $stop = fn (?TripStop $s) => $s ? [
            'name' => $s->name,
            'address' => $s->address,
            'lat' => $s->lat,
            'lng' => $s->lng,
            'scheduled_at' => $s->scheduled_at?->toIso8601String(),
            'eta' => $etas[$s->id] ?? null,
        ] : null;

        $driverName = (string) ($trip->driverProfile?->user?->full_name ?? '');

        return response()->json([
            'passenger_first_name' => Str::before((string) $booking->passenger?->full_name, ' '),
            'status' => $trip->status,
            'boarded' => $booking->started_at !== null,
            'boarding' => $stop($booking->boardingStop),
            'alighting' => $stop($booking->alightingStop),
            'driver_first_name' => Str::before($driverName, ' ') ?: null,
            'vehicle' => $trip->vehicle ? [
                'label' => trim("{$trip->vehicle->brand} {$trip->vehicle->model} {$trip->vehicle->color}"),
                'plate_number' => $trip->vehicle->plate_number,
            ] : null,
            'vehicle_position' => $live['location_fresh']
                ? ['lat' => (float) $trip->current_lat, 'lng' => (float) $trip->current_lng, 'updated_at' => $live['location_updated_at']]
                : null,
            'route' => $trip->stops->map(fn (TripStop $s) => [$s->lat, $s->lng])->values(),
            'expires_at' => $booking->share_expires_at->toIso8601String(),
        ]);
    }

    private function authorizePassenger(Request $request, Booking $booking): void
    {
        abort_unless($booking->passenger_id === $request->user()->id, 403, 'Réservation d\'un autre utilisateur.');
    }
}
