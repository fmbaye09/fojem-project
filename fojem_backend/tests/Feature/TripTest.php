<?php

namespace Tests\Feature;

use App\Models\Driver;
use App\Models\User;
use App\Models\Vehicle;
use App\Models\Wallet;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class TripTest extends TestCase
{
    use RefreshDatabase;

    private function makeApprovedDriverWithVehicle(): array
    {
        $user = User::factory()->create(['is_driver' => true]);
        Wallet::create(['user_id' => $user->id]);
        $driver = Driver::create(['user_id' => $user->id, 'verification_status' => Driver::STATUS_APPROVED]);
        $vehicle = Vehicle::create([
            'driver_id' => $driver->id,
            'plate_number' => 'DK-0001-AA',
            'brand' => 'Toyota',
            'model' => 'Corolla',
            'color' => 'Blanc',
            'seat_count' => 4,
        ]);

        return [$user, $driver, $vehicle];
    }

    public function test_a_pending_driver_cannot_publish_a_trip(): void
    {
        $user = User::factory()->create(['is_driver' => true]);
        Driver::create(['user_id' => $user->id, 'verification_status' => Driver::STATUS_PENDING]);
        $vehicle = Vehicle::create([
            'driver_id' => $user->driver->id,
            'plate_number' => 'DK-0002-AA',
            'brand' => 'Toyota',
            'model' => 'Corolla',
            'color' => 'Noir',
            'seat_count' => 4,
        ]);

        Sanctum::actingAs($user);

        $response = $this->postJson('/api/trips', [
            'vehicle_id' => $vehicle->id,
            'origin_lat' => 14.6928,
            'origin_lng' => -17.4467,
            'destination_lat' => 14.7167,
            'destination_lng' => -17.4677,
            'departure_type' => 'now',
            'price_per_seat' => 2000,
            'seats_available' => 3,
        ]);

        $response->assertForbidden();
    }

    public function test_an_approved_driver_can_publish_a_trip_and_it_is_found_by_geo_search(): void
    {
        [$user, , $vehicle] = $this->makeApprovedDriverWithVehicle();
        Sanctum::actingAs($user);

        $publish = $this->postJson('/api/trips', [
            'vehicle_id' => $vehicle->id,
            'origin_lat' => 14.6928,
            'origin_lng' => -17.4467,
            'destination_lat' => 14.7167,
            'destination_lng' => -17.4677,
            'departure_type' => 'now',
            'price_per_seat' => 2000,
            'seats_available' => 3,
        ]);

        $publish->assertCreated();

        $search = $this->getJson('/api/trips/search?'.http_build_query([
            'origin_lat' => 14.693,
            'origin_lng' => -17.447,
            'destination_lat' => 14.717,
            'destination_lng' => -17.468,
            'radius_m' => 5000,
        ]));

        $search->assertOk();
        $this->assertCount(1, $search->json('trips'));
    }

    public function test_trips_mine_and_show_expose_origin_and_destination_coordinates(): void
    {
        [$user, , $vehicle] = $this->makeApprovedDriverWithVehicle();
        Sanctum::actingAs($user);

        $publish = $this->postJson('/api/trips', [
            'vehicle_id' => $vehicle->id,
            'origin_lat' => 14.6928,
            'origin_lng' => -17.4467,
            'destination_lat' => 14.7167,
            'destination_lng' => -17.4677,
            'departure_type' => 'now',
            'price_per_seat' => 2000,
            'seats_available' => 3,
        ]);
        $publish->assertCreated();
        $tripId = $publish->json('trip.id');

        $mine = $this->getJson('/api/trips/mine');
        $mine->assertOk();
        $mineTrip = collect($mine->json('data'))->firstWhere('id', $tripId);
        $this->assertEqualsWithDelta(14.6928, (float) $mineTrip['origin_lat'], 0.001);
        $this->assertEqualsWithDelta(-17.4467, (float) $mineTrip['origin_lng'], 0.001);
        $this->assertEqualsWithDelta(14.7167, (float) $mineTrip['destination_lat'], 0.001);
        $this->assertEqualsWithDelta(-17.4677, (float) $mineTrip['destination_lng'], 0.001);

        $show = $this->getJson("/api/trips/{$tripId}");
        $show->assertOk();
        $this->assertEqualsWithDelta(14.6928, (float) $show->json('trip.origin_lat'), 0.001);
        $this->assertEqualsWithDelta(-17.4467, (float) $show->json('trip.origin_lng'), 0.001);
    }

    public function test_geo_search_does_not_return_far_away_trips(): void
    {
        [$user, , $vehicle] = $this->makeApprovedDriverWithVehicle();
        Sanctum::actingAs($user);

        $this->postJson('/api/trips', [
            'vehicle_id' => $vehicle->id,
            'origin_lat' => 14.6928,
            'origin_lng' => -17.4467,
            'destination_lat' => 14.7167,
            'destination_lng' => -17.4677,
            'departure_type' => 'now',
            'price_per_seat' => 2000,
            'seats_available' => 3,
        ])->assertCreated();

        // Saint-Louis, ~170km away from the Dakar trip above.
        $search = $this->getJson('/api/trips/search?'.http_build_query([
            'origin_lat' => 16.0179,
            'origin_lng' => -16.4896,
            'destination_lat' => 16.03,
            'destination_lng' => -16.5,
            'radius_m' => 5000,
        ]));

        $search->assertOk();
        $this->assertCount(0, $search->json('trips'));
    }

    public function test_publishing_a_trip_with_another_drivers_vehicle_is_rejected(): void
    {
        [, , $otherDriversVehicle] = $this->makeApprovedDriverWithVehicle();

        $user = User::factory()->create(['is_driver' => true]);
        Wallet::create(['user_id' => $user->id]);
        Driver::create(['user_id' => $user->id, 'verification_status' => Driver::STATUS_APPROVED]);
        Sanctum::actingAs($user);

        $response = $this->postJson('/api/trips', [
            'vehicle_id' => $otherDriversVehicle->id,
            'origin_lat' => 14.6928,
            'origin_lng' => -17.4467,
            'destination_lat' => 14.7167,
            'destination_lng' => -17.4677,
            'departure_type' => 'now',
            'price_per_seat' => 2000,
            'seats_available' => 3,
        ]);

        $response->assertNotFound();
    }
}
