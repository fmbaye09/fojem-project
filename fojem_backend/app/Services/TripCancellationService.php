<?php

namespace App\Services;

use App\Models\Booking;
use App\Models\Trip;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Cancels a whole trip, whoever asks for it (the driver from the app, an
 * admin from the dashboard). Pending and confirmed bookings die with the
 * trip and each passenger is notified, so nobody keeps a "confirmed" seat
 * on a trip that will never leave.
 */
class TripCancellationService
{
    public function __construct(private readonly NotificationService $notifications)
    {
    }

    /**
     * @param  'driver'|'admin'  $closedBy
     * @return Collection<int, Booking> the bookings that were cancelled
     */
    public function cancel(Trip $trip, string $closedBy): Collection
    {
        $affected = DB::transaction(function () use ($trip, $closedBy) {
            $trip->update(['status' => Trip::STATUS_CANCELLED, 'closed_by' => $closedBy]);

            $bookings = Booking::where('trip_id', $trip->id)
                ->whereIn('status', [Booking::STATUS_PENDING_DRIVER, Booking::STATUS_CONFIRMED])
                ->with('passenger')
                ->get();

            Booking::whereIn('id', $bookings->pluck('id'))
                ->update(['status' => Booking::STATUS_CANCELLED_DRIVER]);

            return $bookings;
        });

        // Push notifications are HTTP calls: sent after the commit.
        $tripLabel = ($trip->origin_name ?? 'Départ') . ' → ' . ($trip->destination_name ?? 'Arrivée');
        foreach ($affected as $booking) {
            if ($booking->passenger) {
                $this->notifications->tripCancelled($booking->passenger, [
                    'booking_id' => $booking->id,
                    'trip_id'    => $trip->id,
                    'trip_label' => $tripLabel,
                ]);
            }
        }

        return $affected;
    }
}
