<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/** A phone's push token belongs to the account currently signed in on it. */
class FcmTokenTest extends TestCase
{
    use RefreshDatabase;

    public function test_registering_a_token_detaches_it_from_the_previous_account(): void
    {
        $previous = User::factory()->create(['fcm_token' => 'device-token-1']);
        $current = User::factory()->create();

        Sanctum::actingAs($current);
        $this->postJson('/api/fcm-token', ['fcm_token' => 'device-token-1'])->assertOk();

        $this->assertSame('device-token-1', $current->fresh()->fcm_token);
        $this->assertNull($previous->fresh()->fcm_token);
    }

    public function test_logout_detaches_the_device(): void
    {
        $user = User::factory()->create(['fcm_token' => 'device-token-2']);
        $token = $user->createToken('test')->plainTextToken;

        $this->withHeader('Authorization', "Bearer $token")
            ->postJson('/api/auth/logout')
            ->assertOk();

        $this->assertNull($user->fresh()->fcm_token);
    }
}
