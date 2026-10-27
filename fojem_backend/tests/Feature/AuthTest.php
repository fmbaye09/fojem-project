<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class AuthTest extends TestCase
{
    use RefreshDatabase;

    public function test_a_user_can_register_and_receives_a_wallet(): void
    {
        $response = $this->postJson('/api/auth/register', [
            'full_name' => 'Awa Diop',
            'email' => 'awa@example.sn',
            'password' => 'password123',
            'phone_number' => '+221771234567',
            'gender' => 'female',
        ]);

        $response->assertCreated()->assertJsonStructure(['user', 'token', 'firebase_custom_token']);

        $user = User::where('email', 'awa@example.sn')->firstOrFail();
        $this->assertTrue(Hash::check('password123', $user->password_hash));
        $this->assertNotNull($user->wallet);
        $this->assertEquals(0, $user->wallet->balance);
    }

    public function test_a_user_can_login_with_correct_credentials(): void
    {
        $this->postJson('/api/auth/register', [
            'full_name' => 'Moussa Fall',
            'email' => 'moussa@example.sn',
            'password' => 'password123',
            'phone_number' => '+221781112233',
            'gender' => 'male',
        ])->assertCreated();

        $response = $this->postJson('/api/auth/login', [
            'email' => 'moussa@example.sn',
            'password' => 'password123',
        ]);

        $response->assertOk()->assertJsonStructure(['user', 'token', 'firebase_custom_token']);
    }

    public function test_login_response_includes_a_firebase_custom_token_key(): void
    {
        // The key must always be present in the JSON payload so the
        // Flutter apps have a stable contract, even when its value is
        // null (e.g. in this test environment, which has no real Firebase
        // service account key at storage/app/secrets/firebase-adminsdk.json
        // - see FirebaseTokenService and the README). We only assert
        // presence of the key here, not that it is non-null: minting a
        // real token requires a real Firebase project and is out of scope
        // for this test suite.
        $this->postJson('/api/auth/register', [
            'full_name' => 'Fatou Sow',
            'email' => 'fatou@example.sn',
            'password' => 'password123',
            'phone_number' => '+221770000010',
            'gender' => 'female',
        ])->assertCreated();

        $response = $this->postJson('/api/auth/login', [
            'email' => 'fatou@example.sn',
            'password' => 'password123',
        ]);

        $response->assertOk();
        $this->assertArrayHasKey('firebase_custom_token', $response->json());
    }

    public function test_login_fails_with_wrong_password(): void
    {
        $this->postJson('/api/auth/register', [
            'full_name' => 'Moussa Fall',
            'email' => 'moussa2@example.sn',
            'password' => 'password123',
            'phone_number' => '+221781112234',
            'gender' => 'male',
        ])->assertCreated();

        $this->postJson('/api/auth/login', [
            'email' => 'moussa2@example.sn',
            'password' => 'wrong-password',
        ])->assertUnprocessable();
    }

    public function test_become_driver_creates_a_pending_driver_profile(): void
    {
        $register = $this->postJson('/api/auth/register', [
            'full_name' => 'Ibrahima Ndiaye',
            'email' => 'ibrahima@example.sn',
            'password' => 'password123',
            'phone_number' => '+221770000009',
            'gender' => 'male',
        ]);

        $token = $register->json('token');

        $response = $this->postJson('/api/auth/become-driver', [], [
            'Authorization' => "Bearer {$token}",
        ]);

        $response->assertCreated();
        $this->assertEquals('pending', $response->json('driver.verification_status'));
    }
}
