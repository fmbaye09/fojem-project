<?php

namespace Tests\Feature;

use App\Models\AdminRole;
use App\Models\AdminUser;
use App\Models\Booking;
use App\Models\Driver;
use App\Models\Transaction;
use App\Models\Trip;
use App\Models\User;
use App\Models\Vehicle;
use App\Models\Wallet;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class AdminStatsTest extends TestCase
{
    use RefreshDatabase;

    private function makeAdmin(): AdminUser
    {
        $role = AdminRole::firstOrCreate(['name' => AdminRole::SUPPORT]);

        return AdminUser::create([
            'full_name' => 'Stats Admin',
            'email' => 'stats-admin@fojem.sn',
            'password_hash' => Hash::make('password123'),
            'role_id' => $role->id,
            'is_active' => true,
        ]);
    }

    private function makeDriverWithVehicleAndTrip(): array
    {
        $driverUser = User::factory()->create(['is_driver' => true]);
        Wallet::create(['user_id' => $driverUser->id]);
        $driver = Driver::create([
            'user_id' => $driverUser->id,
            'verification_status' => Driver::STATUS_APPROVED,
        ]);
        $vehicle = Vehicle::create([
            'driver_id' => $driver->id,
            'plate_number' => 'DK-'.uniqid(),
            'brand' => 'Toyota',
            'model' => 'Corolla',
            'color' => 'Grise',
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

        return [$driver, $trip];
    }

    public function test_transactions_breakdown_groups_completed_transactions_by_method_and_type(): void
    {
        $admin = $this->makeAdmin();
        Sanctum::actingAs($admin, ['admin'], 'admin');

        [$driver, $trip] = $this->makeDriverWithVehicleAndTrip();
        $passenger = User::factory()->create();
        $passengerWallet = Wallet::create(['user_id' => $passenger->id]);

        $booking = new Booking([
            'trip_id' => $trip->id,
            'passenger_id' => $passenger->id,
            'status' => 'confirmed',
            'departure_code' => '1234',
            'price_charged' => 2000,
        ]);
        $booking->setPickupPoint(14.6928, -17.4467);
        $booking->save();

        Transaction::create([
            'wallet_id' => $passengerWallet->id,
            'booking_id' => $booking->id,
            'type' => 'payment',
            'amount' => 2000,
            'payment_method' => 'wave',
            'idempotency_key' => 'test-'.uniqid(),
            'status' => 'completed',
        ]);

        $response = $this->getJson('/api/admin/stats/transactions-breakdown');

        $response->assertOk();
        $response->assertJsonPath('by_payment_method.wave.count', 1);
        $response->assertJsonPath('by_type.payment.count', 1);
    }

    public function test_new_accounts_timeseries_splits_passengers_and_drivers(): void
    {
        $admin = $this->makeAdmin();
        Sanctum::actingAs($admin, ['admin'], 'admin');

        User::factory()->create(['is_driver' => false]);
        User::factory()->create(['is_driver' => true]);

        $response = $this->getJson('/api/admin/stats/new-accounts-timeseries');

        $response->assertOk();
        $today = now()->toDateString();
        $response->assertJsonPath("new_passengers_per_day.$today", 1);
        $response->assertJsonPath("new_drivers_per_day.$today", 1);
    }

    public function test_stats_endpoints_require_an_active_admin_token(): void
    {
        $response = $this->getJson('/api/admin/stats/transactions-breakdown');
        $response->assertUnauthorized();

        $response = $this->getJson('/api/admin/stats/new-accounts-timeseries');
        $response->assertUnauthorized();
    }
}
