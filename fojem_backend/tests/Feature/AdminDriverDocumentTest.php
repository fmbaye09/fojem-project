<?php

namespace Tests\Feature;

use App\Models\AdminPermission;
use App\Models\AdminRole;
use App\Models\AdminUser;
use App\Models\Driver;
use App\Models\DriverDocument;
use App\Models\User;
use App\Models\Wallet;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class AdminDriverDocumentTest extends TestCase
{
    use RefreshDatabase;

    private function makeAdmin(): AdminUser
    {
        $role = AdminRole::create(['name' => 'doc_reviewer_'.uniqid()]);
        AdminPermission::create(['role_id' => $role->id, 'resource' => 'driver_documents', 'action' => 'edit']);
        AdminPermission::create(['role_id' => $role->id, 'resource' => 'driver_documents', 'action' => 'view']);

        return AdminUser::create([
            'full_name' => 'Doc Reviewer',
            'email' => uniqid().'@fojem.sn',
            'password_hash' => Hash::make('password123'),
            'role_id' => $role->id,
            'is_active' => true,
        ]);
    }

    private function makePendingDriver(): Driver
    {
        $user = User::factory()->create(['is_driver' => true]);
        Wallet::create(['user_id' => $user->id]);

        return Driver::create(['user_id' => $user->id, 'verification_status' => Driver::STATUS_PENDING]);
    }

    public function test_approving_every_required_document_moves_driver_to_approved(): void
    {
        $admin = $this->makeAdmin();
        Sanctum::actingAs($admin, ['admin'], 'admin');

        $driver = $this->makePendingDriver();

        $documents = collect(DriverDocument::REQUIRED_TYPES)->map(fn ($type) => DriverDocument::create([
            'driver_id' => $driver->id,
            'document_type' => $type,
            'file_url' => "documents/{$type}.pdf",
            'status' => DriverDocument::STATUS_PENDING,
        ]));

        // Approve all but the last document: driver must stay pending.
        foreach ($documents->slice(0, -1) as $document) {
            $this->patchJson("/api/admin/drivers/{$driver->id}/documents/{$document->id}/review", [
                'status' => 'approved',
            ])->assertOk();
        }

        $driver->refresh();
        $this->assertEquals(Driver::STATUS_PENDING, $driver->verification_status);

        $last = $documents->last();
        $response = $this->patchJson("/api/admin/drivers/{$driver->id}/documents/{$last->id}/review", [
            'status' => 'approved',
        ]);

        $response->assertOk();
        $this->assertEquals(Driver::STATUS_APPROVED, $response->json('driver.verification_status'));

        $driver->refresh();
        $this->assertEquals(Driver::STATUS_APPROVED, $driver->verification_status);
        $this->assertNotNull($driver->verified_at);
    }

    public function test_rejecting_a_document_sets_driver_to_rejected_with_a_reason(): void
    {
        $admin = $this->makeAdmin();
        Sanctum::actingAs($admin, ['admin'], 'admin');

        $driver = $this->makePendingDriver();
        $document = DriverDocument::create([
            'driver_id' => $driver->id,
            'document_type' => 'permis_recto',
            'file_url' => 'documents/permis_recto.jpg',
            'status' => DriverDocument::STATUS_PENDING,
        ]);

        $response = $this->patchJson("/api/admin/drivers/{$driver->id}/documents/{$document->id}/review", [
            'status' => 'rejected',
            'rejection_reason' => 'Document illisible.',
        ]);

        $response->assertOk();
        $this->assertEquals(Driver::STATUS_REJECTED, $response->json('driver.verification_status'));
        $this->assertEquals('Document illisible.', $response->json('document.rejection_reason'));
    }
}
