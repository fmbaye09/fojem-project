<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Trip;
use App\Services\MeetingPointSuggester;
use App\Services\StopInsertionPlanner;
use Illuminate\Http\Request;

/**
 * Points de rendez-vous : suggestions au chauffeur qui publie, et aperçu de
 * l'arrêt qu'un passager propose sur un trajet.
 */
class MeetingPointController extends Controller
{
    private const MAX_POINTS = 12;

    /**
     * Arrêts à suggérer sur la route du chauffeur. `points` : départ, arrêts
     * déjà choisis et arrivée, dans l'ordre (« lat,lng;lat,lng;… »).
     */
    public function suggestions(Request $request, MeetingPointSuggester $suggester)
    {
        if (! $request->user()->driver) {
            return response()->json(['message' => 'Profil chauffeur requis.'], 403);
        }

        $request->validate(['points' => ['required', 'string', 'max:400']]);
        $points = [];
        foreach (explode(';', $request->string('points')->value()) as $pair) {
            $parts = explode(',', trim($pair));
            if (count($parts) !== 2 || ! is_numeric($parts[0]) || ! is_numeric($parts[1])
                || abs((float) $parts[0]) > 90 || abs((float) $parts[1]) > 180) {
                return response()->json(['message' => 'Points invalides.', 'errors' => ['points' => ['Format attendu : lat,lng;lat,lng']]], 422);
            }
            $points[] = [(float) $parts[0], (float) $parts[1]];
        }
        if (count($points) < 2 || count($points) > self::MAX_POINTS) {
            return response()->json(['message' => 'Indiquez entre 2 et '.self::MAX_POINTS.' points.'], 422);
        }

        return response()->json(['suggestions' => $suggester->suggest($points)]);
    }

    /**
     * Ce que coûterait au chauffeur l'arrêt que propose le passager : détour,
     * heure de passage et prix, ou la raison du refus (422).
     */
    public function preview(Request $request, Trip $trip, StopInsertionPlanner $planner)
    {
        $data = $request->validate([
            'role' => ['required', 'in:boarding,alighting'],
            'lat' => ['required', 'numeric', 'between:-90,90'],
            'lng' => ['required', 'numeric', 'between:-180,180'],
            'name' => ['sometimes', 'nullable', 'string', 'max:120'],
            'address' => ['sometimes', 'nullable', 'string', 'max:255'],
        ]);

        if ($request->user()->driver && $trip->driver_id === $request->user()->driver->id) {
            return response()->json(['message' => 'Vous ne pouvez pas réserver votre propre trajet.'], 422);
        }

        return response()->json([
            'proposal' => $planner->preview(
                $trip, $data['role'], (float) $data['lat'], (float) $data['lng'], $data['name'] ?? null, $data['address'] ?? null,
            ),
        ]);
    }
}
