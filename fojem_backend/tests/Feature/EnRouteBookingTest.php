<?php

namespace Tests\Feature;

use App\Models\Booking;
use App\Models\Driver;
use App\Models\Notification;
use App\Models\Trip;
use App\Models\User;
use App\Models\Vehicle;
use App\Models\Wallet;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Réservation d'un trajet déjà parti : à un arrêt pas encore atteint, où le
 * chauffeur passe dans au moins 15 min, confirmée d'office.
 */
class EnRouteBookingTest extends TestCase
{
    use RefreshDatabase;

    private const DAKAR = ['name' => 'Dakar', 'address' => 'Gare des Pompiers, Dakar', 'lat' => 14.6800, 'lng' => -17.4380];
    private const RUFISQUE = ['name' => 'Rufisque', 'address' => 'Péage de Rufisque', 'lat' => 14.7160, 'lng' => -17.2730];
    private const THIES = ['name' => 'Thiès', 'address' => 'Gare routière de Thiès', 'lat' => 14.7910, 'lng' => -16.9260];

    private User $driverUser;
    private CarbonImmutable $departure;

    protected function setUp(): void
    {
        parent::setUp();
        $this->departure = CarbonImmutable::now()->addDay()->setTime(8, 30);

        $this->driverUser = User::factory()->create(['is_driver' => true]);
        Wallet::create(['user_id' => $this->driverUser->id]);
        $driver = Driver::create(['user_id' => $this->driverUser->id, 'verification_status' => Driver::STATUS_APPROVED]);
        Vehicle::create([
            'driver_id' => $driver->id,
            'plate_number' => 'DK-5151-ER',
            'brand' => 'Toyota',
            'model' => 'Hiace',
            'color' => 'Blanc',
            'seat_count' => 15,
        ]);
    }

    /** Publie Dakar → Rufisque → Thiès, puis démarre le trajet depuis Dakar. */
    private function startedTrip(bool $acceptsEnRoute = true, int $seats = 3): array
    {
        Sanctum::actingAs($this->driverUser);
        $trip = $this->postJson('/api/trips', [
            'vehicle_id' => $this->driverUser->driver->vehicles()->first()->id,
            'departure_type' => 'scheduled',
            'scheduled_at' => $this->departure->toIso8601String(),
            'price_per_seat' => 3000,
            'seats_available' => $seats,
            'accepts_en_route' => $acceptsEnRoute,
            'stops' => [self::DAKAR, self::RUFISQUE, self::THIES],
        ])->assertCreated()->json('trip');

        $this->travelTo($this->departure);
        $this->postJson("/api/trips/{$trip['id']}/start")->assertOk();
        $this->driverAt($trip['id'], self::DAKAR);

        return $trip;
    }

    private function driverAt(string $tripId, array $point): void
    {
        Sanctum::actingAs($this->driverUser);
        $this->postJson("/api/trips/{$tripId}/location", ['lat' => $point['lat'], 'lng' => $point['lng']])->assertOk();
    }

    private function searchFromRufisque(User $passenger): \Illuminate\Testing\TestResponse
    {
        Sanctum::actingAs($passenger);

        return $this->getJson('/api/trips/search?'.http_build_query([
            'origin_lat' => 14.7200, 'origin_lng' => -17.2650,
            'destination_lat' => self::THIES['lat'], 'destination_lng' => self::THIES['lng'],
        ]));
    }

    private function bookFromRufisque(array $trip, User $passenger): \Illuminate\Testing\TestResponse
    {
        Sanctum::actingAs($passenger);

        return $this->postJson('/api/bookings', [
            'trip_id' => $trip['id'],
            'boarding_stop_id' => $trip['stops'][1]['id'],
            'alighting_stop_id' => $trip['stops'][2]['id'],
        ]);
    }

    public function test_a_passenger_boards_a_trip_already_on_the_road(): void
    {
        $trip = $this->startedTrip();
        $passenger = User::factory()->create();

        $match = $this->searchFromRufisque($passenger)->assertOk()->assertJsonCount(1, 'trips')->json('trips.0.match');
        $this->assertTrue($match['en_route']);
        $this->assertSame('Rufisque', $match['boarding_stop']['name']);
        $this->assertNotNull($match['boarding_eta']);

        $this->bookFromRufisque($trip, $passenger)->assertCreated()->assertJsonPath('booking.status', Booking::STATUS_CONFIRMED);

        $fresh = Trip::find($trip['id']);
        $this->assertSame(Trip::STATUS_IN_PROGRESS, $fresh->status);
        $this->assertEquals(2, $fresh->seats_available);
        $this->assertTrue(Notification::where('user_id', $this->driverUser->id)->where('title', '🚗 Nouveau passager en route')->exists());
        $this->assertTrue(Notification::where('user_id', $passenger->id)->where('type', Notification::TYPE_BOOKING_CONFIRMED)->exists());
    }

    public function test_a_trip_without_the_option_is_not_offered(): void
    {
        $trip = $this->startedTrip(acceptsEnRoute: false);
        $passenger = User::factory()->create();

        $this->searchFromRufisque($passenger)->assertOk()->assertJsonCount(0, 'trips');
        $this->bookFromRufisque($trip, $passenger)->assertUnprocessable();
    }

    public function test_a_stop_reached_soon_or_already_passed_is_not_offered(): void
    {
        $trip = $this->startedTrip();
        $passenger = User::factory()->create();

        // 3 km avant Rufisque : le chauffeur y est dans quelques minutes.
        $this->driverAt($trip['id'], ['lat' => 14.7100, 'lng' => -17.3000]);
        $this->searchFromRufisque($passenger)->assertJsonCount(0, 'trips');
        $this->bookFromRufisque($trip, $passenger)->assertUnprocessable()->assertJsonValidationErrors('boarding_stop_id');

        // Rufisque atteint : il ne se propose plus.
        $this->driverAt($trip['id'], self::RUFISQUE);
        $this->searchFromRufisque($passenger)->assertJsonCount(0, 'trips');
    }

    public function test_recent_no_shows_block_booking_en_route(): void
    {
        $trip = $this->startedTrip();
        $passenger = User::factory()->create();
        for ($i = 0; $i < 3; $i++) {
            $booking = new Booking([
                'trip_id' => $trip['id'],
                'passenger_id' => $passenger->id,
                'seat_count' => 1,
                'status' => Booking::STATUS_NO_SHOW,
                'no_show_at' => now()->subDays(10),
                'departure_code' => '1234',
                'price_charged' => 3000,
            ]);
            $booking->setPickupPoint(self::DAKAR['lat'], self::DAKAR['lng']);
            $booking->save();
        }

        $this->bookFromRufisque($trip, $passenger)->assertUnprocessable()
            ->assertJsonPath('message', fn (string $m) => str_contains($m, 'absences'));
    }

    public function test_accepting_the_last_seat_keeps_the_trip_on_the_road(): void
    {
        Sanctum::actingAs($this->driverUser);
        $trip = $this->postJson('/api/trips', [
            'vehicle_id' => $this->driverUser->driver->vehicles()->first()->id,
            'departure_type' => 'scheduled',
            'scheduled_at' => $this->departure->toIso8601String(),
            'price_per_seat' => 3000,
            'seats_available' => 1,
            'stops' => [self::DAKAR, self::THIES],
        ])->assertCreated()->json('trip');

        Sanctum::actingAs(User::factory()->create());
        $bookingId = $this->postJson('/api/bookings', ['trip_id' => $trip['id']])->assertCreated()->json('booking.id');

        Sanctum::actingAs($this->driverUser);
        $this->postJson("/api/trips/{$trip['id']}/start")->assertOk();
        $this->postJson("/api/bookings/{$bookingId}/accept")->assertOk();

        $this->assertSame(Trip::STATUS_IN_PROGRESS, Trip::find($trip['id'])->status);
    }

    public function test_the_driver_switches_the_option_on_the_road(): void
    {
        $trip = $this->startedTrip(acceptsEnRoute: false);

        $this->patchJson("/api/trips/{$trip['id']}/en-route", ['accepts_en_route' => true])
            ->assertOk()->assertJsonPath('trip.accepts_en_route', true);

        Sanctum::actingAs(User::factory()->create());
        $this->patchJson("/api/trips/{$trip['id']}/en-route", ['accepts_en_route' => false])->assertForbidden();
    }
}
