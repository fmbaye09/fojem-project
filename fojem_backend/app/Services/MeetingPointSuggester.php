<?php

namespace App\Services;

use App\Models\Booking;
use App\Models\MeetingPlace;
use App\Models\Trip;
use Illuminate\Support\Facades\DB;

/**
 * Points de rendez-vous à suggérer au chauffeur qui publie un trajet : les
 * arrêts que d'autres trajets ont déjà utilisés sur sa route d'abord, puis
 * les gares routières, péages, ronds-points et stations d'OpenStreetMap.
 * Au plus un tous les quelques km, dans l'ordre de la route.
 */
class MeetingPointSuggester
{
    public const KIND_FREQUENT = 'frequent';

    private const MAX_SUGGESTIONS = 8;

    /** Un arrêt déjà publié compte s'il est à moins de ça de la route. */
    private const FREQUENT_RADIUS_METERS = 1000;

    /** Les lieux d'OSM comptent plus près de la route que les arrêts déjà publiés. */
    private const PLACE_RADIUS_METERS = 600;

    /** Des arrêts publiés à moins de ça les uns des autres sont le même lieu. */
    private const SAME_PLACE_METERS = 300;

    /** Écart minimal, le long de la route, entre deux suggestions. */
    private const SPACING_KM = 4.0;

    /** Rien de trop près d'un point déjà choisi par le chauffeur... */
    private const NEAR_STOP_METERS = 1500;

    /** ...ni au tout début ou à la toute fin de la route. */
    private const ENDS_KM = 3.0;

    private const MAX_LINE_POINTS = 150;

    private const MIN_LINE_STEP_METERS = 200;

    private const KIND_SCORE = [
        OverpassService::KIND_BUS_STATION => 60,
        OverpassService::KIND_TOLL => 50,
        OverpassService::KIND_ROUNDABOUT => 40,
        OverpassService::KIND_FUEL => 30,
    ];

    public function __construct(private readonly RoutingService $routing)
    {
    }

    /**
     * @param  list<array{0: float, 1: float}>  $points  départ, arrêts déjà choisis, arrivée ([lat, lng])
     * @return list<array{name: string, address: ?string, kind: string, lat: float, lng: float, km_from_start: int, trips_count: int, passengers_count: int}>
     */
    public function suggest(array $points): array
    {
        // Le tracé routier ; à défaut, les segments droits entre les points.
        $line = $this->thin($this->routing->route($points, true)['geometry'] ?? []);
        if (count($line) < 2) {
            $line = $points;
        }
        $cumulative = $this->cumulativeKm($line);
        $totalKm = end($cumulative);

        $wkt = $this->lineWkt($line);
        $candidates = [...$this->frequentStops($wkt), ...$this->knownPlaces($wkt)];

        $scored = [];
        foreach ($candidates as $candidate) {
            [$offRouteMeters, $alongKm] = $this->project($candidate['lat'], $candidate['lng'], $line, $cumulative);
            $radius = $candidate['kind'] === self::KIND_FREQUENT ? self::FREQUENT_RADIUS_METERS : self::PLACE_RADIUS_METERS;
            if ($offRouteMeters > $radius || $alongKm < self::ENDS_KM || $alongKm > $totalKm - self::ENDS_KM) {
                continue;
            }
            foreach ($points as $point) {
                if (Trip::haversineMeters($point[0], $point[1], $candidate['lat'], $candidate['lng']) < self::NEAR_STOP_METERS) {
                    continue 2;
                }
            }
            $scored[] = $candidate + [
                'along' => $alongKm,
                'score' => $candidate['kind'] === self::KIND_FREQUENT
                    ? 100 + 10 * $candidate['trips_count'] + 5 * $candidate['passengers_count']
                    : (self::KIND_SCORE[$candidate['kind']] ?? 0),
            ];
        }

        // Les meilleurs d'abord, en gardant de l'espace entre eux.
        usort($scored, fn (array $a, array $b) => [$b['score'], $a['along']] <=> [$a['score'], $b['along']]);
        $picked = [];
        foreach ($scored as $candidate) {
            foreach ($picked as $other) {
                if (abs($other['along'] - $candidate['along']) < self::SPACING_KM) {
                    continue 2;
                }
            }
            $picked[] = $candidate;
            if (count($picked) >= self::MAX_SUGGESTIONS) {
                break;
            }
        }
        usort($picked, fn (array $a, array $b) => $a['along'] <=> $b['along']);

        return array_map(fn (array $c) => [
            'name' => $c['name'],
            'address' => $c['address'] ?? null,
            'kind' => $c['kind'],
            'lat' => round($c['lat'], 6),
            'lng' => round($c['lng'], 6),
            'km_from_start' => (int) round($c['along']),
            'trips_count' => $c['trips_count'],
            'passengers_count' => $c['passengers_count'],
        ], $picked);
    }

    /**
     * Arrêts déjà publiés près de la route, regroupés par lieu : combien de
     * trajets y passaient et combien de passagers y sont montés ou descendus.
     *
     * @return list<array{name: string, address: ?string, kind: string, lat: float, lng: float, trips_count: int, passengers_count: int}>
     */
    private function frequentStops(string $wkt): array
    {
        $rows = DB::select(
            'SELECT s.trip_id, s.name, s.address, s.lat, s.lng,
                    (SELECT COUNT(*) FROM bookings b
                      WHERE b.deleted_at IS NULL AND b.status IN (?, ?)
                        AND (b.boarding_stop_id = s.id OR b.alighting_stop_id = s.id)) AS passengers
               FROM trip_stops s
               JOIN trips t ON t.id = s.trip_id AND t.deleted_at IS NULL
              WHERE ST_DWithin(s.location_geom, ST_GeogFromText(?), ?)
              ORDER BY s.created_at DESC
              LIMIT 500',
            [Booking::STATUS_CONFIRMED, Booking::STATUS_COMPLETED, $wkt, self::FREQUENT_RADIUS_METERS],
        );

        $clusters = [];
        foreach ($rows as $row) {
            $lat = (float) $row->lat;
            $lng = (float) $row->lng;
            $index = null;
            foreach ($clusters as $i => $cluster) {
                if (Trip::haversineMeters($cluster['lat'], $cluster['lng'], $lat, $lng) <= self::SAME_PLACE_METERS) {
                    $index = $i;
                    break;
                }
            }
            if ($index === null) {
                $clusters[] = ['lat' => $lat, 'lng' => $lng, 'trips' => [], 'passengers' => 0, 'names' => []];
                $index = array_key_last($clusters);
            }
            $clusters[$index]['trips'][$row->trip_id] = true;
            $clusters[$index]['passengers'] += (int) $row->passengers;
            $key = $row->name;
            $clusters[$index]['names'][$key] ??= ['count' => 0, 'address' => $row->address];
            $clusters[$index]['names'][$key]['count']++;
        }

        return array_map(function (array $cluster) {
            // Le nom le plus souvent donné à ce lieu.
            uasort($cluster['names'], fn (array $a, array $b) => $b['count'] <=> $a['count']);
            $name = (string) array_key_first($cluster['names']);
            $address = $cluster['names'][$name]['address'];

            return [
                'name' => $name,
                'address' => $address !== $name ? $address : null,
                'kind' => self::KIND_FREQUENT,
                'lat' => $cluster['lat'],
                'lng' => $cluster['lng'],
                'trips_count' => count($cluster['trips']),
                'passengers_count' => $cluster['passengers'],
            ];
        }, $clusters);
    }

    /**
     * Gares routières, péages, ronds-points et stations d'OpenStreetMap près
     * de la route (importés chaque mois, voir MeetingPlaceImporter).
     *
     * @return list<array{name: string, address: ?string, kind: string, lat: float, lng: float, trips_count: int, passengers_count: int}>
     */
    private function knownPlaces(string $wkt): array
    {
        return MeetingPlace::query()
            ->whereRaw('ST_DWithin(location_geom, ST_GeogFromText(?), ?)', [$wkt, self::PLACE_RADIUS_METERS])
            ->limit(500)
            ->get()
            ->map(fn (MeetingPlace $place) => [
                'name' => $place->name,
                'address' => $place->address,
                'kind' => $place->kind,
                'lat' => $place->lat,
                'lng' => $place->lng,
                'trips_count' => 0,
                'passengers_count' => 0,
            ])
            ->all();
    }

    private function lineWkt(array $line): string
    {
        return 'SRID=4326;LINESTRING('.implode(',', array_map(
            fn (array $p) => sprintf('%.6F %.6F', $p[1], $p[0]),
            $line,
        )).')';
    }

    /** Assez de points pour suivre la route, pas trop pour les requêtes. */
    private function thin(array $line): array
    {
        if (count($line) < 3) {
            return $line;
        }
        $kept = [$line[0]];
        foreach (array_slice($line, 1, -1) as $point) {
            $last = end($kept);
            if (Trip::haversineMeters($last[0], $last[1], $point[0], $point[1]) >= self::MIN_LINE_STEP_METERS) {
                $kept[] = $point;
            }
        }
        $kept[] = end($line);

        if (count($kept) > self::MAX_LINE_POINTS) {
            $step = (count($kept) - 1) / (self::MAX_LINE_POINTS - 1);
            $sampled = [];
            for ($i = 0; $i < self::MAX_LINE_POINTS; $i++) {
                $sampled[] = $kept[(int) round($i * $step)];
            }
            $kept = $sampled;
        }

        return $kept;
    }

    /** @return list<float> km depuis le début de la ligne, à chaque point */
    private function cumulativeKm(array $line): array
    {
        $cumulative = [0.0];
        for ($i = 1; $i < count($line); $i++) {
            $cumulative[] = $cumulative[$i - 1]
                + Trip::haversineMeters($line[$i - 1][0], $line[$i - 1][1], $line[$i][0], $line[$i][1]) / 1000;
        }

        return $cumulative;
    }

    /**
     * Distance du point à la ligne (m) et position le long de celle-ci (km),
     * par projection sur chaque segment (approximation locale plane).
     *
     * @return array{0: float, 1: float}
     */
    private function project(float $lat, float $lng, array $line, array $cumulative): array
    {
        $best = [INF, 0.0];
        for ($i = 0; $i < count($line) - 1; $i++) {
            [$aLat, $aLng] = $line[$i];
            [$bLat, $bLng] = $line[$i + 1];
            $cos = cos(deg2rad($aLat));
            $bx = ($bLng - $aLng) * 111320 * $cos;
            $by = ($bLat - $aLat) * 110540;
            $px = ($lng - $aLng) * 111320 * $cos;
            $py = ($lat - $aLat) * 110540;
            $lengthSquared = $bx * $bx + $by * $by;
            $t = $lengthSquared > 0 ? max(0.0, min(1.0, ($px * $bx + $py * $by) / $lengthSquared)) : 0.0;
            $distance = hypot($px - $t * $bx, $py - $t * $by);
            if ($distance < $best[0]) {
                $best = [$distance, $cumulative[$i] + $t * ($cumulative[$i + 1] - $cumulative[$i])];
            }
        }

        return $best;
    }
}
