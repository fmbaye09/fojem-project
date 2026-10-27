<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('reputation_scores', function (Blueprint $table) {
            $table->foreignUuid('user_id')->primary()->constrained('users')->cascadeOnDelete();
            $table->decimal('punctuality_pct', 5, 2);
            $table->decimal('trips_completed_pct', 5, 2);
            $table->decimal('bookings_honored_pct', 5, 2);
            $table->integer('no_show_count')->default(0);
            $table->timestamp('last_computed_at');
            $table->timestamps();
            $table->softDeletes();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('reputation_scores');
    }
};
