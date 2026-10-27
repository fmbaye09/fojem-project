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
 * BlaBlaCar-style meeting points: drivers publish stops, passengers search
 * against every stop and book a boarding → alighting segment.
 */
class TripStopsTest extends TestCase
{
    use RefreshDatabase;

    // Dakar (gare Pompiers) → Rufisque (péage) → Thiès (gare routière).
    private const DAKAR = ['name' => 'Dakar', 'address' => 'Gare des Pompiers, Dakar', 'lat' => 14.6800, 'lng' => -17.4380];
    private const RUFISQUE = ['name' => 'Rufisque', 'address' => 'Péage de Rufisque', 'lat' => 14.7160, 'lng' => -17.2730];
    private const THIES = ['name' => 'Thiès', 'address' => 'Gare routière de Thiès', 'lat' => 14.7910, 'lng' => -16.9260];

    private function publishTrip(array $stops, array $overrides = []): array
    {
        $user = User::factory()->create(['is_driver' => true]);
        Wallet::create(['user_id' => $user->id]);
        $driver = Driver::create(['user_id' => $user->id, 'verification_status' => Driver::STATUS_APPROVED]);
        $vehicle = Vehicle::create([
            'driver_id' => $driver->id,
            'plate_number' => 'DK-'.random_int(1000, 9999).'-ST',
            'brand' => 'Toyota',
            'model' => 'Avanza',
            'color' => 'Gris',
            'seat_count' => 7,
        ]);
        Sanctum::actingAs($user);

        $response = $this->postJson('/api/trips', $overrides + [
            'vehicle_id' => $vehicle->id,
            'departure_type' => 'scheduled',
            'scheduled_at' => now()->addDay()->setTime(8, 30)->toIso8601String(),
            'price_per_seat' => 3000,
            'seats_available' => 3,
            'stops' => $stops,
        ]);
        $response->assertCreated();

        return $response->json('trip');
    }

    private function search(array $from, array $to, array $extra = []): \Illuminate\Testing\TestResponse
    {
        Sanctum::actingAs(User::factory()->create());

        return $this->getJson('/api/trips/search?' . http_build_query($extra + [
            'origin_lat' => $from['lat'],
            'origin_lng' => $from['lng'],
            'destination_lat' => $to['lat'],
            'destination_lng' => $to['lng'],
        ]));
    }

    public function test_publishing_fills_stop_times_and_pro_rata_prices(): void
    {
        $trip = $this->publishTrip([self::DAKAR, self::RUFISQUE, self::THIES]);

        $this->assertCount(3, $trip['stops']);
        [$dakar, $rufisque, $thies] = $trip['stops'];

        $this->assertSame('Gare des Pompiers, Dakar', $dakar['address']);
        $this->assertEquals(0, $dakar['price_from_origin']);
        $this->assertEquals(3000, $thies['price_from_origin']);
        // Rufisque sits about a third of the way: priced between, rounded to 50.
        $this->assertGreaterThan(0, (float) $rufisque['price_from_origin']);
        $this->assertLessThan(3000, (float) $rufisque['price_from_origin']);
        $this->assertEquals(0, fmod((float) $rufisque['price_from_origin'], 50));
        $this->assertTrue($rufisque['scheduled_at'] > $dakar['scheduled_at']);
        $this->assertTrue($thies['scheduled_at'] > $rufisque['scheduled_at']);

        $this->assertSame('Dakar', $trip['origin_name']);
        $this->assertSame('Thiès', $trip['destination_name']);
    }

    public function test_a_passenger_boarding_mid_route_finds_the_trip_with_its_segment(): void
    {
        $trip = $this->publishTrip([self::DAKAR, self::RUFISQUE, self::THIES]);
        $rufisquePrice = (float) $trip['stops'][1]['price_from_origin'];

        // Passenger lives near Rufisque (≈1 km from the stop) and goes to Thiès.
        $response = $this->search(['lat' => 14.7200, 'lng' => -17.2650], self::THIES)->assertOk();

        $response->assertJsonCount(1, 'trips');
        $match = $response->json('trips.0.match');
        $this->assertSame('Rufisque', $match['boarding_stop']['name']);
        $this->assertSame('Thiès', $match['alighting_stop']['name']);
        $this->assertLessThan(2000, $match['boarding_distance_m']);
        $this->assertEquals(3000 - $rufisquePrice, (float) $match['segment_price']);
    }

    public function test_the_opposite_direction_does_not_match(): void
    {
        $this->publishTrip([self::DAKAR, self::RUFISQUE, self::THIES]);

        $this->search(self::THIES, self::DAKAR)->assertOk()->assertJsonCount(0, 'trips');
    }

    public function test_search_filters_on_date_and_seats(): void
    {
        $this->publishTrip([self::DAKAR, self::THIES]);
        $tomorrow = now()->addDay()->toDateString();

        $this->search(self::DAKAR, self::THIES, ['date' => $tomorrow])->assertJsonCount(1, 'trips');
        $this->search(self::DAKAR, self::THIES, ['date' => now()->addDays(3)->toDateString()])->assertJsonCount(0, 'trips');
        $this->search(self::DAKAR, self::THIES, ['seats' => 4])->assertJsonCount(0, 'trips');
    }

    public function test_booking_a_segment_charges_the_segment_price(): void
    {
        $trip = $this->publishTrip([self::DAKAR, self::RUFISQUE, self::THIES]);
        [, $rufisque, $thies] = $trip['stops'];

        Sanctum::actingAs(User::factory()->create());
        $booking = $this->postJson('/api/bookings', [
            'trip_id' => $trip['id'],
            'boarding_stop_id' => $rufisque['id'],
            'alighting_stop_id' => $thies['id'],
            'seat_numbers' => ['1', '2'],
        ])->assertCreated()->json('booking');

        $segment = 3000 - (float) $rufisque['price_from_origin'];
        $this->assertEquals($segment * 2, (float) $booking['price_charged']);
        $this->assertSame('Rufisque', $booking['boarding_stop']['name']);
        $this->assertSame('Thiès', $booking['alighting_stop']['name']);
    }

    public function test_boarding_after_alighting_is_rejected(): void
    {
        $trip = $this->publishTrip([self::DAKAR, self::RUFISQUE, self::THIES]);
        [$dakar, $rufisque] = $trip['stops'];

        Sanctum::actingAs(User::factory()->create());
        $this->postJson('/api/bookings', [
            'trip_id' => $trip['id'],
            'boarding_stop_id' => $rufisque['id'],
            'alighting_stop_id' => $dakar['id'],
        ])->assertUnprocessable()->assertJsonValidationErrors('alighting_stop_id');
    }

    public function test_a_booking_without_stops_spans_the_whole_trip(): void
    {
        $trip = $this->publishTrip([self::DAKAR, self::RUFISQUE, self::THIES]);

        Sanctum::actingAs(User::factory()->create());
        $booking = $this->postJson('/api/bookings', [
            'trip_id' => $trip['id'],
            'seat_count' => 1,
            'pickup_lat' => 14.69,
            'pickup_lng' => -17.44,
        ])->assertCreated()->json('booking');

        $this->assertSame('Dakar', $booking['boarding_stop']['name']);
        $this->assertSame('Thiès', $booking['alighting_stop']['name']);
        $this->assertEquals(3000, (float) $booking['price_charged']);
    }

    public function test_driver_prices_must_increase_along_the_route(): void
    {
        $stops = [self::DAKAR, self::RUFISQUE + ['price_from_origin' => 3500], self::THIES];

        $user = User::factory()->create(['is_driver' => true]);
        Wallet::create(['user_id' => $user->id]);
        $driver = Driver::create(['user_id' => $user->id, 'verification_status' => Driver::STATUS_APPROVED]);
        $vehicle = Vehicle::create([
            'driver_id' => $driver->id, 'plate_number' => 'DK-7777-ST', 'brand' => 'Toyota',
            'model' => 'Avanza', 'color' => 'Gris', 'seat_count' => 7,
        ]);
        Sanctum::actingAs($user);

        $this->postJson('/api/trips', [
            'vehicle_id' => $vehicle->id,
            'departure_type' => 'now',
            'price_per_seat' => 3000,
            'seats_available' => 3,
            'stops' => $stops,
        ])->assertUnprocessable()->assertJsonValidationErrors('stops.1.price_from_origin');
    }
}
