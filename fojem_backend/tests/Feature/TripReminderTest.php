<?php

namespace Tests\Feature;

use App\Models\Driver;
use App\Models\Notification;
use App\Models\User;
use App\Models\Vehicle;
use App\Models\Wallet;
use App\Services\TripReminderService;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Gestion du temps : rappel 30 min avant, arrivée du chauffeur annoncée aux
 * passagers avec l'heure limite d'attente, que les deux apps décomptent.
 */
class TripReminderTest extends TestCase
{
    use RefreshDatabase;

    private const DAKAR = ['name' => 'Dakar', 'address' => 'Gare des Pompiers, Dakar', 'lat' => 14.6800, 'lng' => -17.4380];
    private const THIES = ['name' => 'Thiès', 'address' => 'Gare routière de Thiès', 'lat' => 14.7910, 'lng' => -16.9260];

    private User $driverUser;
    private User $passenger;
    private string $tripId;
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
            'plate_number' => 'DK-3030-RM',
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

        $this->passenger = $this->bookAndAccept();
    }

    private function bookAndAccept(): User
    {
        $passenger = User::factory()->create();
        Sanctum::actingAs($passenger);
        $bookingId = $this->postJson('/api/bookings', ['trip_id' => $this->tripId])->assertCreated()->json('booking.id');
        Sanctum::actingAs($this->driverUser);
        $this->postJson("/api/bookings/{$bookingId}/accept")->assertOk();

        return $passenger;
    }

    private function driverAt(array $point): void
    {
        Sanctum::actingAs($this->driverUser);
        $this->postJson("/api/trips/{$this->tripId}/location", ['lat' => $point['lat'], 'lng' => $point['lng']])->assertOk();
    }

    private function notificationsOf(User $user, string $title): \Illuminate\Support\Collection
    {
        return Notification::where('user_id', $user->id)->where('title', 'like', $title.'%')->get();
    }

    private function sendDue(): array
    {
        return app(TripReminderService::class)->sendDue();
    }

    public function test_driver_and_passenger_are_reminded_once_half_an_hour_before(): void
    {
        $this->travelTo($this->departure->subMinutes(31));
        $this->assertSame(['drivers' => 0, 'passengers' => 0], $this->sendDue());

        $this->travelTo($this->departure->subMinutes(25));
        $this->assertSame(['drivers' => 1, 'passengers' => 1], $this->sendDue());
        $this->assertSame(['drivers' => 0, 'passengers' => 0], $this->sendDue());

        $driverReminder = $this->notificationsOf($this->driverUser, '⏰ Départ dans 25 min')->sole();
        $this->assertStringContainsString('à 08:30, 1 passager confirmé', $driverReminder->payload['body']);
        $this->assertSame($this->tripId, $driverReminder->payload['trip_id']);

        $passengerReminder = $this->notificationsOf($this->passenger, '⏰ Rendez-vous dans 25 min')->sole();
        $this->assertStringContainsString('Soyez à Dakar à 08:30', $passengerReminder->payload['body']);
        $this->assertSame($this->tripId, $passengerReminder->payload['trip_id']);
    }

    public function test_a_booking_confirmed_within_the_last_half_hour_gets_no_reminder(): void
    {
        $this->travelTo($this->departure->subMinutes(20));
        $latecomer = $this->bookAndAccept();

        $this->assertSame(['drivers' => 1, 'passengers' => 1], $this->sendDue());
        $this->assertCount(0, $this->notificationsOf($latecomer, '⏰'));
        $this->assertCount(1, $this->notificationsOf($this->passenger, '⏰'));
    }

    public function test_passengers_learn_when_the_driver_arrives_and_until_when_he_waits(): void
    {
        $this->travelTo($this->departure->subMinutes(10));
        $this->driverAt(self::DAKAR);

        $arrival = $this->notificationsOf($this->passenger, '📍 Votre chauffeur est arrivé')->sole();
        $this->assertStringContainsString('à Dakar jusqu’à 08:35', $arrival->payload['body']);

        // Les deux apps décomptent jusqu'à cette heure.
        Sanctum::actingAs($this->passenger);
        $stops = $this->getJson("/api/trips/{$this->tripId}")->assertOk()->json('trip.stops');
        $this->assertEquals($this->departure->addMinutes(5), CarbonImmutable::parse($stops[0]['wait_until']));
        $this->assertNull($stops[1]['wait_until']);
    }

    public function test_a_late_driver_waits_five_minutes_from_their_arrival(): void
    {
        $this->travelTo($this->departure->addMinutes(20));
        $this->driverAt(self::DAKAR);

        $arrival = $this->notificationsOf($this->passenger, '📍 Votre chauffeur est arrivé')->sole();
        $this->assertStringContainsString('jusqu’à 08:55', $arrival->payload['body']);
    }

    public function test_an_early_arrival_is_announced_by_the_reminder(): void
    {
        $this->travelTo($this->departure->subMinutes(50));
        $this->driverAt(self::DAKAR);
        $this->assertCount(0, $this->notificationsOf($this->passenger, '📍'));

        $this->travelTo($this->departure->subMinutes(25));
        $this->sendDue();
        $reminder = $this->notificationsOf($this->passenger, '⏰ Rendez-vous')->sole();
        $this->assertStringContainsString('déjà au point de rendez-vous (Dakar). Rejoignez-le avant 08:35', $reminder->payload['body']);
    }
}
