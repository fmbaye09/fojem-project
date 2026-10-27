<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\Wallet;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class ProfileTest extends TestCase
{
    use RefreshDatabase;

    public function test_a_user_can_update_their_full_name(): void
    {
        $user = User::factory()->create(['full_name' => 'Ancien Nom']);
        Wallet::create(['user_id' => $user->id]);
        Sanctum::actingAs($user);

        $response = $this->patchJson('/api/profile', ['full_name' => 'Nouveau Nom']);

        $response->assertOk();
        $this->assertEquals('Nouveau Nom', $response->json('user.full_name'));
    }

    public function test_a_user_can_upload_a_profile_photo(): void
    {
        Storage::fake('public');
        $user = User::factory()->create();
        Wallet::create(['user_id' => $user->id]);
        Sanctum::actingAs($user);

        $response = $this->postJson('/api/profile/photo', [
            'photo' => UploadedFile::fake()->image('avatar.jpg'),
        ]);

        $response->assertOk();
        $this->assertNotNull($response->json('user.profile_photo_url'));
    }
}
