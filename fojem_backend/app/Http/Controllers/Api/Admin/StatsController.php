<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Models\Booking;
use App\Models\Driver;
use App\Models\Review;
use App\Models\Transaction;
use App\Models\Trip;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Simple time-series/ratio aggregates for dashboard charts. Every number
 * here is a direct SQL aggregate over the requested [from, to] window -
 * no sampling, no reporting engine. Keep it that way: if a report needs
 * more than group-by-day + a ratio, it belongs in a proper analytics
 * pipeline, not bolted onto this controller.
 */
class StatsController extends Controller
{
    /** Trips, bookings and completed-transaction revenue, grouped by day. */
    public function timeseries(Request $request)
    {
        [$from, $to] = $this->resolveRange($request);

        $trips = Trip::whereBetween('created_at', [$from, $to])
            ->select(DB::raw('DATE(created_at) as day'), DB::raw('count(*) as total'))
            ->groupBy(DB::raw('DATE(created_at)'))
            ->orderBy('day')
            ->pluck('total', 'day');

        $bookings = Booking::whereBetween('created_at', [$from, $to])
            ->select(DB::raw('DATE(created_at) as day'), DB::raw('count(*) as total'))
            ->groupBy(DB::raw('DATE(created_at)'))
            ->orderBy('day')
            ->pluck('total', 'day');

        $revenue = Transaction::where('status', Transaction::STATUS_COMPLETED)
            ->whereBetween('created_at', [$from, $to])
            ->select(DB::raw('DATE(created_at) as day'), DB::raw('SUM(amount) as total'))
            ->groupBy(DB::raw('DATE(created_at)'))
            ->orderBy('day')
            ->pluck('total', 'day');

        return response()->json([
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'trips_per_day' => $trips,
            'bookings_per_day' => $bookings,
            'revenue_per_day' => $revenue,
        ]);
    }

    /**
     * Acceptance rate = bookings the driver confirmed / bookings created in
     * the window that reached a driver decision (confirmed, completed,
     * rejected, or a driver cancellation - i.e. excludes bookings still
     * pending_driver or cancelled by the passenger before any decision).
     */
    public function bookingAcceptanceRate(Request $request)
    {
        [$from, $to] = $this->resolveRange($request);

        $decided = ['confirmed', 'completed', 'rejected', 'cancelled_driver'];
        $accepted = ['confirmed', 'completed'];

        $decidedCount = Booking::whereBetween('created_at', [$from, $to])
            ->whereIn('status', $decided)
            ->count();

        $acceptedCount = Booking::whereBetween('created_at', [$from, $to])
            ->whereIn('status', $accepted)
            ->count();

        return response()->json([
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'decided_bookings' => $decidedCount,
            'accepted_bookings' => $acceptedCount,
            'acceptance_rate' => $decidedCount > 0 ? round($acceptedCount / $decidedCount, 4) : null,
        ]);
    }

    /**
     * Platform-wide average rating: mean of drivers.average_rating across
     * drivers who have received at least one review. drivers.average_rating
     * is itself the canonical per-driver mean (kept up to date by
     * ReviewController::recalculateDriverRating()), so this reuses it
     * instead of re-deriving ratings from the reviews table.
     */
    public function averageRating()
    {
        $reviewedDriverCount = Review::query()
            ->join('drivers', 'drivers.user_id', '=', 'reviews.reviewee_id')
            ->distinct('drivers.id')
            ->count('drivers.id');

        $average = Driver::where('average_rating', '>', 0)->avg('average_rating');

        return response()->json([
            'platform_average_rating' => $average !== null ? round((float) $average, 2) : null,
            'rated_drivers_count' => $reviewedDriverCount,
        ]);
    }

    /**
     * Completed-transaction volume grouped by payment_method and by type,
     * within the window. Two independent breakdowns of the same base
     * query, not a cross-tab - simpler to read on a dashboard than a
     * matrix, and the dashboard asked for "by method" and "by type"
     * separately.
     */
    public function transactionsBreakdown(Request $request)
    {
        [$from, $to] = $this->resolveRange($request);

        $base = Transaction::where('status', Transaction::STATUS_COMPLETED)
            ->whereBetween('created_at', [$from, $to]);

        $byMethod = (clone $base)
            ->select('payment_method', DB::raw('count(*) as count'), DB::raw('SUM(amount) as total_amount'))
            ->groupBy('payment_method')
            ->get()
            ->keyBy('payment_method');

        $byType = (clone $base)
            ->select('type', DB::raw('count(*) as count'), DB::raw('SUM(amount) as total_amount'))
            ->groupBy('type')
            ->get()
            ->keyBy('type');

        return response()->json([
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'by_payment_method' => $byMethod,
            'by_type' => $byType,
        ]);
    }

    /**
     * New accounts per day, split passengers vs drivers (is_driver at the
     * moment of the query - a passenger who later becomes a driver shifts
     * bucket for future queries, it doesn't rewrite history, since we only
     * have users.created_at to group by, not a role-change log).
     */
    public function newAccountsTimeseries(Request $request)
    {
        [$from, $to] = $this->resolveRange($request);

        $rows = User::whereBetween('created_at', [$from, $to])
            ->select(
                DB::raw('DATE(created_at) as day'),
                'is_driver',
                DB::raw('count(*) as total')
            )
            ->groupBy(DB::raw('DATE(created_at)'), 'is_driver')
            ->orderBy('day')
            ->get();

        $passengers = $rows->where('is_driver', false)->pluck('total', 'day');
        $drivers = $rows->where('is_driver', true)->pluck('total', 'day');

        return response()->json([
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'new_passengers_per_day' => $passengers,
            'new_drivers_per_day' => $drivers,
        ]);
    }

    /**
     * @return array{0: Carbon, 1: Carbon}
     */
    private function resolveRange(Request $request): array
    {
        $from = $request->filled('from') ? Carbon::parse($request->string('from')->value())->startOfDay() : now()->subDays(29)->startOfDay();
        $to = $request->filled('to') ? Carbon::parse($request->string('to')->value())->endOfDay() : now()->endOfDay();

        return [$from, $to];
    }
}
