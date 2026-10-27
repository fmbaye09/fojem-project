<?php

namespace App\Services;

use App\Models\Trip;
use App\Models\TripStop;
use Carbon\CarbonImmutable;

/**
 * Where a trip in progress stands: which meeting points the driver has
 * reached, and when they should reach the next ones.
 *
 * ETAs come from the driver's last GPS fix when it is recent; otherwise
 * they fall back to the published schedule and say so, so passengers never
 * see an invented position or time presented as live.
 */
class TripProgressService
{
    /** A stop counts as reached within this distance. */
    private const STOP_REACHED_METERS = 400;

    /** A GPS fix older than this is no longer "live". */
    private const FRESH_SECONDS = 180;

    private const ROAD_FACTOR = 1.25;
    private const AVERAGE_SPEED_KMH = 50;

    /** Marks the furthest stop the driver is now close to as reached. */
    public function recordPosition(Trip $trip, float $lat, float $lng): void
    {
        $passed = $trip->last_passed_stop_position ?? 0;
        $reached = $trip->stops
            ->filter(fn (TripStop $s) => $s->position > $passed
                && Trip::haversineMeters($lat, $lng, $s->lat, $s->lng) <= self::STOP_REACHED_METERS)
            ->max('position');

        if ($reached !== null) {
            $trip->update(['last_passed_stop_position' => $reached]);
        }
    }

    /**
     * @return array{
     *   state: string,
     *   location_fresh: bool,
     *   location_updated_at: ?string,
     *   last_passed_stop_position: ?int,
     *   next_stop_id: ?string,
     *   eta_source: ?string,
     *   delay_minutes: ?int,
     *   etas: list<array{stop_id: string, eta: string}>
     * }
     */
    public function live(Trip $trip, ?CarbonImmutable $now = null): array
    {
        $now ??= CarbonImmutable::now();
        $updatedAt = $trip->location_updated_at ? CarbonImmutable::instance($trip->location_updated_at) : null;
        $fresh = $trip->status === Trip::STATUS_IN_PROGRESS
            && $updatedAt !== null
            && $trip->current_lat !== null
            && $updatedAt->diffInSeconds($now, true) <= self::FRESH_SECONDS;

        $base = [
            'state' => $trip->status,
            'location_fresh' => $fresh,
            'location_updated_at' => $updatedAt?->toIso8601String(),
            'last_passed_stop_position' => $trip->last_passed_stop_position,
            'next_stop_id' => null,
            'eta_source' => null,
            'delay_minutes' => null,
            'etas' => [],
        ];

        if ($trip->status !== Trip::STATUS_IN_PROGRESS) {
            return $base;
        }

        $passed = $trip->last_passed_stop_position ?? 0;
        $remaining = $trip->stops->filter(fn (TripStop $s) => $s->position > $passed)->values();
        if ($remaining->isEmpty()) {
            return $base;
        }

        $next = $remaining->first();
        if ($fresh) {
            $km = self::ROAD_FACTOR * Trip::haversineMeters(
                (float) $trip->current_lat, (float) $trip->current_lng, $next->lat, $next->lng,
            ) / 1000;
            $nextEta = $updatedAt->addMinutes((int) ceil($km / self::AVERAGE_SPEED_KMH * 60));
            $source = 'live';
        } elseif ($next->scheduled_at) {
            $nextEta = CarbonImmutable::instance($next->scheduled_at);
            $source = 'schedule';
        } else {
            return $base + ['next_stop_id' => $next->id];
        }

        // Later stops keep the published gaps between them.
        $etas = [];
        foreach ($remaining as $stop) {
            $eta = ($stop->scheduled_at && $next->scheduled_at)
                ? $nextEta->addSeconds($next->scheduled_at->diffInSeconds($stop->scheduled_at, false))
                : ($stop->is($next) ? $nextEta : null);
            if ($eta) {
                $etas[] = ['stop_id' => $stop->id, 'eta' => $eta->toIso8601String()];
            }
        }

        return array_merge($base, [
            'next_stop_id' => $next->id,
            'eta_source' => $source,
            'delay_minutes' => $next->scheduled_at
                ? (int) round(CarbonImmutable::instance($next->scheduled_at)->diffInMinutes($nextEta, false))
                : null,
            'etas' => $etas,
        ]);
    }
}
