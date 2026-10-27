<?php

namespace Tests\Feature;

use App\Models\Driver;
use App\Models\RideRequest;
use App\Models\Trip;
use App\Models\User;
use App\Models\Vehicle;
use App\Models\Wallet;
use App\Services\MatchingService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class MatchingTest extends TestCase
{
    use RefreshDatabase;

    public function test_a_ride_request_matching_a_trip_closely_scores_high(): void
    {
        $driverUser = User::factory()->create(['is_driver' => true]);
        Wallet::create(['user_id' => $driverUser->id]);
        $driver = Driver::create(['user_id' => $driverUser->id, 'verification_status' => Driver::STATUS_APPROVED]);
        $vehicle = Vehicle::create([
            'driver_id' => $driver->id,
            'plate_number' => 'DK-0005-AA',
            'brand' => 'Toyota',
            'model' => 'Corolla',
            'color' => 'Blanc',
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

        $passenger = User::factory()->create();

        $closeRequest = new RideRequest([
            'passenger_id' => $passenger->id,
            'requested_at' => now(),
            'status' => RideRequest::STATUS_SEARCHING,
        ]);
        $closeRequest->setOriginPoint(14.6930, -17.4470); // ~50m from trip origin
        $closeRequest->setDestinationPoint(14.7160, -17.4670); // ~100m from trip destination
        $closeRequest->save();

        $farRequest = new RideRequest([
            'passenger_id' => $passenger->id,
            'requested_at' => now(),
            'status' => RideRequest::STATUS_SEARCHING,
        ]);
        // Opposite direction, several km away.
        $farRequest->setOriginPoint(14.60, -17.30);
        $farRequest->setDestinationPoint(14.55, -17.20);
        $farRequest->save();

        $service = app(MatchingService::class);
        $closeScore = $service->score($closeRequest, $trip);
        $farScore = $service->score($farRequest, $trip);

        $this->assertGreaterThan(90, (float) $closeScore->compatibility_score);
        $this->assertGreaterThan((float) $farScore->compatibility_score, (float) $closeScore->compatibility_score);

        $this->assertDatabaseHas('matching_scores', [
            'ride_request_id' => $closeRequest->id,
            'trip_id' => $trip->id,
        ]);
    }
}
