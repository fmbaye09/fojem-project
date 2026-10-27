<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('ride_requests', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('passenger_id')->constrained('users')->cascadeOnDelete();
            $table->timestamp('requested_at');
            $table->enum('status', ['searching', 'matched', 'cancelled', 'expired']);
            $table->boolean('women_only')->default(false);
            $table->timestamps();
            $table->softDeletes();
        });

        DB::statement('ALTER TABLE ride_requests ADD COLUMN origin_geom geography(Point,4326) NOT NULL');
        DB::statement('ALTER TABLE ride_requests ADD COLUMN destination_geom geography(Point,4326) NOT NULL');

        DB::statement('CREATE INDEX ride_requests_origin_geom_gist ON ride_requests USING GIST (origin_geom)');
        DB::statement('CREATE INDEX ride_requests_destination_geom_gist ON ride_requests USING GIST (destination_geom)');
    }

    public function down(): void
    {
        Schema::dropIfExists('ride_requests');
    }
};
