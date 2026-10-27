<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Models\Booking;
use App\Models\Trip;
use App\Services\AuditLogger;
use App\Services\TripCancellationService;
use Illuminate\Http\Request;

/**
 * Trip supervision for the admin dashboard: filterable list, detail with
 * passengers, and cancellation on behalf of the platform.
 *
 * Responses are built field by field rather than serialising models, so
 * the dashboard only receives what it displays.
 */
class TripController extends Controller
{
    public function index(Request $request)
    {
        $request->validate([
            'status' => ['sometimes', 'nullable', 'in:open,full,in_progress,completed,cancelled'],
            'search' => ['sometimes', 'nullable', 'string', 'max:100'],
            'date_from' => ['sometimes', 'nullable', 'date'],
            'date_to' => ['sometimes', 'nullable', 'date'],
            'per_page' => ['sometimes', 'integer', 'min:1', 'max:100'],
        ]);

        // `now` trips have no scheduled_at: their creation time stands in.
        $departureAt = 'COALESCE(trips.scheduled_at, trips.created_at)';

        $query = Trip::query()
            ->with(['driverProfile.user', 'vehicle'])
            ->withCount($this->bookingCounts())
            ->orderByRaw("$departureAt DESC");

        if ($status = $request->string('status')->value()) {
            $query->where('status', $status);
        }

        if ($search = trim($request->string('search')->value())) {
            $like = '%' . str_replace(['%', '_'], ['\%', '\_'], $search) . '%';
            $query->where(function ($q) use ($like) {
                $q->where('origin_name', 'ilike', $like)
                    ->orWhere('destination_name', 'ilike', $like)
                    ->orWhereHas('driverProfile.user', fn ($u) => $u
                        ->where('full_name', 'ilike', $like)
                        ->orWhere('phone_number', 'ilike', $like));
            });
        }

        if ($from = $request->input('date_from')) {
            $query->whereRaw("$departureAt >= ?", [$from]);
        }
        if ($to = $request->input('date_to')) {
            // Inclusive end date: everything before the next midnight.
            $query->whereRaw("$departureAt < (?::date + interval '1 day')", [$to]);
        }

        $page = $query->paginate($request->integer('per_page', 20));
        $page->getCollection()->transform(fn (Trip $trip) => $this->summary($trip));

        return response()->json($page);
    }

    public function show(Trip $trip)
    {
        $trip = Trip::withLatLng()
            ->with(['driverProfile.user', 'vehicle', 'bookings' => fn ($q) => $q->with('passenger')->latest()])
            ->withCount($this->bookingCounts())
            ->findOrFail($trip->id);

        return response()->json([
            'trip' => $this->summary($trip) + [
                'origin_lat' => $trip->origin_lat,
                'origin_lng' => $trip->origin_lng,
                'destination_lat' => $trip->destination_lat,
                'destination_lng' => $trip->destination_lng,
                'waypoints' => $trip->waypoints ?? [],
                'women_only' => (bool) $trip->women_only,
                'toll_fees' => $trip->toll_fees !== null ? (string) $trip->toll_fees : null,
                'location_updated_at' => $trip->location_updated_at?->toIso8601String(),
                'bookings' => $trip->bookings->map(fn (Booking $b) => [
                    'id' => $b->id,
                    'status' => $b->status,
                    'seat_count' => (int) $b->seat_count,
                    'seat_numbers' => $b->seat_numbers ?? [],
                    'price_charged' => (string) $b->price_charged,
                    'has_heavy_luggage' => (bool) $b->has_heavy_luggage,
                    'created_at' => $b->created_at?->toIso8601String(),
                    'started_at' => $b->started_at?->toIso8601String(),
                    'passenger' => $b->passenger ? [
                        'id' => $b->passenger->id,
                        'full_name' => $b->passenger->full_name,
                        'phone_number' => $b->passenger->phone_number,
                    ] : null,
                ])->values(),
            ],
        ]);
    }

    public function cancel(Request $request, Trip $trip, TripCancellationService $cancellation)
    {
        $request->validate([
            'reason' => ['required', 'string', 'min:3', 'max:500'],
        ]);

        if (in_array($trip->status, [Trip::STATUS_COMPLETED, Trip::STATUS_CANCELLED], true)) {
            return response()->json(['message' => 'Ce trajet est déjà terminé ou annulé.'], 422);
        }

        $oldStatus = $trip->status;
        $cancelled = $cancellation->cancel($trip, 'admin');

        AuditLogger::logFromRequest(
            $request,
            'trip.cancelled',
            'trip',
            $trip->id,
            ['status' => $oldStatus],
            [
                'status' => Trip::STATUS_CANCELLED,
                'reason' => $request->string('reason')->value(),
                'cancelled_bookings' => $cancelled->count(),
            ],
        );

        return $this->show($trip->fresh());
    }

    /** Seats actually taken vs requests still waiting for the driver. */
    private function bookingCounts(): array
    {
        return [
            'bookings as confirmed_bookings_count' => fn ($q) => $q->whereIn('status', [
                Booking::STATUS_CONFIRMED,
                Booking::STATUS_COMPLETED,
            ]),
            'bookings as pending_bookings_count' => fn ($q) => $q->where('status', Booking::STATUS_PENDING_DRIVER),
        ];
    }

    private function summary(Trip $trip): array
    {
        $driverUser = $trip->driverProfile?->user;
        $vehicle = $trip->vehicle;

        return [
            'id' => $trip->id,
            'status' => $trip->status,
            'closed_by' => $trip->closed_by,
            'departure_type' => $trip->departure_type,
            'scheduled_at' => $trip->scheduled_at?->toIso8601String(),
            'created_at' => $trip->created_at?->toIso8601String(),
            'origin_name' => $trip->origin_name,
            'destination_name' => $trip->destination_name,
            'price_per_seat' => (string) $trip->price_per_seat,
            'seats_available' => (int) $trip->seats_available,
            'confirmed_bookings_count' => (int) ($trip->confirmed_bookings_count ?? 0),
            'pending_bookings_count' => (int) ($trip->pending_bookings_count ?? 0),
            'driver' => $driverUser ? [
                'id' => $driverUser->id,
                'full_name' => $driverUser->full_name,
                'phone_number' => $driverUser->phone_number,
            ] : null,
            'vehicle' => $vehicle ? [
                'brand' => $vehicle->brand,
                'model' => $vehicle->model,
                'plate_number' => $vehicle->plate_number,
                'seat_count' => (int) $vehicle->seat_count,
            ] : null,
        ];
    }
}
