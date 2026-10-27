<?php

namespace Tests\Feature;

use App\Models\Driver;
use App\Models\User;
use App\Models\Vehicle;
use App\Models\Wallet;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Live progress of a trip in progress: reached stops, next stop ETA, and an
 * honest fallback to the schedule when the GPS fix is stale.
 */
class TripProgressTest extends TestCase
{
    use RefreshDatabase;

    private User $driverUser;

    private function startTrip(): array
    {
        $this->driverUser = User::factory()->create(['is_driver' => true]);
        Wallet::create(['user_id' => $this->driverUser->id]);
        $driver = Driver::create(['user_id' => $this->driverUser->id, 'verification_status' => Driver::STATUS_APPROVED]);
        $vehicle = Vehicle::create([
            'driver_id' => $driver->id, 'plate_number' => 'DK-4242-PR', 'brand' => 'Toyota',
            'model' => 'Avanza', 'color' => 'Gris', 'seat_count' => 7,
        ]);
        Sanctum::actingAs($this->driverUser);

        $departure = now()->addMinutes(10);
        $trip = $this->postJson('/api/trips', [
            'vehicle_id' => $vehicle->id,
            'departure_type' => 'scheduled',
            'scheduled_at' => $departure->toIso8601String(),
            'price_per_seat' => 3000,
            'seats_available' => 3,
            'stops' => [
                ['name' => 'Dakar', 'lat' => 14.6800, 'lng' => -17.4380, 'scheduled_at' => $departure->toIso8601String()],
                ['name' => 'Rufisque', 'lat' => 14.7160, 'lng' => -17.2730, 'scheduled_at' => $departure->copy()->addMinutes(35)->toIso8601String()],
                ['name' => 'Thiès', 'lat' => 14.7910, 'lng' => -16.9260, 'scheduled_at' => $departure->copy()->addMinutes(100)->toIso8601String()],
            ],
        ])->assertCreated()->json('trip');

        $this->postJson("/api/trips/{$trip['id']}/start")->assertOk();

        return $trip;
    }

    public function test_a_completed_trip_has_no_eta(): void
    {
        $trip = $this->startTrip();
        $this->postJson("/api/trips/{$trip['id']}/complete")->assertOk();

        $live = $this->getJson("/api/trips/{$trip['id']}")->json('trip.live');
        $this->assertSame([], $live['etas']);
        $this->assertNull($live['next_stop_id']);
    }

    public function test_live_eta_targets_the_next_stop(): void
    {
        $trip = $this->startTrip();
        [, $rufisque, $thies] = $trip['stops'];

        // Halfway between Dakar and Rufisque.
        $live = $this->postJson("/api/trips/{$trip['id']}/location", ['lat' => 14.698, 'lng' => -17.355])
            ->assertOk()->json('live');

        $this->assertTrue($live['location_fresh']);
        $this->assertSame('live', $live['eta_source']);
        $this->assertSame($rufisque['id'], $live['next_stop_id']);
        $this->assertSame([$rufisque['id'], $thies['id']], array_column($live['etas'], 'stop_id'));
        $this->assertTrue($live['etas'][1]['eta'] > $live['etas'][0]['eta']);
    }

    public function test_reaching_a_stop_moves_on_to_the_next(): void
    {
        $trip = $this->startTrip();
        [, , $thies] = $trip['stops'];

        // At the Rufisque stop (≈100 m away).
        $live = $this->postJson("/api/trips/{$trip['id']}/location", ['lat' => 14.7165, 'lng' => -17.2722])
            ->json('live');

        $this->assertSame(1, $live['last_passed_stop_position']);
        $this->assertSame($thies['id'], $live['next_stop_id']);
    }

    public function test_a_stale_position_falls_back_to_the_schedule(): void
    {
        $trip = $this->startTrip();
        [, $rufisque] = $trip['stops'];

        $this->travel(10)->minutes();
        $live = $this->getJson("/api/trips/{$trip['id']}")->json('trip.live');

        $this->assertFalse($live['location_fresh']);
        $this->assertSame('schedule', $live['eta_source']);
        $this->assertSame($rufisque['id'], $live['next_stop_id']);
        $this->assertSame(0, $live['delay_minutes']);
    }
}
