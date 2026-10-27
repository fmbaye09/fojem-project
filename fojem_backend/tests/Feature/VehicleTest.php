<?php

namespace Tests\Feature;

use App\Models\Driver;
use App\Models\User;
use App\Models\Vehicle;
use App\Models\Wallet;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use LogicException;
use Tests\TestCase;

class VehicleTest extends TestCase
{
    use RefreshDatabase;

    private function makeDriver(): array
    {
        $user = User::factory()->create(['is_driver' => true]);
        Wallet::create(['user_id' => $user->id]);
        $driver = Driver::create(['user_id' => $user->id, 'verification_status' => Driver::STATUS_PENDING]);

        return [$user, $driver];
    }

    public function test_a_driver_can_register_a_vehicle(): void
    {
        [$user] = $this->makeDriver();
        Sanctum::actingAs($user);

        $response = $this->postJson('/api/vehicles', [
            'plate_number' => 'DK-1234-AA',
            'brand' => 'Toyota',
            'model' => 'Corolla',
            'color' => 'Blanc',
            'seat_count' => 4,
        ]);

        $response->assertCreated();
        $this->assertEquals('DK-1234-AA', $response->json('vehicle.plate_number'));
        $this->assertDatabaseCount('vehicles', 1);
    }

    public function test_a_driver_can_register_several_vehicles(): void
    {
        [$user, $driver] = $this->makeDriver();
        Sanctum::actingAs($user);

        $this->postJson('/api/vehicles', [
            'plate_number' => 'DK-1234-AA',
            'brand' => 'Toyota',
            'model' => 'Corolla',
            'color' => 'Blanc',
            'seat_count' => 4,
        ])->assertCreated();

        $second = $this->postJson('/api/vehicles', [
            'plate_number' => 'DK-5678-AA',
            'brand' => 'Toyota',
            'model' => 'Yaris',
            'color' => 'Noir',
            'seat_count' => 4,
        ]);

        $second->assertCreated();
        $this->assertDatabaseCount('vehicles', 2);
        $this->assertEquals(2, Vehicle::where('driver_id', $driver->id)->count());
    }

    public function test_a_driver_cannot_register_two_vehicles_with_the_same_plate_number(): void
    {
        [$user] = $this->makeDriver();
        Sanctum::actingAs($user);

        $this->postJson('/api/vehicles', [
            'plate_number' => 'DK-1234-AA',
            'brand' => 'Toyota',
            'model' => 'Corolla',
            'color' => 'Blanc',
            'seat_count' => 4,
        ])->assertCreated();

        $duplicate = $this->postJson('/api/vehicles', [
            'plate_number' => 'DK-1234-AA',
            'brand' => 'Renault',
            'model' => 'Logan',
            'color' => 'Gris',
            'seat_count' => 4,
        ]);

        $duplicate->assertUnprocessable();
        $this->assertDatabaseCount('vehicles', 1);
    }

    public function test_a_driver_can_list_their_own_vehicles(): void
    {
        [$user, $driver] = $this->makeDriver();
        Vehicle::create([
            'driver_id' => $driver->id,
            'plate_number' => 'DK-5555-AA',
            'brand' => 'Renault',
            'model' => 'Logan',
            'color' => 'Gris',
            'seat_count' => 4,
        ]);
        Vehicle::create([
            'driver_id' => $driver->id,
            'plate_number' => 'DK-6666-AA',
            'brand' => 'Toyota',
            'model' => 'Corolla',
            'color' => 'Blanc',
            'seat_count' => 4,
        ]);

        Sanctum::actingAs($user);

        $response = $this->getJson('/api/vehicles');

        $response->assertOk();
        $this->assertCount(2, $response->json('vehicles'));
    }

    public function test_listing_vehicles_returns_an_empty_array_when_none_registered(): void
    {
        [$user] = $this->makeDriver();
        Sanctum::actingAs($user);

        $response = $this->getJson('/api/vehicles');

        $response->assertOk();
        $this->assertCount(0, $response->json('vehicles'));
    }

    public function test_a_non_driver_cannot_register_a_vehicle(): void
    {
        $user = User::factory()->create(['is_driver' => false]);
        Sanctum::actingAs($user);

        $response = $this->postJson('/api/vehicles', [
            'plate_number' => 'DK-9999-AA',
            'brand' => 'Toyota',
            'model' => 'Corolla',
            'color' => 'Blanc',
            'seat_count' => 4,
        ]);

        $response->assertForbidden();
    }

    public function test_a_vehicle_cannot_be_modified_after_creation(): void
    {
        [, $driver] = $this->makeDriver();
        $vehicle = Vehicle::create([
            'driver_id' => $driver->id,
            'plate_number' => 'DK-7777-AA',
            'brand' => 'Renault',
            'model' => 'Logan',
            'color' => 'Gris',
            'seat_count' => 4,
        ]);

        $this->expectException(LogicException::class);

        $vehicle->update(['brand' => 'Toyota']);
    }

    public function test_a_vehicles_seat_count_cannot_be_modified_after_creation(): void
    {
        [, $driver] = $this->makeDriver();
        $vehicle = Vehicle::create([
            'driver_id' => $driver->id,
            'plate_number' => 'DK-8888-AA',
            'brand' => 'Renault',
            'model' => 'Logan',
            'color' => 'Gris',
            'seat_count' => 4,
        ]);

        $this->expectException(LogicException::class);

        $vehicle->update(['seat_count' => 7]);
    }

    public function test_a_vehicles_is_active_flag_can_still_be_toggled_after_creation(): void
    {
        [, $driver] = $this->makeDriver();
        $vehicle = Vehicle::create([
            'driver_id' => $driver->id,
            'plate_number' => 'DK-9090-AA',
            'brand' => 'Renault',
            'model' => 'Logan',
            'color' => 'Gris',
            'seat_count' => 4,
        ]);

        $vehicle->update(['is_active' => false]);

        $this->assertFalse($vehicle->fresh()->is_active);
    }
}
