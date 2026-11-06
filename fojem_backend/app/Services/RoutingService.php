<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Durées de route entre des points, via OSRM (gratuit ; serveur public par
 * défaut, ou auto-hébergé : config services.osrm.url).
 */
class RoutingService
{
    /**
     * Durée en secondes de chaque tronçon entre ces points, dans l'ordre, ou
     * null si le service est désactivé ou ne répond pas : l'appelant garde
     * alors son estimation.
     *
     * @param  list<array{0: float, 1: float}>  $points  [lat, lng]
     * @return list<float>|null
     */
    public function legDurations(array $points): ?array
    {
        return $this->route($points)['durations'] ?? null;
    }

    /**
     * Itinéraire passant par ces points : durée (s) et distance (m) de chaque
     * tronçon, et, sur demande, le tracé simplifié de la route ([lat, lng]).
     *
     * @param  list<array{0: float, 1: float}>  $points  [lat, lng]
     * @return array{durations: list<float>, distances: list<float>, geometry: list<array{0: float, 1: float}>}|null
     */
    public function route(array $points, bool $withGeometry = false): ?array
    {
        $base = rtrim((string) config('services.osrm.url'), '/');
        if ($base === '' || count($points) < 2) {
            return null;
        }

        // OSRM attend « lng,lat » séparés par « ; ».
        $coordinates = implode(';', array_map(
            fn (array $p) => sprintf('%.6F,%.6F', $p[1], $p[0]),
            $points,
        ));

        try {
            $response = Http::timeout((float) config('services.osrm.timeout', 4))
                ->withUserAgent('FOJEM/1.0 (contact@fojem.sn)')
                ->get("{$base}/route/v1/driving/{$coordinates}", $withGeometry
                    ? ['overview' => 'simplified', 'geometries' => 'geojson']
                    : ['overview' => 'false']);
        } catch (\Throwable $e) {
            Log::info("OSRM unavailable: {$e->getMessage()}");

            return null;
        }

        $legs = $response->ok() && $response->json('code') === 'Ok' ? $response->json('routes.0.legs') : null;
        if (! is_array($legs) || count($legs) !== count($points) - 1) {
            return null;
        }

        $geometry = [];
        foreach ($withGeometry ? (array) $response->json('routes.0.geometry.coordinates') : [] as $c) {
            if (is_array($c) && isset($c[0], $c[1])) {
                $geometry[] = [(float) $c[1], (float) $c[0]];
            }
        }

        return [
            'durations' => array_map(fn ($leg) => (float) ($leg['duration'] ?? 0), $legs),
            'distances' => array_map(fn ($leg) => (float) ($leg['distance'] ?? 0), $legs),
            'geometry' => $geometry,
        ];
    }
}
