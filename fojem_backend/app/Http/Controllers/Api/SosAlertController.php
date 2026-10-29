<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\Sos\TriggerSosRequest;
use App\Models\Booking;
use App\Models\SosAlert;
use App\Models\Trip;
use Illuminate\Http\Request;

/**
 * SOS déclenché depuis l'app (passager ou chauffeur) pendant un trajet.
 * L'app envoie ensuite sa position toutes les 15 s et l'enregistrement
 * audio par morceaux de 30 s, jusqu'à « Je suis en sécurité ». Les admins
 * suivent l'alerte en direct dans le dashboard.
 */
class SosAlertController extends Controller
{
    /** Un second appui pendant une alerte en cours la réutilise. */
    private const REUSE_WINDOW_MINUTES = 15;

    public function store(TriggerSosRequest $request)
    {
        $user = $request->user();
        $role = $request->input('role', SosAlert::ROLE_PASSENGER);
        $booking = $request->filled('booking_id') ? Booking::find($request->input('booking_id')) : null;
        $trip = $request->filled('trip_id') ? Trip::find($request->input('trip_id')) : $booking?->trip;

        abort_if($booking && $booking->passenger_id !== $user->id, 403, 'Réservation d\'un autre utilisateur.');
        if ($role === SosAlert::ROLE_DRIVER) {
            abort_unless($trip && $user->driver && $trip->driver_id === $user->driver->id, 403, 'Trajet d\'un autre chauffeur.');
        }

        $lat = (float) $request->input('lat');
        $lng = (float) $request->input('lng');

        $alert = SosAlert::where('user_id', $user->id)
            ->whereNull('ended_at')
            ->where('status', '!=', SosAlert::STATUS_RESOLVED)
            ->where('triggered_at', '>=', now()->subMinutes(self::REUSE_WINDOW_MINUTES))
            ->latest('triggered_at')
            ->first();

        if (! $alert) {
            $alert = new SosAlert([
                'user_id' => $user->id,
                'booking_id' => $booking?->id,
                'trip_id' => $trip?->id,
                'role' => $role,
                'triggered_at' => now(),
                'status' => SosAlert::STATUS_OPEN,
            ]);
            $alert->setLocationPoint($lat, $lng);
        }

        $alert->recordPosition($lat, $lng)->save();

        // Le SMS au contact d'urgence (notified_at) est prévu mais pas encore
        // branché : il faut un fournisseur SMS.

        return response()->json(['sos_alert' => $alert->fresh()], 201);
    }

    public function location(Request $request, SosAlert $sosAlert)
    {
        $this->authorizeOwner($request, $sosAlert);
        $data = $request->validate([
            'lat' => ['required', 'numeric', 'between:-90,90'],
            'lng' => ['required', 'numeric', 'between:-180,180'],
        ]);

        $sosAlert->recordPosition((float) $data['lat'], (float) $data['lng'])->save();

        return response()->json(['ok' => true]);
    }

    /** Morceau audio, sur le disque privé : seul l'admin peut l'écouter. */
    public function recording(Request $request, SosAlert $sosAlert)
    {
        $this->authorizeOwner($request, $sosAlert);
        $request->validate([
            'audio' => ['required', 'file', 'mimetypes:audio/mp4,audio/x-m4a,audio/m4a,audio/aac,audio/mpeg,video/mp4', 'max:5120'],
            'duration_ms' => ['required', 'integer', 'min:1', 'max:120000'],
        ]);

        $path = $request->file('audio')->store("sos-recordings/{$sosAlert->id}", 'local');
        $recording = $sosAlert->recordings()->create([
            'file_path' => $path,
            'duration_ms' => $request->integer('duration_ms'),
        ]);

        return response()->json(['recording' => $recording], 201);
    }

    /** « Je suis en sécurité » : l'alerte reste ouverte pour l'admin. */
    public function end(Request $request, SosAlert $sosAlert)
    {
        $this->authorizeOwner($request, $sosAlert);
        $sosAlert->update(['ended_at' => $sosAlert->ended_at ?? now()]);

        return response()->json(['sos_alert' => $sosAlert->fresh()]);
    }

    private function authorizeOwner(Request $request, SosAlert $sosAlert): void
    {
        abort_unless($sosAlert->user_id === $request->user()->id, 403, 'Alerte d\'un autre utilisateur.');
    }
}
