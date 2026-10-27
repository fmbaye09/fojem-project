<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\RideRequests\StoreRideRequestRequest;
use App\Models\RideRequest;
use App\Models\Trip;
use App\Services\MatchingService;
use App\Services\NotificationService;
use Illuminate\Http\Request;

class RideRequestController extends Controller
{
    /** Passenger creates a "find me someone" request. */
    public function store(StoreRideRequestRequest $request, MatchingService $matching, NotificationService $notifications)
    {
        $rideRequest = new RideRequest([
            'passenger_id' => $request->user()->id,
            'requested_at' => $request->input('requested_at') ? \Carbon\Carbon::parse($request->input('requested_at')) : now(),
            'status' => RideRequest::STATUS_SEARCHING,
            'women_only' => $request->boolean('women_only'),
            'origin_name' => $request->input('origin_name'),
            'destination_name' => $request->input('destination_name'),
        ]);

        $rideRequest->setOriginPoint((float) $request->input('origin_lat'), (float) $request->input('origin_lng'));
        $rideRequest->setDestinationPoint((float) $request->input('destination_lat'), (float) $request->input('destination_lng'));
        $rideRequest->save();

        $freshRequest = RideRequest::withLatLng()->findOrFail($rideRequest->id);

        // Compute top matches right away and notify drivers of compatible open trips (score >= 65%)
        try {
            $matches = $matching->bestMatchesForRideRequest($freshRequest, 25000, 10);
            $passengerName = $request->user()->full_name ?? $request->user()->name ?? 'Un passager';
            $reqLabel = ($freshRequest->origin_name ?? 'Départ') . ' → ' . ($freshRequest->destination_name ?? 'Arrivée');
            foreach ($matches as $score) {
                if ((float) $score->compatibility_score >= 65.0) {
                    $driverUser = $score->trip?->driverProfile?->user;
                    if ($driverUser && $driverUser->id !== $request->user()->id) {
                        $pct = (int) round((float) $score->compatibility_score);
                        $notifications->system(
                            $driverUser,
                            "Demande passager compatible ({$pct}%)",
                            "{$passengerName} cherche un trajet {$reqLabel} sur votre route.",
                            [
                                'type' => 'ride_request_match',
                                'trip_id' => $score->trip_id,
                                'ride_request_id' => $freshRequest->id,
                                'compatibility_score' => $pct,
                            ]
                        );
                    }
                }
            }
        } catch (\Throwable $e) {
            // Do not block request creation on notification error
        }

        return response()->json(['ride_request' => $freshRequest], 201);
    }

    public function mine(Request $request)
    {
        $rideRequests = RideRequest::withLatLng()
            ->where('passenger_id', $request->user()->id)
            ->orderByDesc('created_at')
            ->paginate(20);

        return response()->json($rideRequests);
    }

    public function cancel(Request $request, RideRequest $rideRequest)
    {
        if ($rideRequest->passenger_id !== $request->user()->id) {
            return response()->json(['message' => 'Non autorise.'], 403);
        }

        $rideRequest->update(['status' => RideRequest::STATUS_CANCELLED]);

        return response()->json(['ride_request' => $rideRequest->fresh()]);
    }

    /**
     * Driver side: open ride requests compatible with a given trip,
     * scored by MatchingService (distance, detour, schedule & direction alignment).
     */
    public function nearTrip(Request $request, Trip $trip, MatchingService $matching)
    {
        $radius = (int) $request->input('radius_m', 25000);
        $minScore = (float) $request->input('min_score', 40.0);

        $rideRequests = $matching->bestRideRequestsForTrip($trip, $radius, $minScore);

        return response()->json(['ride_requests' => $rideRequests]);
    }
}
