<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class ChatAttachmentTest extends TestCase
{
    use RefreshDatabase;

    private function upload(UploadedFile $file): \Illuminate\Testing\TestResponse
    {
        return $this->post('/api/chat/attachments', ['file' => $file], ['Accept' => 'application/json']);
    }

    public function test_a_user_can_send_a_photo(): void
    {
        Storage::fake('public');
        Sanctum::actingAs(User::factory()->create());

        $response = $this->upload(UploadedFile::fake()->image('bagages.jpg', 800, 600))->assertCreated();

        $response->assertJsonPath('kind', 'image')->assertJsonPath('name', 'bagages.jpg');
        $this->assertStringContainsString('/storage/chat-attachments/', $response->json('url'));
        $this->assertCount(1, Storage::disk('public')->files('chat-attachments'));
    }

    public function test_a_user_can_send_a_document(): void
    {
        Storage::fake('public');
        Sanctum::actingAs(User::factory()->create());

        $response = $this->upload(UploadedFile::fake()->create('billet de train.pdf', 300, 'application/pdf'))->assertCreated();

        $response->assertJsonPath('kind', 'file')->assertJsonPath('name', 'billet de train.pdf');
        $this->assertGreaterThan(0, $response->json('size'));
        // Stocké sous un nom aléatoire, pas sous celui du passager.
        $this->assertStringNotContainsString('billet', $response->json('url'));
    }

    public function test_scripts_and_large_files_are_rejected(): void
    {
        Storage::fake('public');
        Sanctum::actingAs(User::factory()->create());

        $this->upload(UploadedFile::fake()->create('evil.php', 10, 'application/x-php'))->assertUnprocessable();
        $this->upload(UploadedFile::fake()->create('gros.pdf', 11 * 1024, 'application/pdf'))->assertUnprocessable();
        $this->assertCount(0, Storage::disk('public')->allFiles());
    }

    public function test_guests_cannot_upload(): void
    {
        $this->post('/api/chat/attachments', [], ['Accept' => 'application/json'])->assertUnauthorized();
    }
}
