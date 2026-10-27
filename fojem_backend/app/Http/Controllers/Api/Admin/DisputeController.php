<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\Moderation\UpdateDisputeRequest;
use App\Models\Dispute;
use App\Services\AuditLogger;
use Illuminate\Http\Request;

class DisputeController extends Controller
{
    public function index(Request $request)
    {
        $query = Dispute::query()->with('reportedBy', 'reportedAgainst', 'booking')->latest();

        if ($status = $request->string('status')->value()) {
            $query->where('status', $status);
        }

        return response()->json($query->paginate($request->integer('per_page', 20)));
    }

    public function update(UpdateDisputeRequest $request, Dispute $dispute)
    {
        $admin = $request->user();
        $old = ['status' => $dispute->status, 'resolution' => $dispute->resolution];

        $dispute->update([
            'status' => $request->string('status')->value(),
            'resolution' => $request->input('resolution', $dispute->resolution),
            'resolved_by_admin_id' => $admin->id,
        ]);

        AuditLogger::logFromRequest(
            $request,
            'dispute.updated',
            'dispute',
            $dispute->id,
            $old,
            ['status' => $dispute->status, 'resolution' => $dispute->resolution],
        );

        return response()->json(['dispute' => $dispute->fresh()]);
    }
}
