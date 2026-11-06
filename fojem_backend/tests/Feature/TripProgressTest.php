<?php

namespace Tests\Feature;

use App\Models\Driver;
use App\Models\User;
use App\Models\Vehicle;
use App\Models\Wallet;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
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

    private function startTrip(bool $start = true): array
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

        if ($start) {
            $this->postJson("/api/trips/{$trip['id']}/start")->assertOk();
        }

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

    /** OSRM simulé : 15 min jusqu'à Rufisque, puis 45 min jusqu'à Thiès. */
    private function fakeRoad(): void
    {
        config(['services.osrm.url' => 'https://osrm.test']);
        Http::fake(['osrm.test/*' => Http::response([
            'code' => 'Ok',
            'routes' => [['legs' => [['duration' => 900], ['duration' => 2700]]]],
        ])]);
    }

    public function test_road_durations_drive_the_live_etas(): void
    {
        $this->fakeRoad();
        $trip = $this->startTrip();
        [, $rufisque, $thies] = $trip['stops'];

        $this->freezeSecond();
        $this->postJson("/api/trips/{$trip['id']}/location", ['lat' => 14.698, 'lng' => -17.355])->assertOk();

        Http::assertSent(fn ($request) => str_starts_with(
            $request->url(),
            'https://osrm.test/route/v1/driving/-17.355000,14.698000;-17.273000,14.716000;-16.926000,14.791000',
        ));
        $live = $this->getJson("/api/trips/{$trip['id']}")->json('trip.live');
        $this->assertSame('live', $live['eta_source']);
        $this->assertSame([$rufisque['id'], $thies['id']], array_column($live['etas'], 'stop_id'));
        $this->assertEquals(now()->addMinutes(15), CarbonImmutable::parse($live['etas'][0]['eta']));
        $this->assertEquals(now()->addMinutes(60), CarbonImmutable::parse($live['etas'][1]['eta']));
    }

    public function test_the_road_is_asked_at_most_once_a_minute_and_after_each_stop(): void
    {
        $this->fakeRoad();
        $trip = $this->startTrip();

        $this->postJson("/api/trips/{$trip['id']}/location", ['lat' => 14.698, 'lng' => -17.355])->assertOk();
        $this->postJson("/api/trips/{$trip['id']}/location", ['lat' => 14.700, 'lng' => -17.340])->assertOk();
        Http::assertSentCount(1);

        // Arrivé à Rufisque : on recalcule tout de suite vers Thiès.
        $this->postJson("/api/trips/{$trip['id']}/location", ['lat' => 14.7165, 'lng' => -17.2722])->assertOk();
        Http::assertSentCount(2);

        $this->travel(61)->seconds();
        $this->postJson("/api/trips/{$trip['id']}/location", ['lat' => 14.730, 'lng' => -17.200])->assertOk();
        Http::assertSentCount(3);
    }

    public function test_without_the_road_service_the_estimate_still_works(): void
    {
        config(['services.osrm.url' => 'https://osrm.test']);
        Http::fake(['osrm.test/*' => Http::response('unavailable', 503)]);
        $trip = $this->startTrip();
        [, $rufisque] = $trip['stops'];

        $this->postJson("/api/trips/{$trip['id']}/location", ['lat' => 14.698, 'lng' => -17.355])->assertOk();
        $live = $this->getJson("/api/trips/{$trip['id']}")->json('trip.live');

        $this->assertSame('live', $live['eta_source']);
        $this->assertSame($rufisque['id'], $live['etas'][0]['stop_id']);
    }

    public function test_no_routing_before_the_trip_starts(): void
    {
        $this->fakeRoad();
        $trip = $this->startTrip(start: false);

        $this->postJson("/api/trips/{$trip['id']}/location", ['lat' => 14.6800, 'lng' => -17.4380])->assertOk();
        Http::assertNothingSent();
    }
}
