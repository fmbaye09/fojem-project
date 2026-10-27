<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('trip_reoptimization_events', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('trip_id')->constrained('trips')->cascadeOnDelete();
            $table->timestamp('freed_at');
            $table->enum('candidate_type', ['instant_nearby', 'scheduled_matching_time']);
            $table->foreignUuid('matched_booking_id')->nullable()->constrained('bookings')->nullOnDelete();
            $table->timestamps();
            $table->softDeletes();
        });

        DB::statement('ALTER TABLE trip_reoptimization_events ADD COLUMN freed_at_geom geography(Point,4326) NOT NULL');
        DB::statement('CREATE INDEX trip_reopt_freed_at_geom_gist ON trip_reoptimization_events USING GIST (freed_at_geom)');
    }

    public function down(): void
    {
        Schema::dropIfExists('trip_reoptimization_events');
    }
};
