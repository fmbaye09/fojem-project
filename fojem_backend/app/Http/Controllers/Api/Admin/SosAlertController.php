<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\Moderation\UpdateSosAlertRequest;
use App\Models\SosAlert;
use App\Services\AuditLogger;
use Illuminate\Http\Request;

class SosAlertController extends Controller
{
    public function index(Request $request)
    {
        $query = SosAlert::query()->with('user', 'booking')->latest('triggered_at');

        if ($status = $request->string('status')->value()) {
            $query->where('status', $status);
        }

        return response()->json($query->paginate($request->integer('per_page', 20)));
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

        return response()->json(['sos_alert' => $sosAlert->fresh()]);
    }
}
