<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('sos_alerts', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->constrained('users')->cascadeOnDelete();
            $table->foreignUuid('booking_id')->nullable()->constrained('bookings')->nullOnDelete();
            $table->timestamp('triggered_at');
            $table->enum('status', ['open', 'in_progress', 'resolved'])->default('open');
            $table->foreignUuid('handled_by_admin_id')->nullable()->constrained('admin_users')->nullOnDelete();
            $table->text('resolution_notes')->nullable();
            $table->timestamps();
            $table->softDeletes();
        });

        DB::statement('ALTER TABLE sos_alerts ADD COLUMN location_geom geography(Point,4326) NOT NULL');
        DB::statement('CREATE INDEX sos_alerts_location_geom_gist ON sos_alerts USING GIST (location_geom)');
    }

    public function down(): void
    {
        Schema::dropIfExists('sos_alerts');
    }
};
