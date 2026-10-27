<?php

namespace Tests\Feature;

use App\Models\AdminPermission;
use App\Models\AdminRole;
use App\Models\AdminUser;
use App\Models\AuditLog;
use App\Models\Booking;
use App\Models\Driver;
use App\Models\Trip;
use App\Models\User;
use App\Models\Vehicle;
use App\Models\Wallet;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class AdminTripTest extends TestCase
{
    use RefreshDatabase;

    private function actingAsAdminWith(array $permissions): AdminUser
    {
        $role = AdminRole::create(['name' => 'custom_role_'.uniqid()]);
        foreach ($permissions as [$resource, $action]) {
            AdminPermission::create(['role_id' => $role->id, 'resource' => $resource, 'action' => $action]);
        }

        $admin = AdminUser::create([
            'full_name' => 'Support Admin',
            'email' => uniqid().'@fojem.sn',
            'password_hash' => Hash::make('password123'),
            'role_id' => $role->id,
            'is_active' => true,
        ]);
        Sanctum::actingAs($admin, ['admin'], 'admin');

        return $admin;
    }

    private function makeTrip(string $originName, string $driverName, string $status = Trip::STATUS_OPEN): Trip
    {
        $driverUser = User::factory()->create(['is_driver' => true, 'full_name' => $driverName]);
        Wallet::create(['user_id' => $driverUser->id]);
        $driver = Driver::create(['user_id' => $driverUser->id, 'verification_status' => Driver::STATUS_APPROVED]);
        $vehicle = Vehicle::create([
            'driver_id' => $driver->id,
            'plate_number' => 'DK-'.random_int(1000, 9999).'-AA',
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
            'status' => $status,
            'origin_name' => $originName,
            'destination_name' => 'Thiès',
        ]);
        $trip->setOriginPoint(14.6928, -17.4467);
        $trip->setDestinationPoint(14.7910, -16.9359);
        $trip->save();

        return $trip;
    }

    private function confirmedBooking(Trip $trip): Booking
    {
        $passenger = User::factory()->create();
        $booking = new Booking([
            'trip_id' => $trip->id,
            'passenger_id' => $passenger->id,
            'seat_count' => 1,
            'status' => Booking::STATUS_CONFIRMED,
            'departure_code' => '1234',
            'price_charged' => 2000,
        ]);
        $booking->setPickupPoint(14.693, -17.447);
        $booking->save();

        return $booking;
    }

    public function test_admin_can_list_and_filter_trips(): void
    {
        $this->makeTrip('Plateau', 'Moussa Diop');
        $this->makeTrip('Ouakam', 'Awa Ndiaye', Trip::STATUS_COMPLETED);
        $this->actingAsAdminWith([['trips', 'view']]);

        $this->getJson('/api/admin/trips')->assertOk()->assertJsonPath('total', 2);

        $this->getJson('/api/admin/trips?status=completed')
            ->assertOk()
            ->assertJsonPath('total', 1)
            ->assertJsonPath('data.0.origin_name', 'Ouakam');

        $this->getJson('/api/admin/trips?search=moussa')
            ->assertOk()
            ->assertJsonPath('total', 1)
            ->assertJsonPath('data.0.driver.full_name', 'Moussa Diop');
    }

    public function test_trip_detail_lists_passengers(): void
    {
        $trip = $this->makeTrip('Plateau', 'Moussa Diop');
        $booking = $this->confirmedBooking($trip);
        $this->actingAsAdminWith([['trips', 'view']]);

        $this->getJson("/api/admin/trips/{$trip->id}")
            ->assertOk()
            ->assertJsonPath('trip.bookings.0.id', $booking->id)
            ->assertJsonPath('trip.bookings.0.passenger.full_name', $booking->passenger->full_name)
            ->assertJsonPath('trip.confirmed_bookings_count', 1);
    }

    public function test_admin_without_trips_permission_is_forbidden(): void
    {
        $this->actingAsAdminWith([['users', 'view']]);

        $this->getJson('/api/admin/trips')->assertForbidden();
    }

    public function test_view_only_admin_cannot_cancel_a_trip(): void
    {
        $trip = $this->makeTrip('Plateau', 'Moussa Diop');
        $this->actingAsAdminWith([['trips', 'view']]);

        $this->postJson("/api/admin/trips/{$trip->id}/cancel", ['reason' => 'Signalement'])
            ->assertForbidden();
    }

    public function test_admin_cancellation_cancels_bookings_and_is_audited(): void
    {
        $trip = $this->makeTrip('Plateau', 'Moussa Diop');
        $booking = $this->confirmedBooking($trip);
        $admin = $this->actingAsAdminWith([['trips', 'view'], ['trips', 'edit']]);

        $this->postJson("/api/admin/trips/{$trip->id}/cancel", ['reason' => 'Chauffeur injoignable'])
            ->assertOk()
            ->assertJsonPath('trip.status', Trip::STATUS_CANCELLED)
            ->assertJsonPath('trip.closed_by', 'admin');

        $this->assertEquals(Booking::STATUS_CANCELLED_DRIVER, $booking->fresh()->status);

        $log = AuditLog::where('target_type', 'trip')->where('target_id', $trip->id)->first();
        $this->assertNotNull($log);
        $this->assertEquals('trip.cancelled', $log->action);
        $this->assertEquals($admin->id, $log->actor_admin_id);
        $this->assertEquals('Chauffeur injoignable', $log->new_value['reason']);
    }

    public function test_a_cancellation_requires_a_reason(): void
    {
        $trip = $this->makeTrip('Plateau', 'Moussa Diop');
        $this->actingAsAdminWith([['trips', 'view'], ['trips', 'edit']]);

        $this->postJson("/api/admin/trips/{$trip->id}/cancel", [])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('reason');
    }
}
