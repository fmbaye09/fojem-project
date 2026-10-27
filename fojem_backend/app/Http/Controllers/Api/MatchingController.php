<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\RideRequest;
use App\Services\MatchingService;
use Illuminate\Http\Request;

class MatchingController extends Controller
{
    public function __construct(private readonly MatchingService $matchingService) {}

    /**
     * Returns the best trip matches for a ride_request, scored and sorted
     * by compatibility_score desc. Each evaluated pair is persisted to
     * matching_scores.
     */
    public function bestMatches(Request $request, RideRequest $rideRequest)
    {
        if ($rideRequest->passenger_id !== $request->user()->id) {
            return response()->json(['message' => 'Non autorise.'], 403);
        }

        $limit = (int) $request->input('limit', 10);
        $radius = (int) $request->input('radius_m', 25000);

        $scores = $this->matchingService->bestMatchesForRideRequest($rideRequest, $radius, $limit);

        return response()->json([
            'matches' => $scores,
        ]);
    }
}
