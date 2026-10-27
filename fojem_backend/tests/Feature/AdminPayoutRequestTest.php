<?php

namespace Tests\Feature;

use App\Models\AdminPermission;
use App\Models\AdminRole;
use App\Models\AdminUser;
use App\Models\Driver;
use App\Models\PayoutRequest;
use App\Models\Transaction;
use App\Models\User;
use App\Models\Wallet;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class AdminPayoutRequestTest extends TestCase
{
    use RefreshDatabase;

    private function makeFinanceAdmin(): AdminUser
    {
        $role = AdminRole::create(['name' => 'finance_'.uniqid()]);
        AdminPermission::create(['role_id' => $role->id, 'resource' => 'payout_requests', 'action' => 'edit']);

        return AdminUser::create([
            'full_name' => 'Finance Admin',
            'email' => uniqid().'@fojem.sn',
            'password_hash' => Hash::make('password123'),
            'role_id' => $role->id,
            'is_active' => true,
        ]);
    }

    public function test_processing_a_payout_request_debits_the_wallet_and_records_a_payout_transaction(): void
    {
        $admin = $this->makeFinanceAdmin();
        Sanctum::actingAs($admin, ['admin'], 'admin');

        $driverUser = User::factory()->create(['is_driver' => true]);
        $wallet = Wallet::create(['user_id' => $driverUser->id, 'balance' => 10000]);
        $driver = Driver::create(['user_id' => $driverUser->id, 'verification_status' => Driver::STATUS_APPROVED]);

        $payoutRequest = PayoutRequest::create([
            'driver_id' => $driver->id,
            'amount' => 4000,
            'destination' => 'wave',
            'destination_ref' => '+221770000000',
            'status' => 'pending',
        ]);

        $response = $this->patchJson("/api/admin/payout-requests/{$payoutRequest->id}/process", [
            'status' => 'processed',
        ]);

        $response->assertOk();
        $this->assertEquals('processed', $response->json('payout_request.status'));

        $wallet->refresh();
        $this->assertEquals('6000.00', (string) $wallet->balance);

        $transaction = Transaction::where('wallet_id', $wallet->id)->where('type', 'payout')->first();
        $this->assertNotNull($transaction);
        $this->assertEquals('4000.00', (string) $transaction->amount);
        $this->assertEquals('completed', $transaction->status);
        $this->assertEquals("payout_request:{$payoutRequest->id}", $transaction->idempotency_key);

        $payoutRequest->refresh();
        $this->assertEquals($admin->id, $payoutRequest->processed_by_admin_id);
    }

    public function test_processing_the_same_payout_request_twice_is_rejected(): void
    {
        $admin = $this->makeFinanceAdmin();
        Sanctum::actingAs($admin, ['admin'], 'admin');

        $driverUser = User::factory()->create(['is_driver' => true]);
        Wallet::create(['user_id' => $driverUser->id, 'balance' => 10000]);
        $driver = Driver::create(['user_id' => $driverUser->id, 'verification_status' => Driver::STATUS_APPROVED]);

        $payoutRequest = PayoutRequest::create([
            'driver_id' => $driver->id,
            'amount' => 4000,
            'destination' => 'wave',
            'destination_ref' => '+221770000000',
            'status' => 'pending',
        ]);

        $this->patchJson("/api/admin/payout-requests/{$payoutRequest->id}/process", ['status' => 'processed'])
            ->assertOk();

        $this->patchJson("/api/admin/payout-requests/{$payoutRequest->id}/process", ['status' => 'processed'])
            ->assertUnprocessable();
    }
}
