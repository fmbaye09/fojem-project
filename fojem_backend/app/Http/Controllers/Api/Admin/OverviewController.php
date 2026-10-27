<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Models\Booking;
use App\Models\Dispute;
use App\Models\Driver;
use App\Models\SosAlert;
use App\Models\Transaction;
use App\Models\Trip;
use App\Models\User;
use Illuminate\Support\Facades\DB;

/**
 * Dashboard landing numbers. Every figure below is a direct aggregate query
 * against the live tables (count/sum/group by) - none of it is estimated,
 * cached, sampled or precomputed. That keeps this endpoint simple and
 * always-correct at the data volumes FOJEM runs at; if it ever needs to
 * scale past that, the honest fix is a materialized view/read replica
 * behind the same response shape, not silently swapping in an estimate.
 */
class OverviewController extends Controller
{
    public function index()
    {
        $usersActive = User::where('account_status', 'active')->count();

        $driversTotal = Driver::count();
        $driversPending = Driver::where('verification_status', Driver::STATUS_PENDING)->count();
        $driversApproved = Driver::where('verification_status', Driver::STATUS_APPROVED)->count();

        $tripsByStatus = Trip::select('status', DB::raw('count(*) as total'))
            ->groupBy('status')
            ->pluck('total', 'status');

        $today = now()->startOfDay();
        $weekStart = now()->startOfWeek();

        $bookingsTodayByStatus = Booking::where('created_at', '>=', $today)
            ->select('status', DB::raw('count(*) as total'))
            ->groupBy('status')
            ->pluck('total', 'status');

        $bookingsThisWeekByStatus = Booking::where('created_at', '>=', $weekStart)
            ->select('status', DB::raw('count(*) as total'))
            ->groupBy('status')
            ->pluck('total', 'status');

        // Sum of completed transactions per calendar day, last 30 days
        // (inclusive of today), for a simple revenue/activity sparkline.
        $revenueByDay = Transaction::where('status', Transaction::STATUS_COMPLETED)
            ->where('created_at', '>=', now()->subDays(29)->startOfDay())
            ->select(DB::raw('DATE(created_at) as day'), DB::raw('SUM(amount) as total'))
            ->groupBy(DB::raw('DATE(created_at)'))
            ->orderBy('day')
            ->get()
            ->map(fn ($row) => ['date' => $row->day, 'total' => (string) $row->total]);

        return response()->json([
            'users_active' => $usersActive,
            'drivers' => [
                'total' => $driversTotal,
                'pending_verification' => $driversPending,
                'approved' => $driversApproved,
            ],
            'trips_by_status' => $tripsByStatus,
            'bookings_today_by_status' => $bookingsTodayByStatus,
            'bookings_this_week_by_status' => $bookingsThisWeekByStatus,
            'completed_transactions_last_30_days' => $revenueByDay,
            'sos_alerts_open' => SosAlert::whereIn('status', [SosAlert::STATUS_OPEN, SosAlert::STATUS_IN_PROGRESS])->count(),
            'disputes_open' => Dispute::whereIn('status', [Dispute::STATUS_OPEN, Dispute::STATUS_INVESTIGATING])->count(),
        ]);
    }

    /**
     * Live map data for the Admin Dashboard: active trips (open, full, in_progress)
     * with origin/destination/current GPS coordinates, driver & vehicle summary,
     * plus open SOS alerts with coordinates.
     */
    public function mapTrips()
    {
        $trips = Trip::query()
            ->withLatLng()
            ->whereIn('status', [Trip::STATUS_OPEN, Trip::STATUS_FULL, Trip::STATUS_IN_PROGRESS])
            ->with(['driverProfile.user', 'vehicle'])
            ->orderByDesc('updated_at')
            ->limit(150)
            ->get()
            ->map(function (Trip $t) {
                $driverUser = $t->driverProfile?->user;
                $vehicle = $t->vehicle;
                return [
                    'id' => $t->id,
                    'status' => $t->status,
                    'origin_name' => $t->origin_name,
                    'destination_name' => $t->destination_name,
                    'origin_lat' => (float) $t->origin_lat,
                    'origin_lng' => (float) $t->origin_lng,
                    'destination_lat' => (float) $t->destination_lat,
                    'destination_lng' => (float) $t->destination_lng,
                    'current_lat' => $t->current_lat !== null ? (float) $t->current_lat : (float) $t->origin_lat,
                    'current_lng' => $t->current_lng !== null ? (float) $t->current_lng : (float) $t->origin_lng,
                    'current_heading' => $t->current_heading !== null ? (float) $t->current_heading : null,
                    'location_updated_at' => $t->location_updated_at?->toIso8601String(),
                    'scheduled_at' => $t->scheduled_at?->toIso8601String(),
                    'seats_available' => (int) $t->seats_available,
                    'price_per_seat' => (string) $t->price_per_seat,
                    'waypoints' => $t->waypoints ?? [],
                    'driver' => $driverUser ? [
                        'id' => $driverUser->id,
                        'full_name' => $driverUser->full_name,
                        'phone_number' => $driverUser->phone_number,
                    ] : null,
                    'vehicle' => $vehicle ? [
                        'make' => $vehicle->make,
                        'model' => $vehicle->model,
                        'plate_number' => $vehicle->plate_number,
                    ] : null,
                ];
            });

        $sosAlerts = SosAlert::query()
            ->addSelect([
                'sos_alerts.*',
                DB::raw('ST_Y(location_geom::geometry) as lat'),
                DB::raw('ST_X(location_geom::geometry) as lng'),
            ])
            ->whereIn('status', [SosAlert::STATUS_OPEN, SosAlert::STATUS_IN_PROGRESS])
            ->with('user')
            ->orderByDesc('triggered_at')
            ->get()
            ->map(fn (SosAlert $a) => [
                'id' => $a->id,
                'status' => $a->status,
                'lat' => (float) $a->lat,
                'lng' => (float) $a->lng,
                'triggered_at' => $a->triggered_at?->toIso8601String(),
                'user_name' => $a->user?->full_name ?? 'Utilisateur',
                'user_phone' => $a->user?->phone_number ?? '',
            ]);

        return response()->json([
            'trips' => $trips,
            'sos_alerts' => $sosAlerts,
        ]);
    }
}
