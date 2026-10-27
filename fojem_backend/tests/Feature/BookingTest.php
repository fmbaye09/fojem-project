<?php

namespace Tests\Feature;

use App\Models\Driver;
use App\Models\Trip;
use App\Models\User;
use App\Models\Vehicle;
use App\Models\Wallet;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class BookingTest extends TestCase
{
    use RefreshDatabase;

    private function makeOpenTrip(int $seats = 3): array
    {
        $driverUser = User::factory()->create(['is_driver' => true]);
        Wallet::create(['user_id' => $driverUser->id]);
        $driver = Driver::create(['user_id' => $driverUser->id, 'verification_status' => Driver::STATUS_APPROVED]);
        $vehicle = Vehicle::create([
            'driver_id' => $driver->id,
            'plate_number' => 'DK-0099-AA',
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
            'seats_available' => $seats,
            'status' => Trip::STATUS_OPEN,
        ]);
        $trip->setOriginPoint(14.6928, -17.4467);
        $trip->setDestinationPoint(14.7167, -17.4677);
        $trip->save();

        return [$driverUser, $trip];
    }

    public function test_a_passenger_can_book_a_seat_and_the_driver_can_accept_it(): void
    {
        [$driverUser, $trip] = $this->makeOpenTrip(3);

        $passenger = User::factory()->create();

        Sanctum::actingAs($passenger);

        $bookingResponse = $this->postJson('/api/bookings', [
            'trip_id' => $trip->id,
            'seat_count' => 2,
            'pickup_lat' => 14.693,
            'pickup_lng' => -17.447,
        ]);

        $bookingResponse->assertCreated();
        $bookingId = $bookingResponse->json('booking.id');

        // seats_available untouched until the driver accepts
        $trip->refresh();
        $this->assertEquals(3, $trip->seats_available);

        Sanctum::actingAs($driverUser);
        $accept = $this->postJson("/api/bookings/{$bookingId}/accept");

        $accept->assertOk();
        $this->assertEquals('confirmed', $accept->json('booking.status'));

        $trip->refresh();
        $this->assertEquals(1, $trip->seats_available);
    }

    public function test_booking_is_rejected_when_not_enough_seats(): void
    {
        [, $trip] = $this->makeOpenTrip(1);

        $passenger = User::factory()->create();
        Sanctum::actingAs($passenger);

        $response = $this->postJson('/api/bookings', [
            'trip_id' => $trip->id,
            'seat_count' => 2,
            'pickup_lat' => 14.693,
            'pickup_lng' => -17.447,
        ]);

        $response->assertUnprocessable();
    }
}
