<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('bookings', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('trip_id')->constrained('trips')->cascadeOnDelete();
            $table->foreignUuid('ride_request_id')->nullable()->constrained('ride_requests')->nullOnDelete();
            $table->foreignUuid('passenger_id')->constrained('users')->cascadeOnDelete();
            $table->smallInteger('seat_count')->default(1);
            $table->enum('status', [
                'pending_driver', 'confirmed', 'rejected', 'cancelled_passenger',
                'cancelled_driver', 'completed', 'no_show',
            ]);
            $table->string('departure_code', 4);
            $table->decimal('price_charged', 10, 2);
            $table->timestamp('confirmed_at')->nullable();
            $table->timestamp('started_at')->nullable();
            $table->timestamp('completed_at')->nullable();
            $table->timestamps();
            $table->softDeletes();

            $table->index(['status', 'trip_id']);
        });

        DB::statement('ALTER TABLE bookings ADD COLUMN pickup_point_geom geography(Point,4326) NOT NULL');
        DB::statement('CREATE INDEX bookings_pickup_point_geom_gist ON bookings USING GIST (pickup_point_geom)');
    }

    public function down(): void
    {
        Schema::dropIfExists('bookings');
    }
};
