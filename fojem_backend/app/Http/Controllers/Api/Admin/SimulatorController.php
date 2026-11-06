<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Models\Notification;
use App\Models\Trip;
use App\Models\User;
use App\Services\RoutingService;
use App\Services\SimulatorService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * API du simulateur du dashboard (local uniquement, voir
 * EnsureSimulatorEnabled). Elle crée les acteurs et prépare les scénarios ;
 * tout le reste (publier, réserver, rouler, déclarer une absence…) passe
 * par l'API publique avec le jeton de chaque acteur, comme dans les applis.
 */
class SimulatorController extends Controller
{
    private const MAX_POINTS = 12;

    /** Vitesse moyenne quand l'itinéraire routier est indisponible. */
    private const FALLBACK_SPEED_KMH = 60;
    private const ROAD_FACTOR = 1.25;

    public function __construct(private readonly SimulatorService $simulator)
    {
    }

    public function status()
    {
        return response()->json([
            'enabled' => true,
            'osrm' => (string) config('services.osrm.url') !== '',
            'simulated_users' => User::where('is_simulated', true)->count(),
        ]);
    }

    public function createActor(Request $request)
    {
        $data = $request->validate([
            'role' => ['required', 'in:driver,passenger'],
            'name' => ['sometimes', 'nullable', 'string', 'max:80'],
            'seats' => ['sometimes', 'integer', 'min:1', 'max:15'],
        ]);
        $actor = $this->simulator->createActor($data['role'], $data['name'] ?? null, (int) ($data['seats'] ?? 7));

        return response()->json([
            'actor' => [
                'id' => $actor['user']->id,
                'role' => $data['role'],
                'full_name' => $actor['user']->full_name,
                'phone_number' => $actor['user']->phone_number,
                'vehicle_id' => $actor['vehicle_id'],
                'token' => $actor['token'],
            ],
        ], 201);
    }

    /**
     * Tracé complet de la route passant par ces points (« lat,lng;… »), pour
     * y faire rouler le chauffeur simulé ; segments droits sans OSRM.
     */
    public function route(Request $request, RoutingService $routing)
    {
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

        $route = $routing->route($points, true, true);
        if ($route !== null && count($route['geometry']) >= 2) {
            return response()->json([
                'source' => 'osrm',
                'geometry' => $route['geometry'],
                'legs' => array_map(
                    fn ($duration, $distance) => ['duration' => $duration, 'distance' => $distance],
                    $route['durations'],
                    $route['distances'],
                ),
            ]);
        }

        // Sans OSRM : lignes droites, durées estimées comme à la publication.
        $legs = [];
        for ($i = 1; $i < count($points); $i++) {
            $meters = Trip::haversineMeters($points[$i - 1][0], $points[$i - 1][1], $points[$i][0], $points[$i][1]);
            $legs[] = [
                'duration' => round(self::ROAD_FACTOR * $meters / 1000 / self::FALLBACK_SPEED_KMH * 3600),
                'distance' => round($meters),
            ];
        }

        return response()->json(['source' => 'straight', 'geometry' => $points, 'legs' => $legs]);
    }

    /** Fait dater le trajet et ses réservations d'il y a N minutes (rappels « 30 min avant »). */
    public function backdate(Request $request)
    {
        $data = $request->validate([
            'trip_id' => ['sometimes', 'nullable', 'uuid'],
            'booking_ids' => ['sometimes', 'array', 'max:50'],
            'booking_ids.*' => ['uuid'],
            'minutes' => ['required', 'integer', 'min:1', 'max:1440'],
        ]);
        $trip = isset($data['trip_id']) ? Trip::find($data['trip_id']) : null;
        if ($trip !== null && ! $this->simulator->isSimulatedTrip($trip)) {
            return response()->json(['message' => 'Seul un trajet du simulateur peut être vieilli.'], 422);
        }

        return response()->json($this->simulator->backdate($trip, $data['booking_ids'] ?? [], (int) $data['minutes']));
    }

    /**
     * Notifications reçues par les comptes simulés, et par tout compte à
     * propos des trajets du scénario (un vrai téléphone qui y a réservé).
     */
    public function notifications(Request $request)
    {
        $data = $request->validate([
            'trip_ids' => ['sometimes', 'array', 'max:20'],
            'trip_ids.*' => ['uuid'],
        ]);
        $tripIds = $data['trip_ids'] ?? [];

        $notifications = Notification::query()
            ->with('user:id,full_name,is_simulated')
            ->where(function ($q) use ($tripIds) {
                $q->whereIn('user_id', User::where('is_simulated', true)->select('id'));
                if ($tripIds !== []) {
                    $q->orWhereIn(DB::raw("payload->>'trip_id'"), $tripIds);
                }
            })
            ->latest()
            ->limit(200)
            ->get()
            ->map(fn (Notification $n) => [
                'id' => $n->id,
                'user_id' => $n->user_id,
                'user_name' => $n->user?->full_name,
                'simulated' => (bool) $n->user?->is_simulated,
                'type' => $n->type,
                'title' => $n->title,
                'body' => $n->payload['body'] ?? null,
                'trip_id' => $n->payload['trip_id'] ?? null,
                'booking_id' => $n->payload['booking_id'] ?? null,
                'created_at' => $n->created_at?->toIso8601String(),
            ]);

        return response()->json(['notifications' => $notifications]);
    }

    public function reset()
    {
        return response()->json($this->simulator->reset());
    }
}
