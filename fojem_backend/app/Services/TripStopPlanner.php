<?php

namespace App\Services;

use App\Models\Trip;
use Carbon\CarbonImmutable;
use Illuminate\Validation\ValidationException;

/**
 * Turns the stops a driver publishes into a complete, consistent plan:
 * every stop gets a time and a price from the departure.
 *
 * The driver app sends road-based values (OSRM legs); when a value is
 * missing (older app, legacy waypoints), it is estimated here from the
 * straight-line distance so the trip is still bookable.
 */
class TripStopPlanner
{
    /** Straight line → road distance, and average interurban speed. */
    private const ROAD_FACTOR = 1.25;
    private const AVERAGE_SPEED_KMH = 60;
    private const PRICE_ROUNDING = 50;

    /**
     * @param  list<array{name: string, address?: ?string, lat: float, lng: float, scheduled_at?: ?string, price_from_origin?: ?float}>  $stops
     * @return list<array{position: int, name: string, address: ?string, lat: float, lng: float, scheduled_at: CarbonImmutable, price_from_origin: float}>
     */
    public function plan(array $stops, CarbonImmutable $departureAt, float $fullPrice): array
    {
        $count = count($stops);
        $cumulativeKm = [0.0];
        for ($i = 1; $i < $count; $i++) {
            $cumulativeKm[$i] = $cumulativeKm[$i - 1] + self::ROAD_FACTOR * Trip::haversineMeters(
                (float) $stops[$i - 1]['lat'], (float) $stops[$i - 1]['lng'],
                (float) $stops[$i]['lat'], (float) $stops[$i]['lng'],
            ) / 1000;
        }
        $totalKm = max($cumulativeKm[$count - 1], 0.001);

        $planned = [];
        $previousTime = $departureAt;
        $previousPrice = 0.0;

        foreach ($stops as $i => $stop) {
            $time = match (true) {
                $i === 0 => $departureAt,
                ! empty($stop['scheduled_at']) => CarbonImmutable::parse($stop['scheduled_at']),
                default => $previousTime->addMinutes((int) ceil(
                    ($cumulativeKm[$i] - $cumulativeKm[$i - 1]) / self::AVERAGE_SPEED_KMH * 60
                )),
            };
            if ($time->lt($previousTime)) {
                throw ValidationException::withMessages([
                    "stops.$i.scheduled_at" => "L'heure de « {$stop['name']} » doit suivre celle de l'arrêt précédent.",
                ]);
            }

            $price = match (true) {
                $i === 0 => 0.0,
                $i === $count - 1 => $fullPrice,
                isset($stop['price_from_origin']) => (float) $stop['price_from_origin'],
                default => round($fullPrice * $cumulativeKm[$i] / $totalKm / self::PRICE_ROUNDING) * self::PRICE_ROUNDING,
            };
            if ($price < $previousPrice || $price > $fullPrice) {
                throw ValidationException::withMessages([
                    "stops.$i.price_from_origin" => "Le prix jusqu'à « {$stop['name']} » doit être compris entre celui de l'arrêt précédent et le prix du trajet complet.",
                ]);
            }

            $planned[] = [
                'position' => $i,
                'name' => $stop['name'],
                'address' => $stop['address'] ?? null,
                'lat' => (float) $stop['lat'],
                'lng' => (float) $stop['lng'],
                'scheduled_at' => $time,
                'price_from_origin' => $price,
            ];
            $previousTime = $time;
            $previousPrice = $price;
        }

        return $planned;
    }

    /**
     * Stops for a client that still sends origin / waypoints / destination
     * instead of `stops`.
     */
    public function fromLegacyFields(array $input): array
    {
        $stops = [[
            'name' => $input['origin_name'] ?? 'Départ',
            'lat' => $input['origin_lat'],
            'lng' => $input['origin_lng'],
        ]];
        foreach ($input['waypoints'] ?? [] as $wp) {
            $stops[] = ['name' => $wp['name'] ?? 'Étape', 'lat' => $wp['lat'], 'lng' => $wp['lng']];
        }
        $stops[] = [
            'name' => $input['destination_name'] ?? 'Arrivée',
            'lat' => $input['destination_lat'],
            'lng' => $input['destination_lng'],
        ];

        return $stops;
    }
}
