<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\Disputes\StoreDisputeRequest;
use App\Models\Dispute;

class DisputeController extends Controller
{
    public function store(StoreDisputeRequest $request)
    {
        $dispute = Dispute::create([
            'booking_id' => $request->input('booking_id'),
            'reported_by_id' => $request->user()->id,
            'reported_against_id' => $request->input('reported_against_id'),
            'reason' => $request->input('reason'),
            'description' => $request->input('description'),
            'status' => Dispute::STATUS_OPEN,
        ]);

        return response()->json(['dispute' => $dispute], 201);
    }

    public function mine(\Illuminate\Http\Request $request)
    {
        $disputes = Dispute::where('reported_by_id', $request->user()->id)
            ->orderByDesc('created_at')
            ->paginate(20);

        return response()->json($disputes);
    }
}
