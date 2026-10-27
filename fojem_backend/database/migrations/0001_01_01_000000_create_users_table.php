<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     *
     * `users` is the single account table shared by passengers and drivers
     * (a user becomes a driver by gaining a `drivers` profile row, see
     * 2024_..._create_drivers_table). Auth is email + password (bcrypt),
     * no OTP. `sessions` below is kept only because Laravel's database
     * session driver needs it for the (currently unused) web guard; the
     * business-level "which device/token is logged in" concept lives in
     * `auth_sessions` (see its own migration) and/or Sanctum's
     * `personal_access_tokens` table.
     */
    public function up(): void
    {
        Schema::create('users', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('full_name', 120);
            $table->string('email', 160)->unique();
            $table->string('password_hash', 255);
            $table->string('phone_number', 20)->unique();
            $table->string('profile_photo_url', 255)->nullable();
            $table->enum('gender', ['male', 'female', 'other']);
            $table->enum('account_status', ['active', 'disabled', 'deleted'])->default('active');
            $table->boolean('is_driver')->default(false);
            $table->enum('language', ['fr', 'wo', 'en'])->default('fr');
            $table->rememberToken();
            $table->timestamps();
            $table->softDeletes();
        });

        Schema::create('password_reset_tokens', function (Blueprint $table) {
            $table->string('email')->primary();
            $table->string('token');
            $table->timestamp('created_at')->nullable();
        });

        Schema::create('sessions', function (Blueprint $table) {
            $table->string('id')->primary();
            $table->uuid('user_id')->nullable()->index();
            $table->string('ip_address', 45)->nullable();
            $table->text('user_agent')->nullable();
            $table->longText('payload');
            $table->integer('last_activity')->index();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('sessions');
        Schema::dropIfExists('password_reset_tokens');
        Schema::dropIfExists('users');
    }
};
