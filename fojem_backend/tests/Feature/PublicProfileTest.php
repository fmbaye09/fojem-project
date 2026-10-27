<?php

namespace Tests\Feature;

use App\Models\Driver;
use App\Models\User;
use App\Models\Wallet;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class PublicProfileTest extends TestCase
{
    use RefreshDatabase;

    public function test_a_users_public_profile_exposes_only_minimal_fields(): void
    {
        $viewer = User::factory()->create();
        $target = User::factory()->create([
            'full_name' => 'Fatou Ndiaye',
            'email' => 'fatou@example.sn',
        ]);

        Sanctum::actingAs($viewer);
        $response = $this->getJson("/api/users/{$target->id}");

        $response->assertOk();
        $response->assertJson([
            'user' => [
                'id' => $target->id,
                'full_name' => 'Fatou Ndiaye',
            ],
        ]);
        $response->assertJsonMissing(['email' => 'fatou@example.sn']);
        $this->assertArrayNotHasKey('email', $response->json('user'));
    }

    public function test_a_drivers_public_profile_exposes_rating_and_recent_reviews(): void
    {
        $viewer = User::factory()->create();
        $driverUser = User::factory()->create(['is_driver' => true]);
        Wallet::create(['user_id' => $driverUser->id]);
        $driver = Driver::create([
            'user_id' => $driverUser->id,
            'verification_status' => Driver::STATUS_APPROVED,
            'average_rating' => 4.7,
            'total_trips_completed' => 5,
        ]);

        Sanctum::actingAs($viewer);
        $response = $this->getJson("/api/drivers/{$driverUser->id}");

        $response->assertOk();
        $response->assertJson([
            'driver' => [
                'id' => $driver->id,
                'average_rating' => '4.70',
                'total_trips_completed' => 5,
            ],
        ]);
        $this->assertArrayHasKey('recent_reviews', $response->json('driver'));
    }
}
