<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('drivers', function (Blueprint $table) {
            // Vehicle info entered during driver activation, before
            // verification is approved and there is a real Vehicle row to
            // attach it to. Consumed (and cleared) by
            // DriverVerificationService::recompute() the moment the driver
            // is first approved, which turns it into an actual Vehicle.
            $table->string('pending_vehicle_brand', 60)->nullable();
            $table->string('pending_vehicle_model', 60)->nullable();
            $table->string('pending_vehicle_color', 60)->nullable();
            $table->string('pending_vehicle_plate_number', 20)->nullable();
            $table->smallInteger('pending_vehicle_seat_count')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('drivers', function (Blueprint $table) {
            $table->dropColumn([
                'pending_vehicle_brand',
                'pending_vehicle_model',
                'pending_vehicle_color',
                'pending_vehicle_plate_number',
                'pending_vehicle_seat_count',
            ]);
        });
    }
};
