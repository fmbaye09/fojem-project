<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\Drivers\StorePendingVehicleRequest;
use App\Models\Driver;
use App\Models\Review;

class DriverController extends Controller
{
    /**
     * Saves/updates the vehicle info a driver enters during activation
     * (before verification is approved, so there is no real Vehicle row
     * yet). DriverVerificationService::recompute() consumes these fields
     * into an actual Vehicle the moment the driver's documents are all
     * approved for the first time.
     */
    public function updateVehicleInfo(StorePendingVehicleRequest $request)
    {
        $user = $request->user();
        $driver = $user->driver;

        if (! $user->is_driver || ! $driver) {
            return response()->json(['message' => 'Profil chauffeur requis.'], 403);
        }

        $driver->update([
            'pending_vehicle_brand' => $request->input('brand'),
            'pending_vehicle_model' => $request->input('model'),
            'pending_vehicle_color' => $request->input('color'),
            'pending_vehicle_plate_number' => $request->input('plate_number'),
            'pending_vehicle_seat_count' => $request->input('seat_count'),
        ]);

        return response()->json(['driver' => $driver->fresh()]);
    }

    /**
     * Public driver profile: basic identity + rating + recent public
     * reviews. No documents, no verification detail, no sensitive data -
     * that's all admin-only (see Api\Admin\DriverController).
     *
     * Keyed by users.id (not drivers.id): every place a client app holds a
     * driver reference - Trip.driver_id embed, chat contact id - is a
     * users.id, never the drivers table's own primary key. Resolving by
     * drivers.id here would 404 on every real call site.
     */
    public function show(string $userId)
    {
        $driver = Driver::where('user_id', $userId)->firstOrFail();
        $driver->load('user');

        $recentReviews = Review::where('reviewee_id', $driver->user_id)
            ->where('is_flagged', false)
            ->latest()
            ->limit(5)
            ->get(['id', 'punctuality_rating', 'driving_rating', 'communication_rating', 'safety_rating', 'comment', 'created_at']);

        return response()->json([
            'driver' => [
                'id' => $driver->id,
                'full_name' => $driver->user->full_name,
                'profile_photo_url' => $driver->user->profile_photo_url,
                'average_rating' => $driver->average_rating,
                'total_trips_completed' => $driver->total_trips_completed,
                'recent_reviews' => $recentReviews,
            ],
        ]);
    }
}
