<?php

namespace Tests\Feature;

use App\Models\Driver;
use App\Models\PlatformSetting;
use App\Models\Trip;
use App\Models\User;
use App\Models\Vehicle;
use App\Models\Wallet;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class WalletCreditOnCompletionTest extends TestCase
{
    use RefreshDatabase;

    private function makeConfirmedBooking(): array
    {
        $driverUser = User::factory()->create(['is_driver' => true]);
        Wallet::create(['user_id' => $driverUser->id, 'balance' => 0]);
        $driver = Driver::create(['user_id' => $driverUser->id, 'verification_status' => Driver::STATUS_APPROVED]);
        $vehicle = Vehicle::create([
            'driver_id' => $driver->id,
            'plate_number' => 'DK-8888-AA',
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

        $passenger = User::factory()->create();
        Sanctum::actingAs($passenger);

        $bookingId = $this->postJson('/api/bookings', [
            'trip_id' => $trip->id,
            'seat_count' => 1,
            'pickup_lat' => 14.693,
            'pickup_lng' => -17.447,
        ])->json('booking.id');

        Sanctum::actingAs($driverUser);
        $this->postJson("/api/bookings/{$bookingId}/accept")->assertOk();

        return [$driverUser, $bookingId];
    }

    public function test_completing_a_booking_credits_the_drivers_wallet_net_of_commission(): void
    {
        PlatformSetting::create([
            'zone_name' => 'Dakar',
            'price_per_km' => 150,
            'commission_pct' => 10,
        ]);

        [$driverUser, $bookingId] = $this->makeConfirmedBooking();

        Sanctum::actingAs($driverUser);
        $response = $this->postJson("/api/bookings/{$bookingId}/complete");

        $response->assertOk();
        $this->assertEquals('completed', $response->json('booking.status'));

        // price_charged = 2000, commission 10% -> net 1800 credited.
        $driverUser->wallet->refresh();
        $this->assertEquals('1800.00', $driverUser->wallet->balance);

        $this->assertDatabaseHas('transactions', [
            'wallet_id' => $driverUser->wallet->id,
            'booking_id' => $bookingId,
            'type' => 'payment',
            'amount' => 1800,
            'idempotency_key' => "booking_payment:{$bookingId}",
        ]);
    }

    public function test_completing_a_booking_credits_the_full_amount_when_no_platform_setting_exists(): void
    {
        [$driverUser, $bookingId] = $this->makeConfirmedBooking();

        Sanctum::actingAs($driverUser);
        $this->postJson("/api/bookings/{$bookingId}/complete")->assertOk();

        $driverUser->wallet->refresh();
        $this->assertEquals('2000.00', $driverUser->wallet->balance);
    }

    public function test_only_the_trips_driver_can_complete_a_booking(): void
    {
        [, $bookingId] = $this->makeConfirmedBooking();

        $stranger = User::factory()->create();
        Sanctum::actingAs($stranger);

        $this->postJson("/api/bookings/{$bookingId}/complete")->assertForbidden();
    }
}
