<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('referrals', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('referrer_id')->constrained('users')->cascadeOnDelete();
            // unique: a given account can only ever be referred once (anti-fraud)
            $table->foreignUuid('referee_id')->unique()->constrained('users')->cascadeOnDelete();
            $table->enum('status', ['pending', 'first_trip_completed', 'rewarded']);
            $table->timestamp('rewarded_at')->nullable();
            $table->timestamps();
            $table->softDeletes();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('referrals');
    }
};
