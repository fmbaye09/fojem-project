<?php

namespace App\Services;

use App\Models\Booking;
use App\Models\Trip;
use App\Models\TripStop;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Collection as EloquentCollection;
use Illuminate\Support\Facades\Log;

/**
 * Prévient chacun à temps :
 * - 30 min avant, rappel au chauffeur (départ) et à chaque passager (son
 *   point de montée, à l'heure prévue ou estimée en route) ;
 * - à l'arrivée du chauffeur à un point de rendez-vous, les passagers qui y
 *   montent savent jusqu'à quand il les attend avant de pouvoir les
 *   déclarer absents.
 */
class TripReminderService
{
    /** Le rappel part quand le rendez-vous est à moins de 30 min. */
    public const LEAD_MINUTES = 30;

    public function __construct(
        private readonly NotificationService $notifications,
        private readonly TripProgressService $progress,
    ) {}

    /** @return array{drivers: int, passengers: int} */
    public function sendDue(?CarbonImmutable $now = null): array
    {
        $now ??= CarbonImmutable::now();

        return [
            'drivers' => $this->remindDrivers($now),
            'passengers' => $this->remindPassengers($now),
        ];
    }

    private function remindDrivers(CarbonImmutable $now): int
    {
        $sent = 0;
        $trips = Trip::whereIn('status', [Trip::STATUS_OPEN, Trip::STATUS_FULL])
            ->whereNull('reminder_sent_at')
            ->whereBetween('scheduled_at', [$now, $now->addMinutes(self::LEAD_MINUTES)])
            // Publié il y a moins de 30 min : le chauffeur sait déjà quand il part.
            ->where('created_at', '<=', $now->subMinutes(self::LEAD_MINUTES))
            ->with('driverProfile.user')
            ->get();

        foreach ($trips as $trip) {
            $trip->update(['reminder_sent_at' => $now]);
            $driver = $trip->driverProfile?->user;
            if (! $driver) {
                continue;
            }
            $at = CarbonImmutable::instance($trip->scheduled_at);
            $passengers = $trip->bookings()->where('status', Booking::STATUS_CONFIRMED)->sum('seat_count');
            $who = $passengers > 0
                ? "{$passengers} passager".($passengers > 1 ? 's' : '').' confirmé'.($passengers > 1 ? 's' : '')
                : 'aucun passager confirmé pour l’instant';

            $this->send(fn () => $this->notifications->system(
                $driver,
                '⏰ Départ dans '.$this->minutesUntil($now, $at).' min',
                "{$trip->origin_name} → {$trip->destination_name} à {$at->format('H:i')}, {$who}. "
                .'Ouvrez le trajet dans l’app en arrivant au point de départ : votre position confirme votre présence.',
                ['trip_id' => $trip->id],
            ));
            $sent++;
        }

        return $sent;
    }

    private function remindPassengers(CarbonImmutable $now): int
    {
        $sent = 0;
        $bookings = Booking::where('status', Booking::STATUS_CONFIRMED)
            ->whereNull('reminder_sent_at')
            ->whereNull('started_at')
            // Le départ précède toujours la montée : un trajet qui part dans
            // plus de 30 min ne peut pas avoir de passager à prévenir.
            ->whereHas('trip', fn ($q) => $q
                ->whereIn('status', [Trip::STATUS_OPEN, Trip::STATUS_FULL, Trip::STATUS_IN_PROGRESS])
                ->whereBetween('scheduled_at', [$now->subDay(), $now->addMinutes(self::LEAD_MINUTES)]))
            ->with(['trip', 'boardingStop', 'passenger'])
            ->get();

        foreach ($bookings as $booking) {
            $trip = $booking->trip;
            $stop = $booking->boardingStop ?? $trip->stops->first();
            if (! $stop || ($trip->status === Trip::STATUS_IN_PROGRESS
                && $stop->position <= ($trip->last_passed_stop_position ?? 0))) {
                continue;
            }

            $at = $trip->status === Trip::STATUS_IN_PROGRESS
                ? $this->progress->etaFor($trip, $stop, $now)
                : CarbonImmutable::instance($stop->scheduled_at ?? $trip->scheduled_at);
            if ($at === null || $at->lessThan($now) || $at->greaterThan($now->addMinutes(self::LEAD_MINUTES))) {
                continue;
            }
            // Réservé (ou accepté) dans les 30 dernières minutes : la
            // confirmation vient d'arriver, pas besoin d'un rappel en plus.
            $bookedAt = CarbonImmutable::instance($booking->confirmed_at ?? $booking->created_at);
            if ($bookedAt->greaterThan($at->subMinutes(self::LEAD_MINUTES))) {
                continue;
            }

            $booking->update(['reminder_sent_at' => $now]);
            if (! $booking->passenger) {
                continue;
            }

            $waitUntil = $stop->waitUntil($trip->scheduled_at);
            $body = $waitUntil !== null
                ? "Votre chauffeur est déjà au point de rendez-vous ({$stop->name}). Rejoignez-le avant {$waitUntil->format('H:i')}."
                : ($trip->status === Trip::STATUS_IN_PROGRESS
                    ? "Le chauffeur passe à {$stop->name} vers {$at->format('H:i')}. Soyez-y en avance : il n’attend que ".TripStop::WAIT_MINUTES.' min.'
                    : "Soyez à {$stop->name} à {$at->format('H:i')}. Le chauffeur attend ".TripStop::WAIT_MINUTES.' min au plus après l’heure prévue.');

            $this->send(fn () => $this->notifications->system(
                $booking->passenger,
                '⏰ Rendez-vous dans '.$this->minutesUntil($now, $at).' min',
                $body,
                ['booking_id' => $booking->id, 'trip_id' => $trip->id],
            ));
            $sent++;
        }

        return $sent;
    }

    /**
     * Le chauffeur vient d'arriver à cet arrêt : ses passagers savent
     * jusqu'à quand il les attend. Une arrivée très en avance (plus de
     * 30 min) est signalée par le rappel, pas ici.
     */
    public function driverArrived(Trip $trip, TripStop $stop, ?CarbonImmutable $now = null): void
    {
        $now ??= CarbonImmutable::now();
        $scheduled = $stop->scheduled_at ?? $trip->scheduled_at;
        if ($scheduled !== null && $now->lessThan(CarbonImmutable::instance($scheduled)->subMinutes(self::LEAD_MINUTES))) {
            return;
        }
        $waitUntil = $stop->waitUntil($trip->scheduled_at);
        if ($waitUntil === null) {
            return;
        }

        foreach ($this->notYetOnBoard($trip, $stop) as $booking) {
            if (! $booking->passenger) {
                continue;
            }
            $this->send(fn () => $this->notifications->system(
                $booking->passenger,
                '📍 Votre chauffeur est arrivé',
                "Il vous attend à {$stop->name} jusqu’à {$waitUntil->format('H:i')}. "
                .'Passé ce délai, il pourra vous déclarer absent et repartir.',
                ['booking_id' => $booking->id, 'trip_id' => $trip->id],
            ));
        }
    }

    /**
     * Le chauffeur vient de quitter cet arrêt, trajet en cours. Les passagers
     * qui devaient y monter et ne sont pas à bord le savent ; s'il part avant
     * la fin de l'attente, lui est averti tout de suite.
     */
    public function driverLeft(Trip $trip, TripStop $stop, ?CarbonImmutable $now = null): void
    {
        $now ??= CarbonImmutable::now();
        $missing = $this->notYetOnBoard($trip, $stop);
        $waitUntil = $stop->waitUntil($trip->scheduled_at);
        if ($missing->isEmpty() || $waitUntil === null) {
            return;
        }
        $early = $now->lessThan($waitUntil);
        $until = $waitUntil->format('H:i');

        foreach ($missing as $booking) {
            if (! $booking->passenger) {
                continue;
            }
            $this->send(fn () => $this->notifications->system(
                $booking->passenger,
                $early ? '🚗 Le chauffeur est reparti sans vous' : '🚗 Le chauffeur est reparti',
                $early
                    ? "Il a quitté {$stop->name} à {$now->format('H:i')}, avant la fin de l’attente ({$until}). "
                        .'Écrivez-lui dans la discussion. S’il ne revient pas, votre réservation sera « manquée », sans pénalité pour vous.'
                    : "Il vous a attendu à {$stop->name} jusqu’à {$until}, puis a repris la route.",
                ['booking_id' => $booking->id, 'trip_id' => $trip->id],
            ));
        }

        $driver = $trip->driverProfile?->user;
        if ($early && $driver) {
            $names = $missing->map(fn (Booking $b) => $b->passenger?->full_name ?? 'un passager')->join(', ', ' et ');
            $this->send(fn () => $this->notifications->system(
                $driver,
                "⚠️ Vous avez quitté {$stop->name} trop tôt",
                "Pas encore à bord : {$names}. L’attente courait jusqu’à {$until} : faites demi-tour si vous le pouvez.",
                ['trip_id' => $trip->id],
            ));
        }
    }

    /** Réservations confirmées qui montent à cet arrêt (sans arrêt connu : au départ), pas encore à bord. */
    private function notYetOnBoard(Trip $trip, TripStop $stop): EloquentCollection
    {
        return $trip->bookings()
            ->where('status', Booking::STATUS_CONFIRMED)
            ->whereNull('started_at')
            ->where(fn ($q) => $stop->position === 0
                ? $q->where('boarding_stop_id', $stop->id)->orWhereNull('boarding_stop_id')
                : $q->where('boarding_stop_id', $stop->id))
            ->with('passenger')
            ->get();
    }

    private function minutesUntil(CarbonImmutable $now, CarbonImmutable $at): int
    {
        return max(1, (int) ceil($now->diffInSeconds($at, true) / 60));
    }

    /** Un échec d'envoi ne doit pas bloquer les autres rappels ni la position. */
    private function send(callable $notify): void
    {
        try {
            $notify();
        } catch (\Throwable $e) {
            Log::warning("Trip reminder failed: {$e->getMessage()}");
        }
    }
}
