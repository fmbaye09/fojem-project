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

class BookingVisibilityTest extends TestCase
{
    use RefreshDatabase;

    private function makeOpenTrip(int $seats = 3): array
    {
        $driverUser = User::factory()->create(['is_driver' => true]);
        Wallet::create(['user_id' => $driverUser->id]);
        $driver = Driver::create(['user_id' => $driverUser->id, 'verification_status' => Driver::STATUS_APPROVED]);
        $vehicle = Vehicle::create([
            'driver_id' => $driver->id,
            'plate_number' => 'DK-0077-AA',
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

        return [$driverUser, $driver, $trip];
    }

    private function bookSeat(Trip $trip, User $passenger): string
    {
        Sanctum::actingAs($passenger);

        $response = $this->postJson('/api/bookings', [
            'trip_id' => $trip->id,
            'seat_count' => 1,
            'pickup_lat' => 14.693,
            'pickup_lng' => -17.447,
        ]);

        return $response->json('booking.id');
    }

    public function test_the_trips_driver_can_list_bookings_on_that_trip(): void
    {
        [$driverUser, , $trip] = $this->makeOpenTrip();
        $passenger = User::factory()->create();
        $this->bookSeat($trip, $passenger);

        Sanctum::actingAs($driverUser);
        $response = $this->getJson("/api/trips/{$trip->id}/bookings");

        $response->assertOk();
        $this->assertCount(1, $response->json('data'));
    }

    public function test_a_stranger_cannot_list_bookings_on_someone_elses_trip(): void
    {
        [, , $trip] = $this->makeOpenTrip();
        $passenger = User::factory()->create();
        $this->bookSeat($trip, $passenger);

        $stranger = User::factory()->create(['is_driver' => true]);
        Wallet::create(['user_id' => $stranger->id]);
        Driver::create(['user_id' => $stranger->id, 'verification_status' => Driver::STATUS_APPROVED]);

        Sanctum::actingAs($stranger);
        $response = $this->getJson("/api/trips/{$trip->id}/bookings");

        $response->assertForbidden();
    }

    public function test_a_driver_can_list_all_bookings_received_across_their_trips(): void
    {
        [$driverUser, , $trip] = $this->makeOpenTrip();
        $passenger = User::factory()->create();
        $this->bookSeat($trip, $passenger);

        Sanctum::actingAs($driverUser);
        $response = $this->getJson('/api/bookings/received');

        $response->assertOk();
        $this->assertCount(1, $response->json('data'));
    }

    public function test_bookings_show_is_visible_to_passenger_and_driver_but_not_a_stranger(): void
    {
        [$driverUser, , $trip] = $this->makeOpenTrip();
        $passenger = User::factory()->create();
        $bookingId = $this->bookSeat($trip, $passenger);

        Sanctum::actingAs($passenger);
        $this->getJson("/api/bookings/{$bookingId}")->assertOk();

        Sanctum::actingAs($driverUser);
        $this->getJson("/api/bookings/{$bookingId}")->assertOk();

        $stranger = User::factory()->create();
        Sanctum::actingAs($stranger);
        $this->getJson("/api/bookings/{$bookingId}")->assertForbidden();
    }
}
