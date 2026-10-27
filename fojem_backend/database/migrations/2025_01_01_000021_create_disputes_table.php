<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('disputes', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('booking_id')->nullable()->constrained('bookings')->nullOnDelete();
            $table->foreignUuid('reported_by_id')->constrained('users')->cascadeOnDelete();
            $table->foreignUuid('reported_against_id')->constrained('users')->cascadeOnDelete();
            $table->string('reason', 255);
            $table->text('description')->nullable();
            $table->enum('status', ['open', 'investigating', 'resolved', 'dismissed'])->default('open');
            $table->foreignUuid('resolved_by_admin_id')->nullable()->constrained('admin_users')->nullOnDelete();
            $table->text('resolution')->nullable();
            $table->timestamps();
            $table->softDeletes();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('disputes');
    }
};
