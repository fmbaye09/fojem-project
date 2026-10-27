<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('trips', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('driver_id')->constrained('drivers')->cascadeOnDelete();
            $table->foreignUuid('vehicle_id')->constrained('vehicles')->restrictOnDelete();
            $table->enum('departure_type', ['now', 'scheduled']);
            $table->timestamp('scheduled_at')->nullable();
            $table->decimal('price_per_seat', 10, 2);
            $table->decimal('toll_fees', 10, 2)->default(0);
            $table->smallInteger('seats_available');
            $table->boolean('is_recurring')->default(false);
            $table->string('recurrence_rule', 100)->nullable();
            $table->enum('status', ['open', 'full', 'in_progress', 'completed', 'cancelled'])->default('open');
            $table->enum('closed_by', ['driver', 'system'])->nullable();
            $table->boolean('women_only')->default(false);
            $table->timestamps();
            $table->softDeletes();

            $table->index(['status', 'departure_type', 'scheduled_at']);
        });

        // Geography columns added via raw SQL (Laravel's schema builder has no
        // native PostGIS type). Point = origin/destination, LineString = full
        // route trace used for the mid-route / "free seat" detour math.
        DB::statement('ALTER TABLE trips ADD COLUMN origin_geom geography(Point,4326) NOT NULL');
        DB::statement('ALTER TABLE trips ADD COLUMN destination_geom geography(Point,4326) NOT NULL');
        DB::statement('ALTER TABLE trips ADD COLUMN route_geom geography(LineString,4326) NULL');

        DB::statement('CREATE INDEX trips_origin_geom_gist ON trips USING GIST (origin_geom)');
        DB::statement('CREATE INDEX trips_destination_geom_gist ON trips USING GIST (destination_geom)');
        DB::statement('CREATE INDEX trips_route_geom_gist ON trips USING GIST (route_geom)');
    }

    public function down(): void
    {
        Schema::dropIfExists('trips');
    }
};
