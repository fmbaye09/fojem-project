<?php

namespace Tests\Feature;

use App\Models\Booking;
use App\Models\Driver;
use App\Models\Notification;
use App\Models\Trip;
use App\Models\TripStop;
use App\Models\User;
use App\Models\Vehicle;
use App\Models\Wallet;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Un passager propose un point de rendez-vous hors des arrêts du trajet ; le
 * chauffeur l'accepte en voyant le détour, et l'arrêt s'ajoute au trajet.
 */
class StopProposalTest extends TestCase
{
    use RefreshDatabase;

    private const DAKAR = ['name' => 'Dakar', 'address' => 'Gare des Pompiers, Dakar', 'lat' => 14.6800, 'lng' => -17.4380];
    private const RUFISQUE = ['name' => 'Rufisque', 'address' => 'Péage de Rufisque', 'lat' => 14.7160, 'lng' => -17.2730];
    private const THIES = ['name' => 'Thiès', 'address' => 'Gare routière de Thiès', 'lat' => 14.7910, 'lng' => -16.9260];

    /** Entre Dakar et Rufisque, à 1,6 km de la ligne droite. */
    private const MBAO = ['name' => 'Mbao', 'address' => 'Station Mbao', 'lat' => 14.7130, 'lng' => -17.3555];

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
            'plate_number' => 'DK-7070-SP',
            'brand' => 'Toyota',
            'model' => 'Hiace',
            'color' => 'Blanc',
            'seat_count' => 15,
        ]);
    }

    private function publish(): array
    {
        Sanctum::actingAs($this->driverUser);

        return $this->postJson('/api/trips', [
            'vehicle_id' => $this->driverUser->driver->vehicles()->first()->id,
            'departure_type' => 'scheduled',
            'scheduled_at' => $this->departure->toIso8601String(),
            'price_per_seat' => 3000,
            'seats_available' => 3,
            'stops' => [self::DAKAR, self::RUFISQUE, self::THIES],
        ])->assertCreated()->json('trip');
    }

    /** OSRM : 15 min jusqu'au point proposé, 15 min ensuite, 25 min en direct → 5 min de détour. */
    private function fakeRoad(): void
    {
        config(['services.osrm.url' => 'https://osrm.test']);
        Http::fake(['osrm.test/*' => function ($request) {
            $points = substr_count(explode('?', $request->url())[0], ';') + 1;

            return Http::response(['code' => 'Ok', 'routes' => [['legs' => $points === 3
                ? [['duration' => 900, 'distance' => 9000], ['duration' => 900, 'distance' => 9000]]
                : [['duration' => 1500, 'distance' => 16000]]]]]);
        }]);
    }

    private function propose(array $trip, User $passenger, array $point, string $role = 'boarding', array $extra = []): \Illuminate\Testing\TestResponse
    {
        Sanctum::actingAs($passenger);

        return $this->postJson('/api/bookings', [
            'trip_id' => $trip['id'],
            'seat_count' => 1,
            'proposed_stop' => ['role' => $role, 'lat' => $point['lat'], 'lng' => $point['lng'], 'name' => $point['name'], 'address' => $point['address']],
        ] + $extra);
    }

    private function accept(string $bookingId): \Illuminate\Testing\TestResponse
    {
        Sanctum::actingAs($this->driverUser);

        return $this->postJson("/api/bookings/{$bookingId}/accept");
    }

    public function test_the_passenger_sees_the_detour_time_and_price_before_proposing(): void
    {
        $this->fakeRoad();
        $trip = $this->publish();
        [$dakar, $rufisque] = $trip['stops'];
        Sanctum::actingAs(User::factory()->create());

        $proposal = $this->getJson("/api/trips/{$trip['id']}/stop-proposal?".http_build_query(['role' => 'boarding'] + self::MBAO))
            ->assertOk()
            ->json('proposal');

        $this->assertSame($dakar['id'], $proposal['after_stop_id']);
        $this->assertSame($rufisque['id'], $proposal['before_stop_id']);
        $this->assertSame(5, $proposal['detour_minutes']);
        $this->assertSame('Mbao', $proposal['name']);
        $this->assertTrue(CarbonImmutable::parse($proposal['scheduled_at'])->equalTo($this->departure->addMinutes(15)));
        $this->assertGreaterThan(0, (float) $proposal['price_from_origin']);
        $this->assertLessThanOrEqual((float) $rufisque['price_from_origin'], (float) $proposal['price_from_origin']);
    }

    public function test_a_point_next_to_a_stop_or_far_from_the_route_is_refused(): void
    {
        $trip = $this->publish();
        Sanctum::actingAs(User::factory()->create());
        $preview = fn (array $point) => $this->getJson("/api/trips/{$trip['id']}/stop-proposal?".http_build_query(['role' => 'boarding'] + $point));

        // 500 m du péage de Rufisque : autant choisir Rufisque.
        $preview(['lat' => 14.7200, 'lng' => -17.2710])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('proposed_stop')
            ->assertJsonFragment(['Le chauffeur passe déjà à « Rufisque », à 500 m : choisissez cet arrêt.']);

        // Mbour : à des dizaines de km de la route.
        $message = $preview(['lat' => 14.4200, 'lng' => -16.9700])->assertUnprocessable()->json('errors.proposed_stop.0');
        $this->assertStringContainsString('trop loin de la route', $message);
    }

    public function test_the_request_carries_the_proposal_and_its_price(): void
    {
        $this->fakeRoad();
        $trip = $this->publish();
        $passenger = User::factory()->create();

        $booking = $this->propose($trip, $passenger, self::MBAO)->assertCreated()->json('booking');

        $this->assertNull($booking['boarding_stop_id']);
        $this->assertSame($trip['stops'][2]['id'], $booking['alighting_stop_id']);
        $this->assertSame('Mbao', $booking['proposed_stop']['name']);
        $this->assertSame(5, $booking['proposed_stop']['detour_minutes']);
        $this->assertEquals(3000 - (float) $booking['proposed_stop']['price_from_origin'], (float) $booking['price_charged']);

        $notification = Notification::where('user_id', $this->driverUser->id)->where('type', Notification::TYPE_BOOKING_NEW)->sole();
        $this->assertStringContainsString('Nouvel arrêt proposé : Mbao (détour d\'environ 5 min)', $notification->payload['body']);
    }

    public function test_accepting_adds_the_stop_and_delays_the_next_ones(): void
    {
        $this->fakeRoad();
        $trip = $this->publish();
        [, $rufisque, $thies] = $trip['stops'];

        // Awa monte à Rufisque, après le futur arrêt.
        $awa = User::factory()->create();
        Sanctum::actingAs($awa);
        $awaBooking = $this->postJson('/api/bookings', ['trip_id' => $trip['id'], 'seat_count' => 1, 'boarding_stop_id' => $rufisque['id']])
            ->assertCreated()->json('booking');
        $this->accept($awaBooking['id'])->assertOk();

        $passenger = User::factory()->create();
        $booking = $this->propose($trip, $passenger, self::MBAO)->assertCreated()->json('booking');
        $accepted = $this->accept($booking['id'])->assertOk()->json('booking');

        $stops = TripStop::where('trip_id', $trip['id'])->orderBy('position')->get();
        $this->assertSame(['Dakar', 'Mbao', 'Rufisque', 'Thiès'], $stops->pluck('name')->all());
        $this->assertSame([0, 1, 2, 3], $stops->pluck('position')->all());
        $mbao = $stops[1];
        $this->assertSame('Station Mbao', $mbao->address);
        $this->assertTrue($mbao->scheduled_at->equalTo($this->departure->addMinutes(15)));
        $this->assertTrue($stops[2]->scheduled_at->equalTo(CarbonImmutable::parse($rufisque['scheduled_at'])->addMinutes(5)));
        $this->assertTrue($stops[3]->scheduled_at->equalTo(CarbonImmutable::parse($thies['scheduled_at'])->addMinutes(5)));

        $this->assertSame(Booking::STATUS_CONFIRMED, $accepted['status']);
        $this->assertSame($mbao->id, $accepted['boarding_stop_id']);
        $this->assertSame($mbao->id, $accepted['proposed_stop']['inserted_stop_id']);
        $this->assertEquals(3000 - (float) $mbao->price_from_origin, (float) $accepted['price_charged']);
        $this->assertEquals(1, Trip::find($trip['id'])->seats_available);

        $notice = Notification::where('user_id', $awa->id)->where('title', '🕒 Horaire modifié')->sole();
        $this->assertStringContainsString('ajoute un arrêt à Mbao', $notice->payload['body']);
        $this->assertStringContainsString('Rufisque vers '.$stops[2]->scheduled_at->format('H:i').', environ 5 min plus tard', $notice->payload['body']);
        $this->assertSame($awaBooking['id'], $notice->payload['booking_id']);
    }

    public function test_cancelling_removes_a_stop_nobody_else_uses(): void
    {
        $trip = $this->publish();
        $passenger = User::factory()->create();
        $booking = $this->propose($trip, $passenger, self::MBAO)->assertCreated()->json('booking');
        $this->accept($booking['id'])->assertOk();
        $this->assertSame(4, TripStop::where('trip_id', $trip['id'])->count());

        Sanctum::actingAs($passenger);
        $this->postJson("/api/bookings/{$booking['id']}/cancel")->assertOk();

        $stops = TripStop::where('trip_id', $trip['id'])->orderBy('position')->get();
        $this->assertSame(['Dakar', 'Rufisque', 'Thiès'], $stops->pluck('name')->all());
        $this->assertSame([0, 1, 2], $stops->pluck('position')->all());
    }

    public function test_a_stop_cannot_be_added_once_the_trip_has_left(): void
    {
        $trip = $this->publish();
        $booking = $this->propose($trip, User::factory()->create(), self::MBAO)->assertCreated()->json('booking');

        $this->travelTo($this->departure);
        Sanctum::actingAs($this->driverUser);
        $this->postJson("/api/trips/{$trip['id']}/start")->assertOk();

        $this->accept($booking['id'])->assertUnprocessable();
        $this->assertSame(3, TripStop::where('trip_id', $trip['id'])->count());
        $this->assertSame(Booking::STATUS_PENDING_DRIVER, Booking::find($booking['id'])->status);
    }

    public function test_the_proposed_point_must_stay_between_boarding_and_alighting(): void
    {
        $trip = $this->publish();

        // Descendre à Mbao en montant à Rufisque : Mbao est avant.
        $this->propose($trip, User::factory()->create(), self::MBAO, 'alighting', ['boarding_stop_id' => $trip['stops'][1]['id']])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('alighting_stop_id');

        // Descendre à Mbao en montant à Dakar : possible.
        $this->propose($trip, User::factory()->create(), self::MBAO, 'alighting')
            ->assertCreated()
            ->assertJsonPath('booking.alighting_stop_id', null)
            ->assertJsonPath('booking.boarding_stop_id', $trip['stops'][0]['id']);
    }
}
