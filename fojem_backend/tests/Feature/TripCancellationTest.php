<?php

namespace Tests\Feature;

use App\Models\Booking;
use App\Models\Driver;
use App\Models\Notification;
use App\Models\Trip;
use App\Models\User;
use App\Models\Vehicle;
use App\Models\Wallet;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class TripCancellationTest extends TestCase
{
    use RefreshDatabase;

    private function makeOpenTrip(): array
    {
        $driverUser = User::factory()->create(['is_driver' => true]);
        Wallet::create(['user_id' => $driverUser->id]);
        $driver = Driver::create(['user_id' => $driverUser->id, 'verification_status' => Driver::STATUS_APPROVED]);
        $vehicle = Vehicle::create([
            'driver_id' => $driver->id,
            'plate_number' => 'DK-0100-AA',
            'brand' => 'Renault',
            'model' => 'Logan',
            'color' => 'Gris',
            'seat_count' => 4,
        ]);

        $trip = new Trip([
            'driver_id' => $driver->id,
            'vehicle_id' => $vehicle->id,
            'departure_type' => 'now',
            'price_per_seat' => 2000,
            'seats_available' => 3,
            'status' => Trip::STATUS_OPEN,
        ]);
        $trip->setOriginPoint(14.6928, -17.4467);
        $trip->setDestinationPoint(14.7167, -17.4677);
        $trip->save();

        return [$driverUser, $trip];
    }

    private function book(Trip $trip, User $passenger): string
    {
        Sanctum::actingAs($passenger);

        return $this->postJson('/api/bookings', [
            'trip_id' => $trip->id,
            'seat_count' => 1,
            'pickup_lat' => 14.693,
            'pickup_lng' => -17.447,
        ])->assertCreated()->json('booking.id');
    }

    public function test_cancelling_a_trip_cancels_its_bookings_and_notifies_passengers(): void
    {
        [$driverUser, $trip] = $this->makeOpenTrip();

        $pendingPassenger = User::factory()->create();
        $confirmedPassenger = User::factory()->create();
        $pendingId = $this->book($trip, $pendingPassenger);
        $confirmedId = $this->book($trip, $confirmedPassenger);

        Sanctum::actingAs($driverUser);
        $this->postJson("/api/bookings/{$confirmedId}/accept")->assertOk();

        $this->postJson("/api/trips/{$trip->id}/cancel")->assertOk();

        $this->assertEquals(Booking::STATUS_CANCELLED_DRIVER, Booking::find($pendingId)->status);
        $this->assertEquals(Booking::STATUS_CANCELLED_DRIVER, Booking::find($confirmedId)->status);

        foreach ([$pendingPassenger, $confirmedPassenger] as $passenger) {
            $this->assertTrue(
                Notification::where('user_id', $passenger->id)
                    ->where('type', Notification::TYPE_TRIP_CANCELLED)
                    ->exists()
            );
        }
    }
}
