<?php

namespace Tests\Feature;

use App\Models\AdminPermission;
use App\Models\AdminRole;
use App\Models\AdminUser;
use App\Models\AuditLog;
use App\Models\User;
use App\Models\Wallet;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class AdminUserManagementTest extends TestCase
{
    use RefreshDatabase;

    private function makeAdminWithPermission(string $resource, string $action): AdminUser
    {
        $role = AdminRole::create(['name' => 'custom_role_'.uniqid()]);
        AdminPermission::create(['role_id' => $role->id, 'resource' => $resource, 'action' => $action]);

        return AdminUser::create([
            'full_name' => 'Support Admin',
            'email' => uniqid().'@fojem.sn',
            'password_hash' => Hash::make('password123'),
            'role_id' => $role->id,
            'is_active' => true,
        ]);
    }

    public function test_admin_can_change_user_account_status_and_it_is_audited(): void
    {
        $admin = $this->makeAdminWithPermission('users', 'edit');
        Sanctum::actingAs($admin, ['admin'], 'admin');

        $user = User::factory()->create(['account_status' => 'active']);
        Wallet::create(['user_id' => $user->id]);

        $response = $this->patchJson("/api/admin/users/{$user->id}/status", [
            'account_status' => 'disabled',
        ]);

        $response->assertOk();
        $this->assertEquals('disabled', $response->json('user.account_status'));
        $this->assertDatabaseHas('users', ['id' => $user->id, 'account_status' => 'disabled']);

        $log = AuditLog::where('target_type', 'user')->where('target_id', $user->id)->first();
        $this->assertNotNull($log);
        $this->assertEquals('user.status_updated', $log->action);
        $this->assertEquals($admin->id, $log->actor_admin_id);
        $this->assertEquals('active', $log->old_value['account_status']);
        $this->assertEquals('disabled', $log->new_value['account_status']);
    }

    public function test_admin_without_the_users_edit_permission_is_forbidden(): void
    {
        $admin = $this->makeAdminWithPermission('users', 'view');
        Sanctum::actingAs($admin, ['admin'], 'admin');

        $user = User::factory()->create();
        Wallet::create(['user_id' => $user->id]);

        $this->patchJson("/api/admin/users/{$user->id}/status", [
            'account_status' => 'disabled',
        ])->assertStatus(403);
    }
}
