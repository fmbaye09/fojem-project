<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\Moderation\UpdateSosAlertRequest;
use App\Models\Booking;
use App\Models\SosAlert;
use App\Models\SosRecording;
use App\Models\User;
use App\Services\AuditLogger;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

class SosAlertController extends Controller
{
    private const RELATIONS = [
        'user.emergencyContact',
        'trip.driverProfile.user.emergencyContact',
        'trip.vehicle',
        'trip.bookings.passenger',
        'booking',
        'recordings',
        'handledByAdmin',
    ];

    public function index(Request $request)
    {
        $query = SosAlert::query()->with(self::RELATIONS)->latest('triggered_at');

        if ($status = $request->string('status')->value()) {
            $query->where('status', $status);
        }

        $page = $query->paginate($request->integer('per_page', 20));
        $page->getCollection()->transform(fn (SosAlert $alert) => $this->present($alert));

        return response()->json($page);
    }

    public function show(SosAlert $sosAlert)
    {
        return response()->json(['sos_alert' => $this->present($sosAlert->load(self::RELATIONS))]);
    }

    /** Audio d'un morceau d'enregistrement (disque privé, admin authentifié). */
    public function recording(SosAlert $sosAlert, SosRecording $recording)
    {
        abort_if($recording->sos_alert_id !== $sosAlert->id, 404);

        return Storage::disk('local')->response($recording->file_path, null, ['Content-Type' => 'audio/mp4']);
    }

    public function update(UpdateSosAlertRequest $request, SosAlert $sosAlert)
    {
        $admin = $request->user();
        $old = ['status' => $sosAlert->status, 'resolution_notes' => $sosAlert->resolution_notes];

        $sosAlert->update([
            'status' => $request->string('status')->value(),
            'resolution_notes' => $request->input('resolution_notes', $sosAlert->resolution_notes),
            'handled_by_admin_id' => $admin->id,
        ]);

        AuditLogger::logFromRequest(
            $request,
            'sos_alert.updated',
            'sos_alert',
            $sosAlert->id,
            $old,
            ['status' => $sosAlert->status, 'resolution_notes' => $sosAlert->resolution_notes],
        );

        return response()->json(['sos_alert' => $this->present($sosAlert->fresh()->load(self::RELATIONS))]);
    }

    /** Fiche complète d'une alerte pour l'agent qui la traite. */
    private function present(SosAlert $alert): array
    {
        $trip = $alert->trip;
        $driverUser = $trip?->driverProfile?->user;

        return [
            'id' => $alert->id,
            'status' => $alert->status,
            'role' => $alert->role,
            'triggered_at' => $alert->triggered_at,
            'ended_at' => $alert->ended_at,
            'last_location_at' => $alert->last_location_at,
            'last_lat' => $alert->last_lat,
            'last_lng' => $alert->last_lng,
            'path' => $alert->path ?? [],
            'resolution_notes' => $alert->resolution_notes,
            'handled_by' => $alert->handledByAdmin?->full_name,
            'user' => $this->person($alert->user),
            'booking_id' => $alert->booking_id,
            'trip' => $trip ? [
                'id' => $trip->id,
                'origin_name' => $trip->origin_name,
                'destination_name' => $trip->destination_name,
                'status' => $trip->status,
                'scheduled_at' => $trip->scheduled_at,
                'current_lat' => $trip->current_lat,
                'current_lng' => $trip->current_lng,
                'vehicle' => $trip->vehicle ? [
                    'label' => trim("{$trip->vehicle->brand} {$trip->vehicle->model} {$trip->vehicle->color}"),
                    'plate_number' => $trip->vehicle->plate_number,
                ] : null,
                'driver' => $this->person($driverUser),
                'passengers' => $trip->bookings
                    ->whereIn('status', [Booking::STATUS_CONFIRMED, Booking::STATUS_COMPLETED])
                    ->map(fn (Booking $b) => $this->person($b->passenger))
                    ->filter()
                    ->values(),
            ] : null,
            'recordings' => $alert->recordings->map(fn (SosRecording $r) => [
                'id' => $r->id,
                'duration_ms' => $r->duration_ms,
                'created_at' => $r->created_at,
                'file_endpoint' => url("/api/admin/sos-alerts/{$alert->id}/recordings/{$r->id}"),
            ]),
        ];
    }

    private function person(?User $user): ?array
    {
        if (! $user) {
            return null;
        }

        return [
            'id' => $user->id,
            'full_name' => $user->full_name,
            'phone_number' => $user->phone_number,
            'emergency_contact' => $user->emergencyContactPayload(),
        ];
    }
}
