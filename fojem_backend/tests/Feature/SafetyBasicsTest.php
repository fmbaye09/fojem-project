<?php

namespace Tests\Feature;

use App\Models\Booking;
use App\Models\Driver;
use App\Models\Trip;
use App\Models\User;
use App\Models\Vehicle;
use App\Models\Wallet;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/** Contact d'urgence du chauffeur et validation d'embarquement par code. */
class SafetyBasicsTest extends TestCase
{
    use RefreshDatabase;

    private function makeDriverUser(): User
    {
        $user = User::factory()->create(['is_driver' => true]);
        Wallet::create(['user_id' => $user->id]);
        Driver::create(['user_id' => $user->id, 'verification_status' => Driver::STATUS_PENDING]);

        return $user;
    }

    public function test_the_driver_gives_an_emergency_contact_during_onboarding(): void
    {
        Sanctum::actingAs($this->makeDriverUser());

        $this->post('/api/driver/onboarding', [
            'emergency_contact_name' => 'Fatou Diop',
            'emergency_contact_phone' => '+221 77 123 45 67',
        ], ['Accept' => 'application/json'])
            ->assertOk()
            ->assertJsonPath('emergency_contact.name', 'Fatou Diop')
            ->assertJsonPath('emergency_contact.phone', '+221 77 123 45 67');

        $this->getJson('/api/driver/onboarding')->assertJsonPath('emergency_contact.name', 'Fatou Diop');
    }

    public function test_the_emergency_contact_can_be_changed_from_the_profile(): void
    {
        $user = $this->makeDriverUser();
        Sanctum::actingAs($user);
        $user->setEmergencyContact('Ancien', '771111111');

        $this->putJson('/api/profile/emergency-contact', ['name' => 'Moussa Sow', 'phone' => '781234567'])
            ->assertOk()
            ->assertJsonPath('emergency_contact.name', 'Moussa Sow');

        $this->assertSame(1, $user->emergencyContacts()->count());
        $this->putJson('/api/profile/emergency-contact', ['name' => 'X', 'phone' => 'pas un numéro'])
            ->assertUnprocessable();
    }

    public function test_the_driver_can_board_a_passenger_with_the_four_digit_code(): void
    {
        $driverUser = $this->makeDriverUser();
        $driver = $driverUser->driver;
        $driver->update(['verification_status' => Driver::STATUS_APPROVED]);
        $vehicle = Vehicle::create([
            'driver_id' => $driver->id, 'plate_number' => 'DK-0001-AA', 'brand' => 'Toyota',
            'model' => 'Avanza', 'color' => 'Gris', 'seat_count' => 4,
        ]);
        $trip = new Trip([
            'driver_id' => $driver->id, 'vehicle_id' => $vehicle->id, 'departure_type' => 'now',
            'price_per_seat' => 2000, 'seats_available' => 3, 'status' => Trip::STATUS_OPEN,
        ]);
        $trip->setOriginPoint(14.6928, -17.4467);
        $trip->setDestinationPoint(14.7167, -17.4677);
        $trip->save();

        $passenger = User::factory()->create();
        Sanctum::actingAs($passenger);
        $bookingId = $this->postJson('/api/bookings', [
            'trip_id' => $trip->id, 'seat_count' => 1, 'pickup_lat' => 14.693, 'pickup_lng' => -17.447,
        ])->assertCreated()->json('booking.id');

        Sanctum::actingAs($driverUser);
        $this->postJson("/api/bookings/{$bookingId}/accept")->assertOk();
        $code = Booking::find($bookingId)->departure_code;
        $this->assertMatchesRegularExpression('/^\d{4}$/', $code);

        $this->postJson("/api/trips/{$trip->id}/board-passenger", ['code' => '0000' === $code ? '1111' : '0000'])
            ->assertUnprocessable();
        $this->postJson("/api/trips/{$trip->id}/board-passenger", ['code' => $code])->assertOk();
    }
}
