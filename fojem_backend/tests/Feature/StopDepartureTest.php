<?php

namespace Tests\Feature;

use App\Models\Booking;
use App\Models\Driver;
use App\Models\Notification;
use App\Models\ReputationScore;
use App\Models\Transaction;
use App\Models\TripStop;
use App\Models\User;
use App\Models\Vehicle;
use App\Models\Wallet;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Le chauffeur qui quitte un arrêt : départ enregistré, passagers laissés
 * sur place prévenus, chauffeur averti s'il part trop tôt, et à la fin du
 * trajet, absent ou « manqué » selon qu'il les a attendus jusqu'au bout.
 */
class StopDepartureTest extends TestCase
{
    use RefreshDatabase;

    private const DAKAR = ['name' => 'Dakar', 'address' => 'Gare des Pompiers, Dakar', 'lat' => 14.6800, 'lng' => -17.4380];
    private const RUFISQUE = ['name' => 'Rufisque', 'address' => 'Péage de Rufisque', 'lat' => 14.7160, 'lng' => -17.2730];
    private const THIES = ['name' => 'Thiès', 'address' => 'Gare routière de Thiès', 'lat' => 14.7910, 'lng' => -16.9260];

    /** À 3 km de Dakar et de Rufisque, sur la route. */
    private const AFTER_DAKAR = ['lat' => 14.6950, 'lng' => -17.4100];
    private const AFTER_RUFISQUE = ['lat' => 14.7300, 'lng' => -17.2450];

    private User $driverUser;
    private CarbonImmutable $departure;
    private array $trip;

    protected function setUp(): void
    {
        parent::setUp();
        $this->departure = CarbonImmutable::now()->addDay()->setTime(8, 30);

        $this->driverUser = User::factory()->create(['is_driver' => true, 'full_name' => 'Modou Seck']);
        Wallet::create(['user_id' => $this->driverUser->id]);
        $driver = Driver::create(['user_id' => $this->driverUser->id, 'verification_status' => Driver::STATUS_APPROVED]);
        Vehicle::create([
            'driver_id' => $driver->id,
            'plate_number' => 'DK-3030-SD',
            'brand' => 'Toyota',
            'model' => 'Hiace',
            'color' => 'Blanc',
            'seat_count' => 15,
        ]);

        Sanctum::actingAs($this->driverUser);
        $this->trip = $this->postJson('/api/trips', [
            'vehicle_id' => $driver->vehicles()->first()->id,
            'departure_type' => 'scheduled',
            'scheduled_at' => $this->departure->toIso8601String(),
            'price_per_seat' => 3000,
            'seats_available' => 6,
            'stops' => [self::DAKAR, self::RUFISQUE, self::THIES],
        ])->assertCreated()->json('trip');
    }

    /** Une place confirmée, montée à l'arrêt [stop] (0 = Dakar, 1 = Rufisque). */
    private function passenger(string $name, int $stop = 0): array
    {
        $user = User::factory()->create(['full_name' => $name]);
        Sanctum::actingAs($user);
        $booking = $this->postJson('/api/bookings', [
            'trip_id' => $this->trip['id'],
            'seat_count' => 1,
            'boarding_stop_id' => $this->trip['stops'][$stop]['id'],
        ])->assertCreated()->json('booking');
        Sanctum::actingAs($this->driverUser);
        $this->postJson("/api/bookings/{$booking['id']}/accept")->assertOk();

        return $booking + ['user' => $user];
    }

    private function at(CarbonImmutable $time, array $point): void
    {
        $this->travelTo($time);
        Sanctum::actingAs($this->driverUser);
        $this->postJson("/api/trips/{$this->trip['id']}/location", ['lat' => $point['lat'], 'lng' => $point['lng']])->assertOk();
    }

    private function start(): void
    {
        $this->travelTo($this->departure);
        Sanctum::actingAs($this->driverUser);
        $this->postJson("/api/trips/{$this->trip['id']}/start")->assertOk();
        $this->at($this->departure, self::DAKAR);
    }

    private function stop(int $position): TripStop
    {
        return TripStop::where('trip_id', $this->trip['id'])->where('position', $position)->sole();
    }

    private function notification(User $user, string $title): ?Notification
    {
        return Notification::where('user_id', $user->id)->where('title', $title)->first();
    }

    public function test_leaving_a_stop_is_recorded_and_coming_back_during_the_wait_clears_it(): void
    {
        $this->start();
        $this->assertNull($this->stop(0)->left_at);

        $this->at($this->departure->addMinutes(2), self::AFTER_DAKAR);
        $this->assertTrue($this->stop(0)->left_at->equalTo($this->departure->addMinutes(2)));

        // Revenu avant 08:35 : il attend de nouveau.
        $this->at($this->departure->addMinutes(3), self::DAKAR);
        $this->assertNull($this->stop(0)->left_at);

        // Reparti après l'attente : un retour ne change plus rien.
        $this->at($this->departure->addMinutes(6), self::AFTER_DAKAR);
        $this->at($this->departure->addMinutes(7), self::DAKAR);
        $this->assertTrue($this->stop(0)->left_at->equalTo($this->departure->addMinutes(6)));
    }

    public function test_leaving_before_the_end_of_the_wait_warns_the_driver_and_the_passenger(): void
    {
        $awa = $this->passenger('Awa Ndiaye');
        $this->start();

        $this->at($this->departure->addMinutes(2), self::AFTER_DAKAR);

        $toPassenger = $this->notification($awa['user'], '🚗 Le chauffeur est reparti sans vous');
        $this->assertNotNull($toPassenger);
        $this->assertStringContainsString('Il a quitté Dakar à 08:32, avant la fin de l’attente (08:35)', $toPassenger->payload['body']);
        $this->assertSame($awa['id'], $toPassenger->payload['booking_id']);

        $toDriver = $this->notification($this->driverUser, '⚠️ Vous avez quitté Dakar trop tôt');
        $this->assertNotNull($toDriver);
        $this->assertStringContainsString('Pas encore à bord : Awa Ndiaye', $toDriver->payload['body']);

        // Parti trop tôt, il ne peut plus la déclarer absente.
        $this->travelTo($this->departure->addMinutes(10));
        $this->postJson("/api/bookings/{$awa['id']}/no-show")
            ->assertUnprocessable()
            ->assertJsonFragment(['message' => "Vous avez quitté Dakar à 08:32, avant la fin de l'attente (08:35) : ce passager ne peut pas être déclaré absent."]);
    }

    public function test_after_waiting_the_full_delay_the_driver_can_declare_the_absence_on_the_road(): void
    {
        $awa = $this->passenger('Awa Ndiaye');
        $this->start();

        $this->at($this->departure->addMinutes(6), self::AFTER_DAKAR);

        $toPassenger = $this->notification($awa['user'], '🚗 Le chauffeur est reparti');
        $this->assertStringContainsString('Il vous a attendu à Dakar jusqu’à 08:35, puis a repris la route.', $toPassenger->payload['body']);
        $this->assertNull($this->notification($this->driverUser, '⚠️ Vous avez quitté Dakar trop tôt'));

        // Plus loin sur la route, l'attente reste prouvée.
        $this->at($this->departure->addMinutes(12), self::AFTER_RUFISQUE);
        $this->postJson("/api/bookings/{$awa['id']}/no-show")->assertOk()->assertJsonPath('booking.status', Booking::STATUS_NO_SHOW);
    }

    public function test_at_the_end_passengers_who_never_boarded_are_absent_or_missed(): void
    {
        $awa = $this->passenger('Awa Ndiaye');        // Dakar : le chauffeur l'attend jusqu'au bout.
        $moussa = $this->passenger('Moussa Diop', 1); // Rufisque : il repart trop tôt.
        $fatou = $this->passenger('Fatou Sow');       // À bord, billet scanné.
        $ibou = $this->passenger('Ibrahima Fall');    // Non scanné, mais a voyagé.
        $this->start();

        Sanctum::actingAs($this->driverUser);
        $this->postJson("/api/trips/{$this->trip['id']}/board-passenger", ['code' => $fatou['departure_code']])->assertOk();
        $this->at($this->departure->addMinutes(6), self::AFTER_DAKAR);

        $rufisqueAt = CarbonImmutable::parse($this->trip['stops'][1]['scheduled_at']);
        $this->at($rufisqueAt, self::RUFISQUE);
        $this->at($rufisqueAt->addMinutes(2), self::AFTER_RUFISQUE);
        $this->at($rufisqueAt->addMinutes(50), self::THIES);

        $this->postJson("/api/trips/{$this->trip['id']}/complete", [
            'not_boarded_booking_ids' => [$awa['id'], $moussa['id']],
        ])->assertOk();

        $this->assertSame(Booking::STATUS_NO_SHOW, Booking::find($awa['id'])->status);
        $this->assertNotNull(Booking::find($awa['id'])->no_show_at);
        $this->assertSame(Booking::STATUS_MISSED, Booking::find($moussa['id'])->status);
        $this->assertSame(Booking::STATUS_COMPLETED, Booking::find($fatou['id'])->status);
        $this->assertSame(Booking::STATUS_COMPLETED, Booking::find($ibou['id'])->status);

        // Gains : seulement pour ceux qui ont voyagé.
        $credited = Transaction::where('type', 'payment')->pluck('booking_id')->all();
        $this->assertEqualsCanonicalizing([$fatou['id'], $ibou['id']], $credited);

        // L'absence compte dans la fiabilité, le trajet manqué non.
        $this->assertSame(1, ReputationScore::where('user_id', $awa['user']->id)->value('no_show_count'));
        $this->assertSame(0, (int) ReputationScore::where('user_id', $moussa['user']->id)->value('no_show_count'));

        $this->assertStringContainsString(
            "Le chauffeur vous a attendu à Dakar jusqu'à 08:35",
            $this->notification($awa['user'], '🚫 Absence signalée')->payload['body'],
        );
        $this->assertStringContainsString(
            'Aucune pénalité pour vous',
            $this->notification($moussa['user'], '🚗 Trajet manqué')->payload['body'],
        );
    }

    public function test_a_stop_the_driver_never_reached_makes_the_booking_missed(): void
    {
        $moussa = $this->passenger('Moussa Diop', 1);
        $this->start();
        // GPS coupé après Dakar : rien ne prouve son passage à Rufisque.
        $this->travelTo($this->departure->addHours(2));

        Sanctum::actingAs($this->driverUser);
        $this->postJson("/api/trips/{$this->trip['id']}/complete", ['not_boarded_booking_ids' => [$moussa['id']]])->assertOk();

        $this->assertSame(Booking::STATUS_MISSED, Booking::find($moussa['id'])->status);
    }
}
