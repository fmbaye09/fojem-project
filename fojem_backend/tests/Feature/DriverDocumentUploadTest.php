<?php

namespace Tests\Feature;

use App\Models\Driver;
use App\Models\DriverDocument;
use App\Models\User;
use App\Models\Wallet;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class DriverDocumentUploadTest extends TestCase
{
    use RefreshDatabase;

    private function makeDriver(): array
    {
        $user = User::factory()->create(['is_driver' => true]);
        Wallet::create(['user_id' => $user->id]);
        $driver = Driver::create(['user_id' => $user->id, 'verification_status' => Driver::STATUS_PENDING]);

        return [$user, $driver];
    }

    public function test_a_driver_can_upload_a_required_document(): void
    {
        Storage::fake('local');
        [$user] = $this->makeDriver();
        Sanctum::actingAs($user);

        $response = $this->postJson('/api/driver/documents', [
            'document_type' => 'permis_recto',
            'file' => UploadedFile::fake()->image('permis_recto.jpg'),
        ]);

        $response->assertCreated();
        $this->assertEquals('permis_recto', $response->json('document.document_type'));
        $this->assertEquals(DriverDocument::STATUS_PENDING, $response->json('document.status'));
        $this->assertDatabaseCount('driver_documents', 1);
    }

    public function test_a_non_driver_cannot_upload_a_document(): void
    {
        Storage::fake('local');
        $user = User::factory()->create(['is_driver' => false]);
        Wallet::create(['user_id' => $user->id]);
        Sanctum::actingAs($user);

        $this->postJson('/api/driver/documents', [
            'document_type' => 'permis_recto',
            'file' => UploadedFile::fake()->image('permis_recto.jpg'),
        ])->assertForbidden();
    }

    public function test_reuploading_a_rejected_document_resets_it_to_pending_and_recomputes_driver_status(): void
    {
        Storage::fake('local');
        [$user, $driver] = $this->makeDriver();

        foreach (DriverDocument::REQUIRED_TYPES as $type) {
            DriverDocument::create([
                'driver_id' => $driver->id,
                'document_type' => $type,
                'file_url' => "driver-documents/{$driver->id}/{$type}.jpg",
                'status' => $type === 'permis_recto' ? DriverDocument::STATUS_REJECTED : DriverDocument::STATUS_APPROVED,
                'rejection_reason' => $type === 'permis_recto' ? 'Illisible.' : null,
            ]);
        }
        $driver->update(['verification_status' => Driver::STATUS_REJECTED]);

        Sanctum::actingAs($user);

        $response = $this->postJson('/api/driver/documents', [
            'document_type' => 'permis_recto',
            'file' => UploadedFile::fake()->image('permis_recto_v2.jpg'),
        ]);

        $response->assertCreated();
        $this->assertEquals(DriverDocument::STATUS_PENDING, $response->json('document.status'));
        $this->assertNull($response->json('document.rejection_reason'));
        $this->assertDatabaseCount('driver_documents', count(DriverDocument::REQUIRED_TYPES));

        $driver->refresh();
        $this->assertEquals(Driver::STATUS_PENDING, $driver->verification_status);
    }

    public function test_a_driver_can_list_their_own_documents(): void
    {
        Storage::fake('local');
        [$user, $driver] = $this->makeDriver();
        DriverDocument::create([
            'driver_id' => $driver->id,
            'document_type' => 'carte_grise',
            'file_url' => 'driver-documents/x/carte_grise.jpg',
            'status' => DriverDocument::STATUS_PENDING,
        ]);

        Sanctum::actingAs($user);

        $response = $this->getJson('/api/driver/documents');

        $response->assertOk();
        $this->assertCount(1, $response->json('documents'));
    }
}
