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

/** Position du passager vers le chauffeur, et lien de suivi pour un proche. */
class TripSharingTest extends TestCase
{
    use RefreshDatabase;

    /** @return array{User, User, Trip, string} chauffeur, passager, trajet, id de réservation confirmée */
    private function confirmedBooking(): array
    {
        $driverUser = User::factory()->create(['is_driver' => true, 'full_name' => 'Ibrahima Ndiaye', 'phone_number' => '+221770000001']);
        Wallet::create(['user_id' => $driverUser->id]);
        $driver = Driver::create(['user_id' => $driverUser->id, 'verification_status' => Driver::STATUS_APPROVED]);
        $vehicle = Vehicle::create([
            'driver_id' => $driver->id, 'plate_number' => 'DK-4321-BB', 'brand' => 'Toyota',
            'model' => 'Corolla', 'color' => 'Blanche', 'seat_count' => 4,
        ]);
        $trip = new Trip([
            'driver_id' => $driver->id, 'vehicle_id' => $vehicle->id, 'departure_type' => 'now',
            'price_per_seat' => 2000, 'seats_available' => 3, 'status' => Trip::STATUS_OPEN,
        ]);
        $trip->setOriginPoint(14.6928, -17.4467);
        $trip->setDestinationPoint(14.7167, -17.4677);
        $trip->save();

        $passenger = User::factory()->create(['full_name' => 'Awa Diop', 'phone_number' => '+221770000002']);
        Sanctum::actingAs($passenger);
        $bookingId = $this->postJson('/api/bookings', [
            'trip_id' => $trip->id, 'seat_count' => 1, 'pickup_lat' => 14.693, 'pickup_lng' => -17.447,
        ])->assertCreated()->json('booking.id');

        Sanctum::actingAs($driverUser);
        $this->postJson("/api/bookings/{$bookingId}/accept")->assertOk();

        return [$driverUser, $passenger, $trip, $bookingId];
    }

    public function test_the_driver_sees_the_position_shared_by_the_passenger_until_it_goes_stale(): void
    {
        [$driverUser, $passenger, $trip, $bookingId] = $this->confirmedBooking();

        Sanctum::actingAs($passenger);
        $this->postJson("/api/bookings/{$bookingId}/location", ['lat' => 14.70, 'lng' => -17.45])->assertOk();

        Sanctum::actingAs($driverUser);
        $this->getJson("/api/trips/{$trip->id}/bookings")
            ->assertJsonPath('data.0.passenger_location.lat', 14.7)
            ->assertJsonMissingPath('data.0.passenger_lat');

        $this->travel(4)->minutes();
        $this->getJson("/api/trips/{$trip->id}/bookings")->assertJsonPath('data.0.passenger_location', null);
    }

    public function test_only_the_passenger_can_share_or_stop_sharing_their_position(): void
    {
        [$driverUser, $passenger, , $bookingId] = $this->confirmedBooking();

        Sanctum::actingAs($driverUser);
        $this->postJson("/api/bookings/{$bookingId}/location", ['lat' => 1, 'lng' => 1])->assertForbidden();

        Sanctum::actingAs($passenger);
        $this->postJson("/api/bookings/{$bookingId}/location", ['lat' => 14.7, 'lng' => -17.4])->assertOk();
        $this->deleteJson("/api/bookings/{$bookingId}/location")->assertOk();
        $this->assertNull(Booking::find($bookingId)->passenger_location);
    }

    public function test_a_share_link_shows_the_trip_without_personal_details(): void
    {
        [, $passenger, , $bookingId] = $this->confirmedBooking();

        Sanctum::actingAs($passenger);
        $url = $this->postJson("/api/bookings/{$bookingId}/share")->assertOk()->json('url');
        $token = basename($url);
        // Le même lien est renvoyé tant qu'il est valable.
        $this->assertSame($url, $this->postJson("/api/bookings/{$bookingId}/share")->json('url'));

        $this->get("/suivi/{$token}")->assertOk()->assertSee('Suivi de trajet');

        $public = $this->getJson("/api/public/share/{$token}")
            ->assertOk()
            ->assertJsonPath('passenger_first_name', 'Awa')
            ->assertJsonPath('driver_first_name', 'Ibrahima')
            ->assertJsonPath('vehicle.plate_number', 'DK-4321-BB');
        $body = $public->getContent();
        $this->assertStringNotContainsString('+22177', $body);
        $this->assertStringNotContainsString('passenger_lat', $body);
    }

    public function test_the_link_stops_working_once_the_booking_is_over_or_unknown(): void
    {
        [, $passenger, , $bookingId] = $this->confirmedBooking();

        Sanctum::actingAs($passenger);
        $token = basename($this->postJson("/api/bookings/{$bookingId}/share")->json('url'));

        Booking::where('id', $bookingId)->update(['status' => Booking::STATUS_COMPLETED]);
        $this->getJson("/api/public/share/{$token}")->assertNotFound();
        $this->getJson('/api/public/share/'.str_repeat('x', 40))->assertNotFound();
    }
}
