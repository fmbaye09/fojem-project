<?php

namespace Tests\Feature;

use App\Models\Booking;
use App\Models\Driver;
use App\Models\Notification;
use App\Models\ReputationScore;
use App\Models\Trip;
use App\Models\User;
use App\Models\Vehicle;
use App\Models\Wallet;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * « Passager absent » : le chauffeur doit être au point de rendez-vous et y
 * avoir attendu 5 min ; l'absence pèse sur la fiabilité du passager.
 */
class NoShowTest extends TestCase
{
    use RefreshDatabase;

    private const DAKAR = ['name' => 'Dakar', 'address' => 'Gare des Pompiers, Dakar', 'lat' => 14.6800, 'lng' => -17.4380];
    private const THIES = ['name' => 'Thiès', 'address' => 'Gare routière de Thiès', 'lat' => 14.7910, 'lng' => -16.9260];

    private User $driverUser;
    private User $passenger;
    private string $tripId;
    private string $bookingId;
    private CarbonImmutable $departure;

    protected function setUp(): void
    {
        parent::setUp();

        $this->departure = CarbonImmutable::now()->addDay()->setTime(8, 30);

        $this->driverUser = User::factory()->create(['is_driver' => true]);
        Wallet::create(['user_id' => $this->driverUser->id]);
        $driver = Driver::create(['user_id' => $this->driverUser->id, 'verification_status' => Driver::STATUS_APPROVED]);
        $vehicle = Vehicle::create([
            'driver_id' => $driver->id,
            'plate_number' => 'DK-4242-NS',
            'brand' => 'Toyota',
            'model' => 'Avanza',
            'color' => 'Gris',
            'seat_count' => 7,
        ]);

        Sanctum::actingAs($this->driverUser);
        $this->tripId = $this->postJson('/api/trips', [
            'vehicle_id' => $vehicle->id,
            'departure_type' => 'scheduled',
            'scheduled_at' => $this->departure->toIso8601String(),
            'price_per_seat' => 3000,
            'seats_available' => 3,
            'stops' => [self::DAKAR, self::THIES],
        ])->assertCreated()->json('trip.id');

        $this->passenger = User::factory()->create();
        Sanctum::actingAs($this->passenger);
        $this->bookingId = $this->postJson('/api/bookings', ['trip_id' => $this->tripId])->assertCreated()->json('booking.id');

        Sanctum::actingAs($this->driverUser);
        $this->postJson("/api/bookings/{$this->bookingId}/accept")->assertOk();
    }

    private function driverAt(array $point): void
    {
        Sanctum::actingAs($this->driverUser);
        $this->postJson("/api/trips/{$this->tripId}/location", ['lat' => $point['lat'], 'lng' => $point['lng']])->assertOk();
    }

    private function declareAbsent(): \Illuminate\Testing\TestResponse
    {
        Sanctum::actingAs($this->driverUser);

        return $this->postJson("/api/bookings/{$this->bookingId}/no-show");
    }

    public function test_the_driver_must_be_at_the_meeting_point(): void
    {
        $this->travelTo($this->departure->addMinutes(10));
        $this->driverAt(self::THIES);

        $this->declareAbsent()->assertUnprocessable()->assertJsonPath('message', fn (string $m) => str_contains($m, 'Dakar'));
        $this->assertSame(Booking::STATUS_CONFIRMED, Booking::find($this->bookingId)->status);
    }

    public function test_the_passenger_has_five_minutes_after_the_scheduled_time(): void
    {
        $this->travelTo($this->departure->subMinutes(10));
        $this->driverAt(self::DAKAR);
        $this->declareAbsent()->assertUnprocessable()->assertJsonPath('message', fn (string $m) => str_contains($m, '15 min'));

        $this->travelTo($this->departure->addMinutes(5));
        $this->driverAt(self::DAKAR);
        $this->declareAbsent()->assertOk()->assertJsonPath('booking.status', Booking::STATUS_NO_SHOW);

        $this->assertEquals(3, Trip::find($this->tripId)->seats_available);
        $this->assertTrue(Notification::where('user_id', $this->passenger->id)->where('title', '🚫 Absence signalée')->exists());

        $score = ReputationScore::find($this->passenger->id);
        $this->assertSame(1, (int) $score->no_show_count);
        $this->assertEquals(0, (float) $score->bookings_honored_pct);
    }

    public function test_a_late_driver_waits_five_minutes_from_their_arrival(): void
    {
        $this->travelTo($this->departure->addMinutes(20));
        $this->driverAt(self::DAKAR);
        $this->declareAbsent()->assertUnprocessable()->assertJsonPath('message', fn (string $m) => str_contains($m, '5 min'));

        $this->travelTo($this->departure->addMinutes(26));
        $this->driverAt(self::DAKAR);
        $this->declareAbsent()->assertOk();
    }

    public function test_an_old_position_is_not_a_proof(): void
    {
        $this->travelTo($this->departure);
        $this->driverAt(self::DAKAR);

        $this->travelTo($this->departure->addMinutes(10));
        $this->declareAbsent()->assertUnprocessable();
    }

    public function test_a_passenger_on_board_cannot_be_absent(): void
    {
        Sanctum::actingAs($this->driverUser);
        $this->postJson("/api/bookings/{$this->bookingId}/board")->assertOk();

        $this->travelTo($this->departure->addMinutes(10));
        $this->driverAt(self::DAKAR);
        $this->declareAbsent()->assertUnprocessable();
    }

    public function test_drivers_see_the_reliability_of_their_passengers(): void
    {
        Sanctum::actingAs($this->driverUser);
        $this->getJson('/api/bookings/received')->assertJsonPath('data.0.passenger_reliability', null);

        $this->travelTo($this->departure);
        $this->driverAt(self::DAKAR);
        $this->travelTo($this->departure->addMinutes(5));
        $this->driverAt(self::DAKAR);
        $this->declareAbsent()->assertOk();

        $this->getJson("/api/trips/{$this->tripId}/bookings")
            ->assertJsonPath('data.0.passenger_reliability.honored_pct', 0)
            ->assertJsonPath('data.0.passenger_reliability.no_show_count', 1);
    }

    public function test_only_last_minute_cancellations_count(): void
    {
        // La veille : une annulation sans conséquence.
        Sanctum::actingAs($this->passenger);
        $this->postJson("/api/bookings/{$this->bookingId}/cancel")->assertOk();
        $this->assertNull(ReputationScore::find($this->passenger->id)->bookings_honored_pct);

        // Une heure avant la montée : elle compte.
        $second = $this->postJson('/api/bookings', ['trip_id' => $this->tripId])->assertCreated()->json('booking.id');
        $this->travelTo($this->departure->subHour());
        $this->postJson("/api/bookings/{$second}/cancel")->assertOk();
        $this->assertEquals(0, (float) ReputationScore::find($this->passenger->id)->bookings_honored_pct);
    }
}
