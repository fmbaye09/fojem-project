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
    public const STOP_REACHED_METERS = 400;

    /** Before this, being near a stop (e.g. the driver lives there) is not an arrival. */
    private const ARRIVAL_WINDOW_HOURS = 2;

    /** A trip already on the road is booked at least this long before it reaches the stop. */
    public const EN_ROUTE_LEAD_MINUTES = 15;

    /** When the driver should reach this stop: live ETA during the trip, else the published time. */
    public function etaFor(Trip $trip, TripStop $stop, ?CarbonImmutable $now = null): ?CarbonImmutable
    {
        $eta = collect($this->live($trip, $now)['etas'])->firstWhere('stop_id', $stop->id);
        if ($eta !== null) {
            return CarbonImmutable::parse($eta['eta']);
        }

        return $stop->scheduled_at ? CarbonImmutable::instance($stop->scheduled_at) : null;
    }

    /**
     * Un passager peut monter en route à cet arrêt : le chauffeur ne l'a pas
     * encore atteint et y passe dans au moins 15 min, le temps de le rejoindre.
     */
    public function canBoardEnRoute(Trip $trip, TripStop $stop, ?CarbonImmutable $now = null): bool
    {
        $now ??= CarbonImmutable::now();
        if ($stop->position <= ($trip->last_passed_stop_position ?? 0)) {
            return false;
        }
        $eta = $this->etaFor($trip, $stop, $now);

        return $eta !== null && $eta->greaterThanOrEqualTo($now->addMinutes(self::EN_ROUTE_LEAD_MINUTES));
    }

    /** A GPS fix older than this is no longer "live". */
    private const FRESH_SECONDS = 180;

    private const ROAD_FACTOR = 1.25;
    private const AVERAGE_SPEED_KMH = 50;

    /**
     * Records the driver's arrival at the stops they are near (trip started
     * or not, so the departure point counts too), then, during the trip,
     * marks the furthest one as passed.
     */
    public function recordPosition(Trip $trip, float $lat, float $lng): void
    {
        $now = CarbonImmutable::now();
        foreach ($trip->stops as $stop) {
            $scheduled = $stop->scheduled_at ?? $trip->scheduled_at;
            if ($stop->reached_at === null
                && ($scheduled === null || $now->greaterThanOrEqualTo(CarbonImmutable::instance($scheduled)->subHours(self::ARRIVAL_WINDOW_HOURS)))
                && Trip::haversineMeters($lat, $lng, $stop->lat, $stop->lng) <= self::STOP_REACHED_METERS) {
                $stop->update(['reached_at' => $now]);
                // Les passagers qui montent ici savent jusqu'à quand il attend.
                app(TripReminderService::class)->driverArrived($trip, $stop, $now);
            }
        }

        if ($trip->status !== Trip::STATUS_IN_PROGRESS) {
            return;
        }

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
