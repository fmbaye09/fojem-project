<?php

namespace Tests\Feature;

use App\Models\AdminRole;
use App\Models\AdminUser;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class AdminAuthTest extends TestCase
{
    use RefreshDatabase;

    private function makeAdmin(string $roleName = AdminRole::SUPPORT, bool $active = true): AdminUser
    {
        $role = AdminRole::firstOrCreate(['name' => $roleName]);

        return AdminUser::create([
            'full_name' => 'Test Admin',
            'email' => 'admin@fojem.sn',
            'password_hash' => Hash::make('password123'),
            'role_id' => $role->id,
            'is_active' => $active,
        ]);
    }

    public function test_an_admin_can_login_and_receives_a_token_scoped_to_the_admin_ability(): void
    {
        $this->makeAdmin();

        $response = $this->postJson('/api/admin/auth/login', [
            'email' => 'admin@fojem.sn',
            'password' => 'password123',
        ]);

        $response->assertOk()->assertJsonStructure(['admin', 'token']);

        $token = $response->json('token');

        // A regular /api/auth/* users token would not carry the "admin"
        // ability, so /api/admin/* must reject requests without it - here
        // we check the happy path: this admin token is accepted.
        $me = $this->getJson('/api/admin/auth/me', ['Authorization' => "Bearer {$token}"]);
        $me->assertOk();
        $this->assertEquals('support', $me->json('role'));
    }

    public function test_login_fails_for_wrong_password(): void
    {
        $this->makeAdmin();

        $this->postJson('/api/admin/auth/login', [
            'email' => 'admin@fojem.sn',
            'password' => 'wrong-password',
        ])->assertUnprocessable();
    }

    public function test_login_fails_for_a_deactivated_admin(): void
    {
        $this->makeAdmin(active: false);

        $this->postJson('/api/admin/auth/login', [
            'email' => 'admin@fojem.sn',
            'password' => 'password123',
        ])->assertUnprocessable();
    }

    public function test_admin_token_is_issued_with_an_8_hour_expiration(): void
    {
        $admin = $this->makeAdmin();

        $login = $this->postJson('/api/admin/auth/login', [
            'email' => 'admin@fojem.sn',
            'password' => 'password123',
        ]);
        $token = $login->json('token');

        $this->getJson('/api/admin/auth/me', ['Authorization' => "Bearer {$token}"])->assertOk();

        $tokenId = explode('|', $token)[0];
        $accessToken = $admin->tokens()->findOrFail($tokenId);
        $this->assertNotNull($accessToken->expires_at, 'Admin tokens must have an expiration - a dashboard session should never last forever.');
        $this->assertTrue($accessToken->expires_at->between(now()->addHours(7), now()->addHours(9)));

        // Simulate the token having expired instead of relying on time-travel
        // semantics interacting with Sanctum's internal now() calls.
        $accessToken->forceFill(['expires_at' => now()->subMinute()])->save();
        // Laravel's RequestGuard caches the resolved user on the guard
        // instance for the lifetime of the container; a real second HTTP
        // request always gets a fresh guard, but two simulated calls in the
        // same test share one, so force re-resolution here.
        $this->app['auth']->forgetGuards();
        $this->getJson('/api/admin/auth/me', ['Authorization' => "Bearer {$token}"])->assertStatus(401);
    }

    public function test_a_users_token_cannot_access_admin_routes(): void
    {
        $user = \App\Models\User::factory()->create();
        \App\Models\Wallet::create(['user_id' => $user->id]);
        $token = $user->createToken('device')->plainTextToken;

        // Sanctum's "admin" guard resolves the token's tokenable model
        // through the guard's configured provider (AdminUser); a users
        // token's tokenable is a User, so the guard treats the request as
        // unauthenticated (401) rather than merely unauthorized.
        $this->getJson('/api/admin/auth/me', ['Authorization' => "Bearer {$token}"])
            ->assertStatus(401);
    }
}
