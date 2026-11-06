<?php

namespace App\Services;

use App\Models\Trip;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Lieux de rendez-vous connus d'OpenStreetMap, via l'API Overpass (gratuite) :
 * gares routières, stations-service, péages et ronds-points nommés, chacun
 * situé par la localité la plus proche (« Péage de Diamniadio »).
 *
 * Le serveur public n'accepte pas d'usage automatisé intensif : ces lieux
 * sont importés en une requête pour tout le pays (fojem:import-meeting-places,
 * une fois par mois) et les suggestions lisent ensuite la base locale.
 */
class OverpassService
{
    public const KIND_BUS_STATION = 'gare_routiere';
    public const KIND_FUEL = 'station';
    public const KIND_TOLL = 'peage';
    public const KIND_ROUNDABOUT = 'rond_point';

    /** Sénégal : sud, ouest, nord, est. */
    public const SENEGAL_BBOX = [12.2, -17.6, 16.7, -11.3];

    /** Une localité situe un lieu jusqu'à cette distance (pondérée par sa taille). */
    private const LOCALITY_MAX_METERS = 6000;

    /** Une ville compte comme plus proche qu'un village à la même distance. */
    private const LOCALITY_WEIGHT = ['city' => 0.4, 'town' => 0.5, 'suburb' => 0.7, 'village' => 1.0];

    private const GRID_DEGREES = 0.1;

    /**
     * Tous les lieux de la zone, ou null si le serveur ne répond pas.
     *
     * @param  array{0: float, 1: float, 2: float, 3: float}  $bbox  sud, ouest, nord, est
     * @return list<array{osm_id: string, name: string, kind: string, lat: float, lng: float, address: ?string}>|null
     */
    public function placesIn(array $bbox): ?array
    {
        $url = (string) config('services.overpass.url');
        if ($url === '') {
            return null;
        }

        $box = implode(',', array_map(fn ($v) => sprintf('%.4F', $v), $bbox));
        $query = <<<OVERPASS
            [out:json][timeout:180][bbox:{$box}];
            (
              nwr["amenity"="bus_station"];
              nwr["amenity"="fuel"];
              node["barrier"="toll_booth"];
              way["junction"="roundabout"]["name"];
              node["place"~"^(city|town|suburb|village)$"]["name"];
            );
            out center tags;
            OVERPASS;

        try {
            $response = Http::asForm()
                ->timeout((float) config('services.overpass.timeout', 200))
                ->withUserAgent('FOJEM/1.0 (contact@fojem.sn)')
                ->post($url, ['data' => $query]);
        } catch (\Throwable $e) {
            Log::info("Overpass unavailable: {$e->getMessage()}");

            return null;
        }

        $elements = $response->ok() ? $response->json('elements') : null;
        if (! is_array($elements)) {
            Log::info("Overpass refused the query: HTTP {$response->status()}");

            return null;
        }

        $raw = [];
        $localities = [];
        foreach ($elements as $element) {
            if (! is_array($element)) {
                continue;
            }
            if (isset($element['tags']['place'])) {
                $locality = $this->locality($element);
                if ($locality !== null) {
                    $localities[$this->cell($locality['lat'], $locality['lng'])][] = $locality;
                }
            } elseif (($place = $this->place($element)) !== null) {
                $raw[] = $place;
            }
        }

        $places = [];
        foreach ($raw as $place) {
            $place = $this->locate($place, $place['city'] ?? $this->nearestLocality($localities, $place['lat'], $place['lng']));
            if ($place !== null) {
                $places[] = $place;
            }
        }

        return $places;
    }

    /** @return array{osm_id: string, name: string, kind: string, lat: float, lng: float, city: ?string}|null */
    private function place(array $element): ?array
    {
        $tags = (array) ($element['tags'] ?? []);
        $lat = $element['lat'] ?? $element['center']['lat'] ?? null;
        $lng = $element['lon'] ?? $element['center']['lon'] ?? null;
        if (! is_numeric($lat) || ! is_numeric($lng) || ! isset($element['type'], $element['id'])) {
            return null;
        }

        $kind = match (true) {
            ($tags['amenity'] ?? null) === 'bus_station' => self::KIND_BUS_STATION,
            ($tags['amenity'] ?? null) === 'fuel' => self::KIND_FUEL,
            ($tags['barrier'] ?? null) === 'toll_booth' => self::KIND_TOLL,
            ($tags['junction'] ?? null) === 'roundabout' => self::KIND_ROUNDABOUT,
            default => null,
        };
        if ($kind === null) {
            return null;
        }

        $name = trim((string) ($tags['name:fr'] ?? $tags['name'] ?? ''));
        if ($name === '' && $kind === self::KIND_FUEL && ! empty($tags['brand'])) {
            $name = 'Station '.trim((string) $tags['brand']);
        }
        $city = trim((string) ($tags['addr:city'] ?? ''));

        return [
            'osm_id' => "{$element['type']}/{$element['id']}",
            'name' => $name,
            'kind' => $kind,
            'lat' => (float) $lat,
            'lng' => (float) $lng,
            'city' => $city !== '' ? $city : null,
        ];
    }

    /**
     * Nom final et adresse : un péage ou une gare sans nom prend celui de sa
     * localité ; une station sans nom ni marque ne se retrouve pas sur place.
     *
     * @return array{osm_id: string, name: string, kind: string, lat: float, lng: float, address: ?string}|null
     */
    private function locate(array $place, ?string $locality): ?array
    {
        $name = $place['name'];
        $generic = $name === '' ? match ($place['kind']) {
            self::KIND_BUS_STATION => 'Gare routière',
            self::KIND_TOLL => 'Péage',
            default => null,
        } : (in_array(mb_strtolower($name), ['péage', 'peage', 'gare routière', 'gare routiere'], true) ? $name : null);

        if ($generic !== null) {
            $name = $locality !== null ? $generic.' '.$this->of($locality) : $generic;
        }
        if ($name === '') {
            return null;
        }

        return [
            'osm_id' => $place['osm_id'],
            'name' => mb_substr($name, 0, 120),
            'kind' => $place['kind'],
            'lat' => $place['lat'],
            'lng' => $place['lng'],
            'address' => $locality !== null && ! str_contains(mb_strtolower($name), mb_strtolower($locality))
                ? mb_substr("{$name}, {$locality}", 0, 255)
                : null,
        ];
    }

    /** @return array{name: string, lat: float, lng: float, weight: float}|null */
    private function locality(array $element): ?array
    {
        $tags = (array) ($element['tags'] ?? []);
        $name = trim((string) ($tags['name:fr'] ?? $tags['name'] ?? ''));
        $weight = self::LOCALITY_WEIGHT[$tags['place'] ?? ''] ?? null;
        if ($name === '' || $weight === null || ! is_numeric($element['lat'] ?? null) || ! is_numeric($element['lon'] ?? null)) {
            return null;
        }

        return ['name' => $name, 'lat' => (float) $element['lat'], 'lng' => (float) $element['lon'], 'weight' => $weight];
    }

    /** Localité la plus proche, les villes l'emportant sur les villages voisins. */
    private function nearestLocality(array $grid, float $lat, float $lng): ?string
    {
        [$row, $col] = array_map('intval', explode(':', $this->cell($lat, $lng)));
        $best = null;
        $bestScore = self::LOCALITY_MAX_METERS;
        for ($r = $row - 1; $r <= $row + 1; $r++) {
            for ($c = $col - 1; $c <= $col + 1; $c++) {
                foreach ($grid["{$r}:{$c}"] ?? [] as $locality) {
                    $score = Trip::haversineMeters($lat, $lng, $locality['lat'], $locality['lng']) * $locality['weight'];
                    if ($score < $bestScore) {
                        $bestScore = $score;
                        $best = $locality['name'];
                    }
                }
            }
        }

        return $best;
    }

    private function cell(float $lat, float $lng): string
    {
        return ((int) floor($lat / self::GRID_DEGREES)).':'.((int) floor($lng / self::GRID_DEGREES));
    }

    /** « de Rufisque », « d’Ouakam ». */
    private function of(string $locality): string
    {
        return preg_match('/^[aeiouyhàâéèêîôûAEIOUYHÀÂÉÈÊÎÔÛ]/u', $locality) ? "d’{$locality}" : "de {$locality}";
    }
}
