<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('matching_scores', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('ride_request_id')->constrained('ride_requests')->cascadeOnDelete();
            $table->foreignUuid('trip_id')->constrained('trips')->cascadeOnDelete();
            $table->decimal('compatibility_score', 5, 2);
            $table->integer('detour_distance_m');
            $table->integer('detour_duration_s');
            $table->timestamp('computed_at');
            $table->timestamps();
            $table->softDeletes();

            $table->index(['ride_request_id', 'compatibility_score']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('matching_scores');
    }
};
