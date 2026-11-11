<?php

namespace Tests\Feature;

use App\Models\MeetingPlace;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Recherche de lieux de rendez-vous par leur nom, dans les deux applis.
 */
class PlaceSearchTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $places = [
            ['gare_routiere', 'Gare Routière de Thiès', 14.7910, -16.9260],
            ['station', 'Total Thiès Nord', 14.8010, -16.9300],
            ['gare_routiere', 'Gare routière de Pikine', 14.7500, -17.3900],
            ['gare_routiere', 'Gare routière de Rufisque Est', 14.7160, -17.2700],
            ['peage', 'Péage de Dalifort', 14.7400, -17.4100],
            ['peage', 'Péage de Dalifort', 14.7402, -17.4098],
            ['rond_point', 'Rond-point de Saint-Louis', 16.0200, -16.4900],
        ];
        foreach ($places as $i => [$kind, $name, $lat, $lng]) {
            MeetingPlace::create(['osm_id' => 'node/'.$i, 'kind' => $kind, 'name' => $name, 'lat' => $lat, 'lng' => $lng]);
        }
    }

    private function search(array $params)
    {
        Sanctum::actingAs(User::factory()->create());

        return $this->getJson('/api/places/search?'.http_build_query($params));
    }

    public function test_matches_without_accents_case_or_word_order(): void
    {
        $this->search(['q' => 'gare routiere THIES'])
            ->assertOk()
            ->assertJsonPath('places.0.name', 'Gare Routière de Thiès')
            ->assertJsonCount(1, 'places');

        $this->search(['q' => 'thies gare'])->assertJsonPath('places.0.name', 'Gare Routière de Thiès');
    }

    public function test_hyphens_match_spaces(): void
    {
        $this->search(['q' => 'saint louis'])->assertJsonPath('places.0.name', 'Rond-point de Saint-Louis');
    }

    public function test_bus_stations_come_before_fuel_stations(): void
    {
        $names = $this->search(['q' => 'thies'])->json('places.*.name');

        $this->assertSame(['Gare Routière de Thiès', 'Total Thiès Nord'], $names);
    }

    public function test_same_name_points_are_listed_once(): void
    {
        $this->search(['q' => 'dalifort'])->assertJsonCount(1, 'places');
    }

    public function test_closest_place_first_when_the_position_is_known(): void
    {
        $names = $this->search(['q' => 'gare routiere de', 'lat' => 14.7150, 'lng' => -17.2710])->json('places.*.name');

        $this->assertSame('Gare routière de Rufisque Est', $names[0]);
    }

    public function test_requires_a_signed_in_user_and_a_real_query(): void
    {
        $this->getJson('/api/places/search?q=thies')->assertUnauthorized();
        $this->search(['q' => 'a'])->assertUnprocessable();
    }
}
