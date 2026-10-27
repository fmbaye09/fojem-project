<?php

namespace App\Services;

use App\Models\MatchingScore;
use App\Models\RideRequest;
use App\Models\Trip;
use Illuminate\Support\Facades\DB;

/**
 * FOJEM Match: scores how well a ride_request fits a driver's trip.
 *
 * compatibility_score (0-100) is a weighted blend of four signals:
 *
 *   1. Detour distance (40%)  - how many extra meters the driver would
 *      drive to pick up + drop off this passenger, relative to their
 *      own origin/destination. Decays exponentially: small detours barely
 *      hurt the score, large ones crush it.
 *        distance_score = 100 * exp(-detour_distance_m / 3000)
 *
 *   2. Detour duration (25%) - the time cost of that detour, estimated
 *      from distance at an assumed 40 km/h urban/interurban average
 *      (no live routing engine wired up yet - see note below).
 *        duration_score = 100 * exp(-detour_duration_s / 900)
 *
 *   3. Schedule gap (25%) - how far the ride_request's desired time is
 *      from the trip's scheduled_at (0 for "depart now" trips matched
 *      against a request made "now").
 *        time_score = 100 * exp(-abs(gap_seconds) / 1800)
 *
 *   4. Direction alignment (10%) - cosine similarity between the trip's
 *      bearing (origin -> destination) and the request's bearing, mapped
 *      to 0-100. A request going roughly the same way scores near 100;
 *      a request going the opposite way scores near 0.
 *
 *   compatibility_score = 40%*distance_score + 25%*duration_score
 *                        + 25%*time_score + 10%*direction_score
 *
 * NOTE on detour_distance_m / detour_duration_s: without an integrated
 * routing engine (OSRM/Google Directions/Mapbox), the real "extra driving
 * distance if I detour to pick up/drop off this passenger" cannot be
 * computed exactly. This implementation approximates it as the sum of
 * great-circle distances from the trip's origin to the request's origin,
 * plus the trip's destination to the request's destination - a
 * conservative proxy that is cheap to compute entirely in PostGIS and
 * good enough to rank candidates. Swapping in a real routing engine later
 * only requires replacing computeDetour(); the scoring formula and its
 * weights do not need to change.
 */
class MatchingService
{
    private const WEIGHT_DISTANCE = 0.40;
    private const WEIGHT_DURATION = 0.25;
    private const WEIGHT_TIME = 0.25;
    private const WEIGHT_DIRECTION = 0.10;

    private const DISTANCE_DECAY_M = 3000;
    private const DURATION_DECAY_S = 900;
    private const TIME_DECAY_S = 1800;

    private const ASSUMED_SPEED_MPS = 40 * 1000 / 3600; // 40 km/h

    public function score(RideRequest $rideRequest, Trip $trip): MatchingScore
    {
        [$detourDistanceM, $detourDurationS] = $this->computeDetour($rideRequest, $trip);

        $timeGapS = $this->computeTimeGapSeconds($rideRequest, $trip);
        $directionScore = $this->computeDirectionScore($rideRequest, $trip);

        $distanceScore = 100 * exp(-$detourDistanceM / self::DISTANCE_DECAY_M);
        $durationScore = 100 * exp(-$detourDurationS / self::DURATION_DECAY_S);
        $timeScore = 100 * exp(-abs($timeGapS) / self::TIME_DECAY_S);

        $compatibility = self::WEIGHT_DISTANCE * $distanceScore
            + self::WEIGHT_DURATION * $durationScore
            + self::WEIGHT_TIME * $timeScore
            + self::WEIGHT_DIRECTION * $directionScore;

        return MatchingScore::updateOrCreate(
            [
                'ride_request_id' => $rideRequest->id,
                'trip_id' => $trip->id,
            ],
            [
                'compatibility_score' => round($compatibility, 2),
                'detour_distance_m' => (int) round($detourDistanceM),
                'detour_duration_s' => (int) round($detourDurationS),
                'computed_at' => now(),
            ]
        );
    }

    /**
     * @return array{0: float, 1: float} [detour_distance_m, detour_duration_s]
     */
    private function computeDetour(RideRequest $rideRequest, Trip $trip): array
    {
        $row = DB::selectOne(
            'SELECT
                ST_Distance(t.origin_geom, r.origin_geom) as origin_gap,
                ST_Distance(t.destination_geom, r.destination_geom) as destination_gap
             FROM trips t, ride_requests r
             WHERE t.id = ? AND r.id = ?',
            [$trip->id, $rideRequest->id]
        );

        $detourDistanceM = (float) $row->origin_gap + (float) $row->destination_gap;

        // If the trip has intermediate waypoints, see if picking up or dropping off at a waypoint reduces the detour
        $waypoints = is_array($trip->waypoints) ? $trip->waypoints : [];
        if (! empty($waypoints)) {
            $reqCoords = DB::selectOne(
                'SELECT
                    ST_Y(r.origin_geom::geometry) as o_lat,
                    ST_X(r.origin_geom::geometry) as o_lng,
                    ST_Y(r.destination_geom::geometry) as d_lat,
                    ST_X(r.destination_geom::geometry) as d_lng,
                    ST_Y(t.origin_geom::geometry) as to_lat,
                    ST_X(t.origin_geom::geometry) as to_lng,
                    ST_Y(t.destination_geom::geometry) as td_lat,
                    ST_X(t.destination_geom::geometry) as td_lng
                 FROM trips t, ride_requests r
                 WHERE t.id = ? AND r.id = ?',
                [$trip->id, $rideRequest->id]
            );
            if ($reqCoords) {
                $path = [
                    ['lat' => (float) $reqCoords->to_lat, 'lng' => (float) $reqCoords->to_lng],
                ];
                foreach ($waypoints as $wp) {
                    if (isset($wp['lat'], $wp['lng'])) {
                        $path[] = ['lat' => (float) $wp['lat'], 'lng' => (float) $wp['lng']];
                    }
                }
                $path[] = ['lat' => (float) $reqCoords->td_lat, 'lng' => (float) $reqCoords->td_lng];

                for ($i = 0; $i < count($path) - 1; $i++) {
                    $oGap = Trip::haversineMeters((float) $reqCoords->o_lat, (float) $reqCoords->o_lng, $path[$i]['lat'], $path[$i]['lng']);
                    for ($j = $i + 1; $j < count($path); $j++) {
                        $dGap = Trip::haversineMeters((float) $reqCoords->d_lat, (float) $reqCoords->d_lng, $path[$j]['lat'], $path[$j]['lng']);
                        if ($oGap + $dGap < $detourDistanceM) {
                            $detourDistanceM = $oGap + $dGap;
                        }
                    }
                }
            }
        }

        $detourDurationS = $detourDistanceM / self::ASSUMED_SPEED_MPS;

        return [$detourDistanceM, $detourDurationS];
    }

    private function computeTimeGapSeconds(RideRequest $rideRequest, Trip $trip): int
    {
        if ($trip->departure_type === 'now') {
            return abs(now()->diffInSeconds($rideRequest->requested_at, false));
        }

        if (! $trip->scheduled_at) {
            return 0;
        }

        return abs($trip->scheduled_at->diffInSeconds($rideRequest->requested_at, false));
    }

    /**
     * Cosine similarity between the trip's origin->destination bearing and
     * the request's origin->destination bearing, rescaled from [-1, 1] to
     * a [0, 100] score (1 = same direction -> 100, -1 = opposite -> 0).
     */
    private function computeDirectionScore(RideRequest $rideRequest, Trip $trip): float
    {
        $row = DB::selectOne(
            "SELECT
                ST_X(t.destination_geom::geometry) - ST_X(t.origin_geom::geometry) as tx,
                ST_Y(t.destination_geom::geometry) - ST_Y(t.origin_geom::geometry) as ty,
                ST_X(r.destination_geom::geometry) - ST_X(r.origin_geom::geometry) as rx,
                ST_Y(r.destination_geom::geometry) - ST_Y(r.origin_geom::geometry) as ry
             FROM trips t, ride_requests r
             WHERE t.id = ? AND r.id = ?",
            [$trip->id, $rideRequest->id]
        );

        $tx = (float) $row->tx;
        $ty = (float) $row->ty;
        $rx = (float) $row->rx;
        $ry = (float) $row->ry;

        $tripMagnitude = sqrt($tx ** 2 + $ty ** 2);
        $requestMagnitude = sqrt($rx ** 2 + $ry ** 2);

        if ($tripMagnitude == 0.0 || $requestMagnitude == 0.0) {
            return 50.0; // no directional information -> neutral score
        }

        $cosine = ($tx * $rx + $ty * $ry) / ($tripMagnitude * $requestMagnitude);
        $cosine = max(-1.0, min(1.0, $cosine));

        return ($cosine + 1) * 50;
    }

    /**
     * Scores $rideRequest against every open, driver-approved trip found
     * within $radiusMeters of its origin (or passing through a waypoint),
     * persists each score, and returns the top $limit trips ranked by compatibility_score desc.
     */
    public function bestMatchesForRideRequest(RideRequest $rideRequest, int $radiusMeters = 25000, int $limit = 10)
    {
        $candidateTrips = Trip::query()
            ->withLatLng()
            ->where('status', Trip::STATUS_OPEN)
            ->where('seats_available', '>', 0)
            ->whereHas('driverProfile', fn ($q) => $q->where('verification_status', 'approved'))
            ->where(function ($q) use ($rideRequest, $radiusMeters) {
                $q->whereRaw(
                    'ST_DWithin(origin_geom, (SELECT origin_geom FROM ride_requests WHERE id = ?)::geography, ?)',
                    [$rideRequest->id, $radiusMeters]
                )->orWhereNotNull('waypoints');
            })
            ->with('vehicle', 'driverProfile.user')
            ->get();

        $scores = $candidateTrips
            ->map(function (Trip $trip) use ($rideRequest) {
                $score = $this->score($rideRequest, $trip);
                $score->setRelation('trip', $trip);
                return $score;
            })
            ->filter(fn (MatchingScore $s) => $s->compatibility_score >= 35.0);

        return $scores->sortByDesc('compatibility_score')->values()->take($limit);
    }

    /**
     * Scores a newly published or active $trip against open ride requests,
     * returning matches sorted by compatibility_score desc.
     */
    public function bestRideRequestsForTrip(Trip $trip, int $radiusMeters = 25000, float $minScore = 40.0)
    {
        $candidateRequests = RideRequest::query()
            ->withLatLng()
            ->where('status', RideRequest::STATUS_SEARCHING)
            ->when($trip->women_only, fn ($q) => $q->where('women_only', true))
            ->with('passenger')
            ->get();

        return $candidateRequests
            ->map(function (RideRequest $req) use ($trip) {
                $score = $this->score($req, $trip);
                $req->setAttribute('compatibility_score', (float) $score->compatibility_score);
                $req->setAttribute('detour_distance_m', (int) $score->detour_distance_m);
                $req->setAttribute('detour_duration_s', (int) $score->detour_duration_s);
                return $req;
            })
            ->filter(fn (RideRequest $req) => $req->getAttribute('compatibility_score') >= $minScore)
            ->sortByDesc(fn (RideRequest $req) => $req->getAttribute('compatibility_score'))
            ->values();
    }
}
