<?php

namespace Tests\Feature;

use App\Models\Driver;
use App\Models\MeetingPlace;
use App\Models\User;
use App\Models\Vehicle;
use App\Models\Wallet;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Arrêts suggérés au chauffeur qui publie : ceux que d'autres trajets ont
 * déjà utilisés sur sa route, puis les lieux connus d'OpenStreetMap.
 */
class MeetingPointSuggestionTest extends TestCase
{
    use RefreshDatabase;

    private const DAKAR = ['name' => 'Dakar', 'address' => 'Gare des Pompiers, Dakar', 'lat' => 14.6800, 'lng' => -17.4380];
    private const RUFISQUE = ['name' => 'Rufisque', 'address' => 'Péage de Rufisque', 'lat' => 14.7160, 'lng' => -17.2730];
    /** Sur la ligne Dakar → Thiès, aux 3/5 du chemin. */
    private const SEBIKOTANE = ['name' => 'Sébikotane', 'address' => 'Carrefour Sébikotane', 'lat' => 14.7466, 'lng' => -17.1308];
    private const MBOUR = ['name' => 'Mbour', 'address' => 'Gare routière de Mbour', 'lat' => 14.4200, 'lng' => -16.9700];
    private const THIES = ['name' => 'Thiès', 'address' => 'Gare routière de Thiès', 'lat' => 14.7910, 'lng' => -16.9260];

    private User $driverUser;

    protected function setUp(): void
    {
        parent::setUp();
        $this->driverUser = User::factory()->create(['is_driver' => true]);
        Wallet::create(['user_id' => $this->driverUser->id]);
        $driver = Driver::create(['user_id' => $this->driverUser->id, 'verification_status' => Driver::STATUS_APPROVED]);
        Vehicle::create([
            'driver_id' => $driver->id,
            'plate_number' => 'DK-8080-MP',
            'brand' => 'Peugeot',
            'model' => '508',
            'color' => 'Gris',
            'seat_count' => 6,
        ]);
    }

    private function publish(array $stops): array
    {
        Sanctum::actingAs($this->driverUser);

        return $this->postJson('/api/trips', [
            'vehicle_id' => $this->driverUser->driver->vehicles()->first()->id,
            'departure_type' => 'scheduled',
            'scheduled_at' => CarbonImmutable::now()->addDay()->setTime(8, 30)->toIso8601String(),
            'price_per_seat' => 3000,
            'seats_available' => 4,
            'stops' => $stops,
        ])->assertCreated()->json('trip');
    }

    private function suggest(array ...$points): \Illuminate\Testing\TestResponse
    {
        Sanctum::actingAs($this->driverUser);
        $param = implode(';', array_map(fn (array $p) => "{$p['lat']},{$p['lng']}", $points));

        return $this->getJson('/api/meeting-points/suggestions?points='.urlencode($param));
    }

    public function test_stops_other_trips_used_on_the_route_are_suggested_in_route_order(): void
    {
        $first = $this->publish([self::DAKAR, self::RUFISQUE, self::THIES]);
        $this->publish([self::DAKAR, self::RUFISQUE, self::THIES]);
        $this->publish([self::DAKAR, self::SEBIKOTANE, self::THIES]);
        $this->publish([self::DAKAR, self::MBOUR]);

        // Un passager est monté à Rufisque.
        Sanctum::actingAs(User::factory()->create());
        $booking = $this->postJson('/api/bookings', ['trip_id' => $first['id'], 'seat_count' => 1, 'boarding_stop_id' => $first['stops'][1]['id']])
            ->assertCreated()->json('booking');
        Sanctum::actingAs($this->driverUser);
        $this->postJson("/api/bookings/{$booking['id']}/accept")->assertOk();

        $suggestions = $this->suggest(self::DAKAR, self::THIES)->assertOk()->json('suggestions');

        // Mbour est loin de la route ; Dakar et Thiès sont déjà les points du chauffeur.
        $this->assertSame(['Rufisque', 'Sébikotane'], array_column($suggestions, 'name'));
        $this->assertSame('frequent', $suggestions[0]['kind']);
        $this->assertSame('Péage de Rufisque', $suggestions[0]['address']);
        $this->assertSame(2, $suggestions[0]['trips_count']);
        $this->assertSame(1, $suggestions[0]['passengers_count']);
        $this->assertSame(1, $suggestions[1]['trips_count']);
        $this->assertLessThan($suggestions[1]['km_from_start'], $suggestions[0]['km_from_start']);

        // Rufisque déjà choisi : il ne se propose plus.
        $this->assertSame(['Sébikotane'], array_column($this->suggest(self::DAKAR, self::RUFISQUE, self::THIES)->json('suggestions'), 'name'));
    }

    /** Réponse d'Overpass pour le pays, avec ce qu'un import doit trier. */
    private function countryPlaces(): array
    {
        return ['elements' => [
            ['type' => 'node', 'id' => 1, 'lat' => 14.7244, 'lon' => -17.2332, 'tags' => ['amenity' => 'bus_station', 'name' => 'Gare routière de Bargny']],
            // À 1 km de la gare : trop près, la gare l'emporte.
            ['type' => 'way', 'id' => 2, 'center' => ['lat' => 14.7262, 'lon' => -17.2240], 'tags' => ['amenity' => 'fuel', 'brand' => 'Total']],
            ['type' => 'node', 'id' => 3, 'lat' => 14.7466, 'lon' => -17.1308, 'tags' => ['barrier' => 'toll_booth']],
            ['type' => 'way', 'id' => 4, 'center' => ['lat' => 14.7710, 'lon' => -17.0180], 'tags' => ['junction' => 'roundabout', 'name' => 'Rond-point Keur Mbir', 'addr:city' => 'Pout']],
            // Sans nom ni marque : inutilisable comme point de rendez-vous.
            ['type' => 'node', 'id' => 5, 'lat' => 14.7600, 'lon' => -17.0700, 'tags' => ['amenity' => 'fuel']],
            // Loin de la route.
            ['type' => 'node', 'id' => 6, 'lat' => 14.4200, 'lon' => -16.9700, 'tags' => ['amenity' => 'bus_station', 'name' => 'Gare routière de Mbour']],
            // Localités : elles situent les lieux sans nom, et ne sont pas des lieux de rendez-vous.
            ['type' => 'node', 'id' => 7, 'lat' => 14.7450, 'lon' => -17.1350, 'tags' => ['place' => 'town', 'name' => 'Sébikotane']],
            ['type' => 'node', 'id' => 8, 'lat' => 14.7470, 'lon' => -17.1276, 'tags' => ['place' => 'village', 'name' => 'Keur Ndiaye']],
            ['type' => 'node', 'id' => 9, 'lat' => 14.7250, 'lon' => -17.2300, 'tags' => ['place' => 'town', 'name' => 'Bargny']],
        ]];
    }

    private function fakeOverpass(\Illuminate\Http\Client\ResponseSequence $responses): void
    {
        config(['services.overpass.url' => 'https://overpass.test/api/interpreter']);
        Http::fake(['overpass.test/*' => $responses]);
    }

    public function test_openstreetmap_places_fill_in_spaced_along_the_route(): void
    {
        $this->fakeOverpass(Http::sequence()->push($this->countryPlaces()));
        $this->artisan('fojem:import-meeting-places', ['--attempts' => 1])
            ->expectsOutputToContain('5 importés, 0 retirés')
            ->assertSuccessful();

        $suggestions = $this->suggest(self::DAKAR, self::THIES)->assertOk()->json('suggestions');

        // Le péage sans nom prend celui de la ville voisine plutôt que du hameau plus proche.
        $this->assertSame(['Gare routière de Bargny', 'Péage de Sébikotane', 'Rond-point Keur Mbir'], array_column($suggestions, 'name'));
        $this->assertNull($suggestions[0]['address']);
        $this->assertSame(['gare_routiere', 'peage', 'rond_point'], array_column($suggestions, 'kind'));
        $this->assertSame('Rond-point Keur Mbir, Pout', $suggestions[2]['address']);

        // Les suggestions lisent la base : OpenStreetMap n'a servi qu'à l'import.
        Http::assertSentCount(1);
    }

    public function test_an_import_updates_places_and_survives_an_unavailable_server(): void
    {
        $this->fakeOverpass(Http::sequence()
            ->push($this->countryPlaces())
            ->push('# 502 Gateway Timeout', 502)
            ->push(['elements' => [$this->countryPlaces()['elements'][0]]]));

        $this->artisan('fojem:import-meeting-places', ['--attempts' => 1])->assertSuccessful();

        // Le serveur saturé ne vide pas la base.
        $this->artisan('fojem:import-meeting-places', ['--attempts' => 1])->assertFailed();
        $this->assertSame(5, MeetingPlace::count());

        // Un lieu disparu d'OSM disparaît aussi des suggestions.
        $this->artisan('fojem:import-meeting-places', ['--attempts' => 1])
            ->expectsOutputToContain('1 importés, 4 retirés')
            ->assertSuccessful();
        $this->assertSame(['Gare routière de Bargny'], array_column($this->suggest(self::DAKAR, self::THIES)->json('suggestions'), 'name'));
    }

    public function test_only_drivers_with_valid_points_get_suggestions(): void
    {
        Sanctum::actingAs(User::factory()->create());
        $this->getJson('/api/meeting-points/suggestions?points=14.68,-17.438;14.791,-16.926')->assertForbidden();

        $this->suggest(self::DAKAR)->assertUnprocessable();
        Sanctum::actingAs($this->driverUser);
        $this->getJson('/api/meeting-points/suggestions?points=abc;14.791,-16.926')->assertUnprocessable();
    }
}
