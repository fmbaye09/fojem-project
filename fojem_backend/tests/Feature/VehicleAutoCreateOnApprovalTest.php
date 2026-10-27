<?php

namespace Tests\Feature;

use App\Models\Driver;
use App\Models\DriverDocument;
use App\Models\User;
use App\Models\Wallet;
use App\Services\DriverVerificationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class VehicleAutoCreateOnApprovalTest extends TestCase
{
    use RefreshDatabase;

    public function test_first_approval_turns_pending_vehicle_info_into_a_real_vehicle(): void
    {
        $user = User::factory()->create(['is_driver' => true]);
        Wallet::create(['user_id' => $user->id]);
        $driver = Driver::create([
            'user_id' => $user->id,
            'verification_status' => Driver::STATUS_PENDING,
            'pending_vehicle_brand' => 'Toyota',
            'pending_vehicle_model' => 'Avanza',
            'pending_vehicle_color' => 'Gris',
            'pending_vehicle_plate_number' => 'DK-TEST-01',
            'pending_vehicle_seat_count' => 7,
        ]);

        foreach (DriverDocument::REQUIRED_TYPES as $type) {
            DriverDocument::create([
                'driver_id' => $driver->id,
                'document_type' => $type,
                'file_url' => "driver-documents/{$driver->id}/{$type}.jpg",
                'status' => DriverDocument::STATUS_APPROVED,
            ]);
        }

        DriverVerificationService::recompute($driver->fresh());
        $driver->refresh();

        $this->assertSame(Driver::STATUS_APPROVED, $driver->verification_status);
        $this->assertSame(1, $driver->vehicles()->count());

        $vehicle = $driver->vehicles()->first();
        $this->assertSame('DK-TEST-01', $vehicle->plate_number);
        $this->assertSame('Toyota', $vehicle->brand);
        $this->assertNull($driver->pending_vehicle_plate_number);
    }

    public function test_recompute_without_pending_vehicle_info_creates_nothing(): void
    {
        $user = User::factory()->create(['is_driver' => true]);
        Wallet::create(['user_id' => $user->id]);
        $driver = Driver::create(['user_id' => $user->id, 'verification_status' => Driver::STATUS_PENDING]);

        foreach (DriverDocument::REQUIRED_TYPES as $type) {
            DriverDocument::create([
                'driver_id' => $driver->id,
                'document_type' => $type,
                'file_url' => "driver-documents/{$driver->id}/{$type}.jpg",
                'status' => DriverDocument::STATUS_APPROVED,
            ]);
        }

        DriverVerificationService::recompute($driver->fresh());
        $driver->refresh();

        $this->assertSame(Driver::STATUS_APPROVED, $driver->verification_status);
        $this->assertSame(0, $driver->vehicles()->count());
    }
}
