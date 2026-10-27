<?php

namespace App\Services;

use App\Models\Booking;
use App\Models\RideRequest;
use App\Models\Trip;
use Illuminate\Support\Facades\Log;

class TripLifecycleService
{
    /**
     * Executes complete synchronization of trips, bookings, and ride requests lifecycle.
     * Can be invoked on API reads, scheduled cron, or artisan commands.
     */
    public static function sync(): array
    {
        $updatedBookings = 0;
        $updatedTrips = 0;
        $updatedRequests = 0;

        try {
            // 1. Expire pending bookings whose trip departure time has passed or whose trip is not open
            $stalePendingBookings = Booking::where('status', Booking::STATUS_PENDING_DRIVER)
                ->whereHas('trip', function ($q) {
                    $q->where('scheduled_at', '<=', now())
                      ->orWhereIn('status', [Trip::STATUS_CANCELLED, Trip::STATUS_COMPLETED]);
                })
                ->with(['trip', 'passenger'])
                ->get();

            $notificationService = app(NotificationService::class);

            foreach ($stalePendingBookings as $booking) {
                $booking->update([
                    'status' => Booking::STATUS_REJECTED,
                ]);
                $updatedBookings++;

                // Notify passenger if possible
                if ($booking->passenger) {
                    try {
                        $tripLabel = ($booking->trip?->origin_name ?? 'Départ') . ' → ' . ($booking->trip?->destination_name ?? 'Arrivée');
                        $notificationService->bookingRejected($booking->passenger, [
                            'booking_id' => $booking->id,
                            'trip_id' => $booking->trip_id,
                            'trip_label' => $tripLabel,
                            'reason' => 'Demande expirée : départ dépassé sans validation du chauffeur.',
                        ]);
                    } catch (\Throwable $e) {
                        Log::warning("Failed to send booking expiry notification: {$e->getMessage()}");
                    }
                }
            }

            // 2. Auto-close trips that were scheduled > 24 hours ago and never started
            $staleTrips = Trip::whereIn('status', [Trip::STATUS_OPEN, Trip::STATUS_FULL])
                ->where('scheduled_at', '<=', now()->subHours(24))
                ->update(['status' => Trip::STATUS_CANCELLED]);

            $updatedTrips += $staleTrips;

            // 3. Auto-expire old ride requests
            $staleRequests = RideRequest::where('status', RideRequest::STATUS_SEARCHING)
                ->where('requested_at', '<=', now()->subHours(6))
                ->update(['status' => RideRequest::STATUS_EXPIRED]);

            $updatedRequests += $staleRequests;

        } catch (\Throwable $e) {
            Log::error("TripLifecycleService sync error: {$e->getMessage()}");
        }

        return [
            'expired_bookings' => $updatedBookings,
            'cancelled_stale_trips' => $updatedTrips,
            'expired_ride_requests' => $updatedRequests,
            'synced_at' => now()->toIso8601String(),
        ];
    }
}
