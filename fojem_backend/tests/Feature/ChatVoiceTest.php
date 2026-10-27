<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class ChatVoiceTest extends TestCase
{
    use RefreshDatabase;

    public function test_a_user_can_upload_a_voice_message(): void
    {
        Storage::fake('public');
        Sanctum::actingAs(User::factory()->create());

        $response = $this->post('/api/chat/voice', [
            'audio' => UploadedFile::fake()->create('voice.m4a', 120, 'audio/mp4'),
            'duration_ms' => 4200,
        ], ['Accept' => 'application/json']);

        $response->assertCreated()->assertJsonPath('duration_ms', 4200);
        $this->assertStringContainsString('/storage/chat-voice/', $response->json('url'));
        $this->assertCount(1, Storage::disk('public')->files('chat-voice'));
    }

    public function test_non_audio_files_are_rejected(): void
    {
        Storage::fake('public');
        Sanctum::actingAs(User::factory()->create());

        $this->post('/api/chat/voice', [
            'audio' => UploadedFile::fake()->create('evil.php', 10, 'application/x-php'),
            'duration_ms' => 1000,
        ], ['Accept' => 'application/json'])->assertUnprocessable();
    }

    public function test_guests_cannot_upload(): void
    {
        $this->post('/api/chat/voice', [], ['Accept' => 'application/json'])->assertUnauthorized();
    }
}
