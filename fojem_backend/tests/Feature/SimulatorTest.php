<?php

namespace Tests\Feature;

use App\Models\AdminPermission;
use App\Models\AdminRole;
use App\Models\AdminUser;
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
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Le simulateur du dashboard : des comptes simulés qui passent par l'API
 * publique, un scénario qu'on peut vieillir, et un nettoyage complet.
 */
class SimulatorTest extends TestCase
{
    use RefreshDatabase;

    private const DAKAR = ['name' => 'Dakar', 'address' => 'Gare des Pompiers, Dakar', 'lat' => 14.6800, 'lng' => -17.4380];
    private const RUFISQUE = ['name' => 'Rufisque', 'address' => 'Péage de Rufisque', 'lat' => 14.7160, 'lng' => -17.2730];
    private const THIES = ['name' => 'Thiès', 'address' => 'Gare routière de Thiès', 'lat' => 14.7910, 'lng' => -16.9260];

    private AdminUser $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $role = AdminRole::create(['name' => 'super_'.uniqid()]);
        AdminPermission::create(['role_id' => $role->id, 'resource' => '*', 'action' => 'edit']);
        $this->admin = AdminUser::create([
            'full_name' => 'Admin',
            'email' => uniqid().'@fojem.sn',
            'password_hash' => Hash::make('password123'),
            'role_id' => $role->id,
            'is_active' => true,
        ]);
    }

    private function asAdmin(): void
    {
        Sanctum::actingAs($this->admin, ['admin'], 'admin');
    }

    /** @return array{id: string, token: string, vehicle_id: ?string, full_name: string} */
    private function actor(string $role, array $extra = []): array
    {
        $this->asAdmin();

        return $this->postJson('/api/admin/simulator/actors', ['role' => $role] + $extra)->assertCreated()->json('actor');
    }

    /** Appel de l'API publique avec le jeton d'un acteur, comme le fait le dashboard. */
    private function as(array $actor, string $method, string $uri, array $data = []): \Illuminate\Testing\TestResponse
    {
        $this->app['auth']->forgetGuards();

        return $this->withToken($actor['token'])->json($method, $uri, $data);
    }

    private function publish(array $driver): array
    {
        return $this->as($driver, 'POST', '/api/trips', [
            'vehicle_id' => $driver['vehicle_id'],
            'departure_type' => 'scheduled',
            'scheduled_at' => CarbonImmutable::now()->addMinutes(20)->toIso8601String(),
            'price_per_seat' => 3000,
            'seats_available' => 3,
            'stops' => [self::DAKAR, self::RUFISQUE, self::THIES],
        ])->assertCreated()->json('trip');
    }

    public function test_simulated_actors_use_the_public_api_like_the_apps(): void
    {
        $driver = $this->actor('driver', ['name' => 'Modou Seck (sim)', 'seats' => 7]);
        $passenger = $this->actor('passenger');

        $this->assertSame('Modou Seck (sim)', $driver['full_name']);
        $this->assertStringEndsWith('(sim)', $passenger['full_name']);
        $this->assertTrue(User::find($driver['id'])->is_simulated);

        $trip = $this->publish($driver);
        $booking = $this->as($passenger, 'POST', '/api/bookings', ['trip_id' => $trip['id'], 'seat_count' => 1])
            ->assertCreated()->json('booking');
        $this->as($driver, 'POST', "/api/bookings/{$booking['id']}/accept")->assertOk();
        $this->as($driver, 'POST', "/api/trips/{$trip['id']}/location", self::DAKAR)->assertOk();

        $this->assertSame(Booking::STATUS_CONFIRMED, Booking::find($booking['id'])->status);
        $this->assertNotNull(TripStop::where('trip_id', $trip['id'])->where('position', 0)->value('reached_at'));
    }

    public function test_the_simulator_only_exists_locally_and_for_admins(): void
    {
        $this->asAdmin();
        $this->getJson('/api/admin/simulator')->assertOk()->assertJsonPath('enabled', true);

        config(['simulator.enabled' => false]);
        $this->getJson('/api/admin/simulator')->assertNotFound();
        $this->postJson('/api/admin/simulator/actors', ['role' => 'driver'])->assertNotFound();

        config(['simulator.enabled' => true]);
        $this->app['env'] = 'production';
        $this->getJson('/api/admin/simulator')->assertNotFound();
        $this->app['env'] = 'testing';

        // Un compte de l'appli, même chauffeur, n'y a pas accès.
        $this->app['auth']->forgetGuards();
        Sanctum::actingAs(User::factory()->create());
        $this->getJson('/api/admin/simulator')->assertUnauthorized();
    }

    public function test_the_route_follows_the_road_or_falls_back_to_straight_lines(): void
    {
        $this->asAdmin();
        $points = '14.68,-17.438;14.716,-17.273;14.791,-16.926';

        $straight = $this->getJson("/api/admin/simulator/route?points={$points}")->assertOk();
        $straight->assertJsonPath('source', 'straight')->assertJsonCount(3, 'geometry')->assertJsonCount(2, 'legs');

        config(['services.osrm.url' => 'https://osrm.test']);
        Http::fake(['osrm.test/*' => Http::response(['code' => 'Ok', 'routes' => [[
            'geometry' => ['coordinates' => [[-17.438, 14.68], [-17.35, 14.70], [-17.273, 14.716], [-17.1, 14.75], [-16.926, 14.791]]],
            'legs' => [['duration' => 1400, 'distance' => 19000], ['duration' => 2400, 'distance' => 41000]],
        ]]])]);
        $road = $this->getJson("/api/admin/simulator/route?points={$points}")->assertOk();
        $road->assertJsonPath('source', 'osrm')->assertJsonCount(5, 'geometry')->assertJsonPath('legs.1.duration', 2400);
        $this->assertEquals([14.70, -17.35], $road->json('geometry.1'));
        Http::assertSent(fn ($request) => str_contains($request->url(), 'overview=full'));

        $this->getJson('/api/admin/simulator/route?points=14.68,-17.438')->assertUnprocessable();
    }

    public function test_a_scenario_can_be_aged_so_reminders_behave_like_a_trip_published_earlier(): void
    {
        $driver = $this->actor('driver');
        $passenger = $this->actor('passenger');
        $trip = $this->publish($driver);
        $booking = $this->as($passenger, 'POST', '/api/bookings', ['trip_id' => $trip['id'], 'seat_count' => 1])->json('booking');
        $this->as($driver, 'POST', "/api/bookings/{$booking['id']}/accept")->assertOk();

        // Publié à l'instant : pas de rappel « départ dans 20 min ».
        $this->artisan('fojem:send-reminders')->expectsOutputToContain('0 chauffeur(s), 0 passager(s)');

        $this->asAdmin();
        $this->postJson('/api/admin/simulator/backdate', ['trip_id' => $trip['id'], 'minutes' => 60])
            ->assertOk()->assertJson(['trips' => 1, 'bookings' => 1]);
        $this->assertTrue(Trip::find($trip['id'])->created_at->lessThan(now()->subMinutes(59)));

        $this->artisan('fojem:send-reminders')->expectsOutputToContain('1 chauffeur(s), 1 passager(s)');

        // Un vrai trajet ne se vieillit pas.
        $real = $this->realTrip();
        $this->postJson('/api/admin/simulator/backdate', ['trip_id' => $real->id, 'minutes' => 60])->assertUnprocessable();
    }

    public function test_notifications_of_the_scenario_are_listed_for_the_dashboard(): void
    {
        $driver = $this->actor('driver');
        $trip = $this->publish($driver);

        // Un vrai téléphone réserve le trajet simulé ; un autre compte réel n'a rien à voir.
        $realPassenger = User::factory()->create(['full_name' => 'Vrai Passager']);
        $this->app['auth']->forgetGuards();
        Sanctum::actingAs($realPassenger);
        $booking = $this->postJson('/api/bookings', ['trip_id' => $trip['id'], 'seat_count' => 1])->assertCreated()->json('booking');
        $this->as($driver, 'POST', "/api/bookings/{$booking['id']}/accept")->assertOk();
        Notification::create(['user_id' => User::factory()->create()->id, 'type' => 'system', 'title' => 'Sans rapport', 'payload' => ['body' => 'x'], 'sent_at' => now()]);

        $this->asAdmin();
        $notifications = $this->getJson('/api/admin/simulator/notifications?'.http_build_query(['trip_ids' => [$trip['id']]]))
            ->assertOk()->json('notifications');

        $byUser = collect($notifications)->groupBy('user_name');
        $this->assertTrue($byUser->has($driver['full_name']), 'nouvelle demande pour le chauffeur simulé');
        $this->assertTrue($byUser->has('Vrai Passager'), 'confirmation pour le vrai passager');
        $this->assertFalse($byUser->has(''), 'pas de compte sans nom');
        $this->assertNotContains('Sans rapport', array_column($notifications, 'title'));
        $this->assertFalse($byUser['Vrai Passager'][0]['simulated']);
    }

    public function test_reset_removes_every_simulated_account_and_gives_seats_back(): void
    {
        $driver = $this->actor('driver');
        $passenger = $this->actor('passenger');
        $trip = $this->publish($driver);
        $booking = $this->as($passenger, 'POST', '/api/bookings', ['trip_id' => $trip['id'], 'seat_count' => 1])->json('booking');
        $this->as($driver, 'POST', "/api/bookings/{$booking['id']}/accept")->assertOk();

        // Le passager simulé a aussi une place sur un vrai trajet.
        $real = $this->realTrip();
        $onReal = $this->as($passenger, 'POST', '/api/bookings', ['trip_id' => $real->id, 'seat_count' => 1])->json('booking');
        $this->app['auth']->forgetGuards();
        Sanctum::actingAs($real->driverProfile->user);
        $this->postJson("/api/bookings/{$onReal['id']}/accept")->assertOk();
        $this->assertEquals(2, $real->fresh()->seats_available);

        $this->asAdmin();
        $this->deleteJson('/api/admin/simulator')->assertOk()->assertJson(['users' => 2, 'trips' => 1]);

        $this->assertSame(0, User::withTrashed()->where('is_simulated', true)->count());
        $this->assertNull(Trip::withTrashed()->find($trip['id']));
        $this->assertSame(0, TripStop::where('trip_id', $trip['id'])->count());
        $this->assertSame(0, Booking::withTrashed()->whereIn('id', [$booking['id'], $onReal['id']])->count());
        $this->assertSame(0, DB::table('personal_access_tokens')->whereIn('tokenable_id', [$driver['id'], $passenger['id']])->count());

        // Le vrai trajet récupère sa place et garde tout le reste.
        $this->assertEquals(3, $real->fresh()->seats_available);
        $this->assertSame(3, TripStop::where('trip_id', $real->id)->count());
        $this->assertNotNull(User::find($real->driverProfile->user_id));
    }

    /** Un trajet publié par un vrai compte chauffeur. */
    private function realTrip(): Trip
    {
        $user = User::factory()->create(['is_driver' => true]);
        Wallet::create(['user_id' => $user->id]);
        $driver = Driver::create(['user_id' => $user->id, 'verification_status' => Driver::STATUS_APPROVED]);
        $vehicle = Vehicle::create([
            'driver_id' => $driver->id,
            'plate_number' => 'DK-'.random_int(1000, 9999).'-RL',
            'brand' => 'Peugeot',
            'model' => '508',
            'color' => 'Gris',
            'seat_count' => 6,
        ]);
        $this->app['auth']->forgetGuards();
        Sanctum::actingAs($user);
        $trip = $this->postJson('/api/trips', [
            'vehicle_id' => $vehicle->id,
            'departure_type' => 'scheduled',
            'scheduled_at' => CarbonImmutable::now()->addHours(3)->toIso8601String(),
            'price_per_seat' => 2500,
            'seats_available' => 3,
            'stops' => [self::DAKAR, self::RUFISQUE, self::THIES],
        ])->assertCreated()->json('trip');
        $this->asAdmin();

        return Trip::find($trip['id']);
    }
}
