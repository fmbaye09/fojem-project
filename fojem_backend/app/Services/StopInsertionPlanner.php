<?php

namespace App\Services;

use App\Models\Booking;
use App\Models\Trip;
use App\Models\TripStop;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;
use Illuminate\Validation\ValidationException;

/**
 * Arrêt proposé par un passager quand aucun point de rendez-vous du trajet ne
 * lui convient : entre quels arrêts il se place, le détour qu'il coûte au
 * chauffeur, son heure et son prix. Le chauffeur décide en voyant le détour ;
 * s'il accepte, l'arrêt est ajouté au trajet et les suivants sont décalés.
 */
class StopInsertionPlanner
{
    public const ROLE_BOARDING = 'boarding';
    public const ROLE_ALIGHTING = 'alighting';

    /** Au-delà, le point est trop loin de la route pour être proposé. */
    public const MAX_DETOUR_MINUTES = 20;

    /** Plus près d'un arrêt existant, le passager choisit simplement cet arrêt. */
    public const SAME_STOP_METERS = 1000;

    /** Mêmes estimations que TripStopPlanner quand le routage ne répond pas. */
    private const ROAD_FACTOR = 1.25;
    private const AVERAGE_SPEED_KMH = 60;
    private const PRICE_ROUNDING = 50;

    public function __construct(private readonly RoutingService $routing)
    {
    }

    /**
     * Ce que coûterait l'arrêt proposé, sans rien changer au trajet.
     *
     * @return array{role: string, name: string, address: ?string, lat: float, lng: float, after_stop_id: string, before_stop_id: string, detour_minutes: int, scheduled_at: ?string, price_from_origin: string}
     *
     * @throws ValidationException point refusé, avec la raison à afficher
     */
    public function preview(Trip $trip, string $role, float $lat, float $lng, ?string $name = null, ?string $address = null): array
    {
        if ($trip->status !== Trip::STATUS_OPEN) {
            throw ValidationException::withMessages([
                'proposed_stop' => 'On ne peut proposer un arrêt qu’avant le départ, sur un trajet qui a encore des places.',
            ]);
        }

        $stops = $trip->ensureStops()->stops->values();
        $near = $this->nearestStop($stops, $lat, $lng);
        if ($near !== null && $near['meters'] <= self::SAME_STOP_METERS) {
            throw ValidationException::withMessages([
                'proposed_stop' => "Le chauffeur passe déjà à « {$near['stop']->name} », à "
                    .$this->distanceLabel($near['meters']).' : choisissez cet arrêt.',
            ]);
        }

        $plan = $this->plan($stops, $lat, $lng);
        if ($plan['detour_minutes'] > self::MAX_DETOUR_MINUTES) {
            throw ValidationException::withMessages([
                'proposed_stop' => "Ce point est trop loin de la route du chauffeur : environ {$plan['detour_minutes']} min de détour ("
                    .self::MAX_DETOUR_MINUTES.' min au plus). Choisissez un point plus proche de son trajet.',
            ]);
        }

        $name = trim((string) $name);
        $address = trim((string) $address);

        return [
            'role' => $role,
            'name' => mb_substr($name !== '' ? $name : Trip::closestCity($lat, $lng), 0, 120),
            'address' => $address !== '' ? mb_substr($address, 0, 255) : null,
            'lat' => $lat,
            'lng' => $lng,
            'after_stop_id' => $plan['prev']->id,
            'before_stop_id' => $plan['next']->id,
            'detour_minutes' => $plan['detour_minutes'],
            'scheduled_at' => $plan['scheduled_at']?->toIso8601String(),
            'price_from_origin' => number_format($plan['price'], 2, '.', ''),
        ];
    }

    /**
     * Ajoute l'arrêt proposé au trajet, placé d'après ses arrêts actuels (un
     * autre arrêt a pu être ajouté depuis la demande). Un arrêt déjà présent
     * tout près est réutilisé. Les arrêts suivants sont retardés du détour.
     *
     * @return array{stop: TripStop, shift_minutes: int}
     */
    public function insert(Trip $trip, array $proposal): array
    {
        $lat = (float) $proposal['lat'];
        $lng = (float) $proposal['lng'];
        $stops = $trip->stops()->get()->values();

        $near = $this->nearestStop($stops, $lat, $lng);
        if ($near !== null && $near['meters'] <= self::SAME_STOP_METERS) {
            return ['stop' => $near['stop'], 'shift_minutes' => 0];
        }

        $plan = $this->plan($stops, $lat, $lng);
        $prev = $plan['prev'];
        $next = $plan['next'];
        $position = $prev->position + 1;
        $price = min(
            max((float) ($proposal['price_from_origin'] ?? $plan['price']), (float) $prev->price_from_origin),
            (float) $next->price_from_origin,
        );

        // Les arrêts suivants passent plus tard du détour.
        foreach ($stops->where('position', '>=', $position) as $later) {
            if ($later->scheduled_at !== null) {
                TripStop::whereKey($later->id)->update([
                    'scheduled_at' => CarbonImmutable::instance($later->scheduled_at)->addMinutes($plan['detour_minutes']),
                ]);
            }
        }
        $this->shiftPositions($trip, $position, 1);

        $stop = TripStop::create([
            'trip_id' => $trip->id,
            'position' => $position,
            'name' => $proposal['name'] ?? Trip::closestCity($lat, $lng),
            'address' => $proposal['address'] ?? null,
            'lat' => $lat,
            'lng' => $lng,
            'scheduled_at' => $plan['scheduled_at'],
            'price_from_origin' => $price,
        ]);
        $trip->unsetRelation('stops');

        return ['stop' => $stop, 'shift_minutes' => $plan['detour_minutes']];
    }

    /**
     * Retire un arrêt ajouté pour un passager qui n'y monte ou n'y descend
     * plus, si personne d'autre ne l'utilise et que le trajet n'est pas parti.
     * Les heures suivantes restent celles annoncées : arriver en avance ne
     * fait manquer le chauffeur à personne, il attend jusqu'à l'heure prévue.
     */
    public function removeIfUnused(Trip $trip, ?string $stopId): bool
    {
        if ($stopId === null || ! in_array($trip->status, [Trip::STATUS_OPEN, Trip::STATUS_FULL], true)) {
            return false;
        }
        $stop = TripStop::where('trip_id', $trip->id)->find($stopId);
        $lastPosition = (int) TripStop::where('trip_id', $trip->id)->max('position');
        if (! $stop || $stop->position === 0 || $stop->position >= $lastPosition) {
            return false;
        }

        $used = Booking::where('trip_id', $trip->id)
            ->whereIn('status', [Booking::STATUS_PENDING_DRIVER, Booking::STATUS_CONFIRMED])
            ->where(fn ($q) => $q->where('boarding_stop_id', $stop->id)->orWhere('alighting_stop_id', $stop->id))
            ->exists();
        if ($used) {
            return false;
        }

        $position = $stop->position;
        $stop->delete();
        $this->shiftPositions($trip, $position + 1, -1);
        $trip->unsetRelation('stops');

        return true;
    }

    /**
     * Où placer le point : entre les deux arrêts consécutifs qui allongent le
     * moins la route. Détour et heure par la route (OSRM), sinon estimés.
     *
     * @param  Collection<int, TripStop>  $stops
     * @return array{prev: TripStop, next: TripStop, detour_minutes: int, scheduled_at: ?CarbonImmutable, price: float}
     */
    private function plan(Collection $stops, float $lat, float $lng): array
    {
        $bestIndex = 0;
        $bestExtra = INF;
        for ($i = 0; $i < $stops->count() - 1; $i++) {
            $a = $stops[$i];
            $b = $stops[$i + 1];
            $extra = Trip::haversineMeters($a->lat, $a->lng, $lat, $lng)
                + Trip::haversineMeters($lat, $lng, $b->lat, $b->lng)
                - Trip::haversineMeters($a->lat, $a->lng, $b->lat, $b->lng);
            if ($extra < $bestExtra) {
                $bestExtra = $extra;
                $bestIndex = $i;
            }
        }
        $prev = $stops[$bestIndex];
        $next = $stops[$bestIndex + 1];

        $via = $this->routing->legDurations([[$prev->lat, $prev->lng], [$lat, $lng], [$next->lat, $next->lng]]);
        $direct = $via !== null ? $this->routing->legDurations([[$prev->lat, $prev->lng], [$next->lat, $next->lng]]) : null;
        if ($via !== null && $direct !== null) {
            $toStop = $via[0];
            $detour = $via[0] + $via[1] - $direct[0];
        } else {
            $toStop = $this->estimateSeconds($prev->lat, $prev->lng, $lat, $lng);
            $detour = $toStop
                + $this->estimateSeconds($lat, $lng, $next->lat, $next->lng)
                - $this->estimateSeconds($prev->lat, $prev->lng, $next->lat, $next->lng);
        }

        // Prix au prorata de la distance entre les deux arrêts voisins.
        $toPrev = Trip::haversineMeters($prev->lat, $prev->lng, $lat, $lng);
        $toNext = Trip::haversineMeters($lat, $lng, $next->lat, $next->lng);
        $fraction = $toPrev + $toNext > 0 ? $toPrev / ($toPrev + $toNext) : 0.5;
        $prevPrice = (float) $prev->price_from_origin;
        $nextPrice = (float) $next->price_from_origin;
        $price = round(($prevPrice + ($nextPrice - $prevPrice) * $fraction) / self::PRICE_ROUNDING) * self::PRICE_ROUNDING;

        return [
            'prev' => $prev,
            'next' => $next,
            'detour_minutes' => (int) ceil(max(0.0, $detour) / 60),
            'scheduled_at' => $prev->scheduled_at
                ? CarbonImmutable::instance($prev->scheduled_at)->addMinutes((int) round($toStop / 60))
                : null,
            'price' => min(max($price, $prevPrice), $nextPrice),
        ];
    }

    /** @return array{stop: TripStop, meters: float}|null */
    private function nearestStop(Collection $stops, float $lat, float $lng): ?array
    {
        $nearest = null;
        foreach ($stops as $stop) {
            $meters = Trip::haversineMeters($stop->lat, $stop->lng, $lat, $lng);
            if ($nearest === null || $meters < $nearest['meters']) {
                $nearest = ['stop' => $stop, 'meters' => $meters];
            }
        }

        return $nearest;
    }

    /** Décale les positions à partir de $from ; en deux temps, à cause de l'unicité (trajet, position). */
    private function shiftPositions(Trip $trip, int $from, int $by): void
    {
        $offset = 10000;
        TripStop::where('trip_id', $trip->id)->where('position', '>=', $from)->increment('position', $offset);
        TripStop::where('trip_id', $trip->id)->where('position', '>=', $offset + $from)->decrement('position', $offset - $by);
    }

    private function estimateSeconds(float $fromLat, float $fromLng, float $toLat, float $toLng): float
    {
        $km = self::ROAD_FACTOR * Trip::haversineMeters($fromLat, $fromLng, $toLat, $toLng) / 1000;

        return $km / self::AVERAGE_SPEED_KMH * 3600;
    }

    private function distanceLabel(float $meters): string
    {
        return $meters < 950
            ? (int) (round($meters / 50) * 50).' m'
            : number_format($meters / 1000, 1, ',', '').' km';
    }
}
