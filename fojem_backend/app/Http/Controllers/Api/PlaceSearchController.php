<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\MeetingPlace;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

/**
 * Recherche de lieux connus de FOJËM (gares routières, péages, ronds-points,
 * stations) par leur nom, sans tenir compte des accents, de la casse ni des
 * tirets : « gare routiere thies » trouve « Gare routière de Thiès ». Les
 * deux applis l'interrogent avant OpenStreetMap, dont les résultats sont
 * moins fiables pour ces lieux de rendez-vous.
 */
class PlaceSearchController extends Controller
{
    private const LIMIT = 8;

    /** Caractères ramenés à leur forme simple, un pour un (translate SQL). */
    private const FROM = "àâäáãåçéèêëíìîïñóòôöõúùûüýÿ-'’";
    private const TO = 'aaaaaaceeeeiiiinooooouuuuyy   ';

    /** Ordre d'affichage à pertinence égale : les vrais lieux de départ d'abord. */
    private const KIND_RANK = "CASE kind WHEN 'gare_routiere' THEN 0 WHEN 'peage' THEN 1 WHEN 'rond_point' THEN 2 ELSE 3 END";

    public function search(Request $request)
    {
        $data = $request->validate([
            'q' => ['required', 'string', 'min:2', 'max:80'],
            'lat' => ['sometimes', 'numeric', 'between:-90,90'],
            'lng' => ['sometimes', 'numeric', 'between:-180,180'],
        ]);

        $words = collect(preg_split('/\s+/', $this->normalize($data['q'])))
            ->filter(fn (string $word) => mb_strlen($word) >= 2)
            ->take(5)
            ->values();
        if ($words->isEmpty()) {
            return response()->json(['places' => []]);
        }

        $name = 'translate(lower(name), ?, ?)';
        $query = MeetingPlace::query()->select(['id', 'kind', 'name', 'address', 'lat', 'lng']);
        foreach ($words as $word) {
            $query->whereRaw("{$name} LIKE ?", [self::FROM, self::TO, '%'.$this->escapeLike($word).'%']);
        }

        // Le nom qui commence par la recherche passe devant, puis le type de
        // lieu, puis la proximité quand la position du passager est connue.
        $query->orderByRaw("CASE WHEN {$name} LIKE ? THEN 0 ELSE 1 END", [self::FROM, self::TO, $this->escapeLike($words->first()).'%'])
            ->orderByRaw(self::KIND_RANK);
        if (isset($data['lat'], $data['lng'])) {
            $query->orderByRaw(
                'location_geom <-> ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography',
                [(float) $data['lng'], (float) $data['lat']],
            );
        }
        // OpenStreetMap a souvent plusieurs points du même nom (les deux
        // sens d'un péage) : on garde le premier, donc le plus proche.
        $places = $query->orderBy('name')->limit(self::LIMIT * 5)->get()
            ->unique(fn (MeetingPlace $place) => $this->normalize($place->name))
            ->take(self::LIMIT);

        return response()->json([
            'places' => $places->map(fn (MeetingPlace $place) => [
                'id' => $place->id,
                'kind' => $place->kind,
                'name' => $place->name,
                'address' => $place->address,
                'lat' => $place->lat,
                'lng' => $place->lng,
            ])->values(),
        ]);
    }

    /** Minuscules, sans accents ni tirets, espaces simples. */
    private function normalize(string $text): string
    {
        $text = mb_strtolower(trim($text));
        $text = strtr($text, array_combine(mb_str_split(self::FROM), mb_str_split(self::TO)));

        return trim(preg_replace('/\s+/', ' ', $text));
    }

    private function escapeLike(string $text): string
    {
        return str_replace(['\\', '%', '_'], ['\\\\', '\\%', '\\_'], $text);
    }
}
