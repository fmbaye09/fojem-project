<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\Vehicles\StoreVehicleRequest;
use App\Models\Vehicle;
use Illuminate\Http\Request;

class VehicleController extends Controller
{
    /**
     * Declares a new vehicle for the authenticated driver. A driver can
     * declare several vehicles (no upsert, no "one active vehicle" limit):
     * every call inserts a new row. There is intentionally no update
     * endpoint - see the immutability note on App\Models\Vehicle. Once
     * declared, a vehicle joins the driver's overall document verification
     * (driver_documents / Driver::verification_status is not per-vehicle -
     * see the README "Vehicules" section) and becomes selectable as
     * `vehicle_id` on POST /api/trips.
     */
    public function store(StoreVehicleRequest $request)
    {
        $user = $request->user();
        $driver = $user->driver;

        if (! $user->is_driver || ! $driver) {
            return response()->json(['message' => 'Profil chauffeur requis.'], 403);
        }

        $vehicle = Vehicle::create([
            'driver_id' => $driver->id,
            'plate_number' => $request->input('plate_number'),
            'brand' => $request->input('brand'),
            'model' => $request->input('model'),
            'color' => $request->input('color'),
            'seat_count' => $request->input('seat_count'),
            'is_active' => true,
        ]);

        return response()->json(['vehicle' => $vehicle->fresh()], 201);
    }

    /** All vehicles declared by the authenticated driver, most recent first. */
    public function index(Request $request)
    {
        $user = $request->user();
        $driver = $user->driver;

        if (! $user->is_driver || ! $driver) {
            return response()->json(['message' => 'Profil chauffeur requis.'], 403);
        }

        $vehicles = Vehicle::where('driver_id', $driver->id)->latest()->get();

        return response()->json(['vehicles' => $vehicles]);
    }

    /** A single vehicle, only if it belongs to the authenticated driver. */
    public function show(Request $request, Vehicle $vehicle)
    {
        $user = $request->user();
        $driver = $user->driver;

        if (! $user->is_driver || ! $driver || $vehicle->driver_id !== $driver->id) {
            return response()->json(['message' => 'Vehicule introuvable.'], 404);
        }

        return response()->json(['vehicle' => $vehicle]);
    }
}
