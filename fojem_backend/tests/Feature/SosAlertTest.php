<?php

namespace Tests\Feature;

use App\Models\AdminPermission;
use App\Models\AdminRole;
use App\Models\AdminUser;
use App\Models\SosAlert;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class SosAlertTest extends TestCase
{
    use RefreshDatabase;

    private function trigger(User $user): string
    {
        Sanctum::actingAs($user);

        return $this->postJson('/api/sos-alerts', ['lat' => 14.69, 'lng' => -17.44])
            ->assertCreated()
            ->json('sos_alert.id');
    }

    public function test_a_second_press_reuses_the_ongoing_alert(): void
    {
        $user = User::factory()->create();

        $first = $this->trigger($user);
        $second = $this->trigger($user);

        $this->assertSame($first, $second);
        $this->assertSame(1, SosAlert::count());
    }

    public function test_the_author_streams_position_and_audio_then_ends_the_alert(): void
    {
        Storage::fake('local');
        $user = User::factory()->create();
        $id = $this->trigger($user);

        $this->postJson("/api/sos-alerts/{$id}/location", ['lat' => 14.70, 'lng' => -17.45])->assertOk();
        $this->post("/api/sos-alerts/{$id}/recordings", [
            'audio' => UploadedFile::fake()->create('sos.m4a', 200, 'audio/mp4'),
            'duration_ms' => 30000,
        ], ['Accept' => 'application/json'])->assertCreated();
        $this->postJson("/api/sos-alerts/{$id}/end")->assertOk();

        $alert = SosAlert::find($id);
        $this->assertEqualsWithDelta(14.70, $alert->last_lat, 0.0001);
        $this->assertCount(2, $alert->path);
        $this->assertNotNull($alert->ended_at);
        $this->assertCount(1, $alert->recordings);
        Storage::disk('local')->assertExists($alert->recordings->first()->file_path);
    }

    public function test_someone_else_cannot_feed_an_alert(): void
    {
        $id = $this->trigger(User::factory()->create());

        Sanctum::actingAs(User::factory()->create());
        $this->postJson("/api/sos-alerts/{$id}/location", ['lat' => 1, 'lng' => 1])->assertForbidden();
        $this->postJson("/api/sos-alerts/{$id}/end")->assertForbidden();
    }

    public function test_admins_get_the_full_alert_file_and_can_listen_to_recordings(): void
    {
        Storage::fake('local');
        $user = User::factory()->create(['full_name' => 'Awa Ndiaye']);
        $user->setEmergencyContact('Fatou Diop', '771234567');
        $id = $this->trigger($user);
        $this->post("/api/sos-alerts/{$id}/recordings", [
            'audio' => UploadedFile::fake()->create('sos.m4a', 50, 'audio/mp4'),
            'duration_ms' => 12000,
        ], ['Accept' => 'application/json'])->assertCreated();

        $role = AdminRole::create(['name' => 'sos_'.uniqid()]);
        AdminPermission::create(['role_id' => $role->id, 'resource' => 'sos_alerts', 'action' => 'view']);
        $admin = AdminUser::create([
            'full_name' => 'Agent', 'email' => uniqid().'@fojem.sn',
            'password_hash' => Hash::make('password123'), 'role_id' => $role->id, 'is_active' => true,
        ]);
        Sanctum::actingAs($admin, ['admin'], 'admin');

        $alert = $this->getJson("/api/admin/sos-alerts/{$id}")
            ->assertOk()
            ->assertJsonPath('sos_alert.user.full_name', 'Awa Ndiaye')
            ->assertJsonPath('sos_alert.user.emergency_contact.name', 'Fatou Diop')
            ->json('sos_alert');

        $this->assertCount(1, $alert['recordings']);
        $this->get(parse_url($alert['recordings'][0]['file_endpoint'], PHP_URL_PATH))->assertOk();
    }
}
