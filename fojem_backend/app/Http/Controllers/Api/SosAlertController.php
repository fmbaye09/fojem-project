<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\Sos\TriggerSosRequest;
use App\Models\SosAlert;

class SosAlertController extends Controller
{
    public function store(TriggerSosRequest $request)
    {
        $alert = new SosAlert([
            'user_id' => $request->user()->id,
            'booking_id' => $request->input('booking_id'),
            'triggered_at' => now(),
            'status' => SosAlert::STATUS_OPEN,
        ]);

        $alert->setLocationPoint((float) $request->input('lat'), (float) $request->input('lng'));
        $alert->save();

        // NOTE: in production this should also fan out a `sos` notification
        // to on-call admins / emergency contacts; left out of this pass -
        // see app/Models/Notification and README "reste a faire".

        return response()->json(['sos_alert' => $alert->fresh()], 201);
    }
}
