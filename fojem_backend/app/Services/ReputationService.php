<?php

namespace App\Services;

use App\Models\Booking;
use App\Models\ReputationScore;
use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;

/**
 * Fiabilité d'un passager, montrée aux chauffeurs : part des réservations
 * honorées parmi celles qui comptent (terminées, absences, annulations de
 * dernière minute). Les paiements se faisant en espèces, c'est la seule
 * sanction, avec le blocage de la réservation en route après plusieurs
 * absences récentes.
 */
class ReputationService
{
    /** Une annulation plus proche que ça de la montée compte contre le passager. */
    public const LATE_CANCELLATION_HOURS = 2;

    /** Absences récentes au-delà desquelles un trajet déjà parti ne se réserve plus. */
    public const NO_SHOW_LIMIT = 3;
    public const NO_SHOW_WINDOW_DAYS = 90;

    public function refresh(User $user): ReputationScore
    {
        $bookings = Booking::where('passenger_id', $user->id)
            ->whereIn('status', [Booking::STATUS_COMPLETED, Booking::STATUS_NO_SHOW, Booking::STATUS_CANCELLED_PASSENGER])
            ->with('trip')
            ->get();

        $completed = $bookings->where('status', Booking::STATUS_COMPLETED)->count();
        $noShows = $bookings->where('status', Booking::STATUS_NO_SHOW)->count();
        $late = $bookings
            ->where('status', Booking::STATUS_CANCELLED_PASSENGER)
            ->filter(fn (Booking $b) => $this->isLateCancellation($b))
            ->count();
        $counted = $completed + $noShows + $late;

        $score = ReputationScore::withTrashed()->firstOrNew(['user_id' => $user->id]);
        $score->fill([
            'bookings_honored_pct' => $counted > 0 ? round(100 * $completed / $counted, 2) : null,
            'no_show_count' => $noShows,
            'last_computed_at' => now(),
        ]);
        $score->deleted_at = null;
        $score->save();

        return $score;
    }

    public function recentNoShows(User $user): int
    {
        return Booking::where('passenger_id', $user->id)
            ->where('status', Booking::STATUS_NO_SHOW)
            ->where('no_show_at', '>=', now()->subDays(self::NO_SHOW_WINDOW_DAYS))
            ->count();
    }

    /**
     * Fiabilité des passagers de ces réservations, pour le chauffeur : null
     * pour un passager sans historique (« Nouveau passager »).
     *
     * @param  Collection<int, Booking>  $bookings
     */
    public function attachTo(Collection $bookings): void
    {
        $scores = ReputationScore::whereIn('user_id', $bookings->pluck('passenger_id')->unique())->get()->keyBy('user_id');
        foreach ($bookings as $booking) {
            $score = $scores->get($booking->passenger_id);
            $booking->setAttribute('passenger_reliability', $score && $score->bookings_honored_pct !== null ? [
                'honored_pct' => (int) round((float) $score->bookings_honored_pct),
                'no_show_count' => (int) $score->no_show_count,
            ] : null);
        }
    }

    private function isLateCancellation(Booking $booking): bool
    {
        $boardingAt = $booking->boardingStop?->scheduled_at ?? $booking->trip?->scheduled_at;
        if ($booking->cancelled_at === null || $boardingAt === null) {
            return false;
        }

        return CarbonImmutable::instance($booking->cancelled_at)
            ->greaterThan(CarbonImmutable::instance($boardingAt)->subHours(self::LATE_CANCELLATION_HOURS));
    }
}
