<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * NOTE on auth_sessions vs Sanctum's personal_access_tokens:
     *
     * We use Laravel Sanctum for API authentication (Bearer tokens), which
     * already stores a hashed token in `personal_access_tokens`. Rather than
     * duplicating that as the "source of truth" for auth, `auth_sessions` is
     * kept as a complementary, app-level device/session ledger: one row per
     * device login, used for showing the user "your active devices", forcing
     * a remote logout (revoked_at), and auditing IP addresses over time -
     * concerns Sanctum's table does not track. In practice a login writes to
     * both: Sanctum issues the bearer token, and we store its hash (never
     * the raw token) + device_id + ip in auth_sessions for that richer view.
     */
    public function up(): void
    {
        Schema::create('auth_sessions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->constrained('users')->cascadeOnDelete();
            $table->string('device_id', 255);
            $table->string('token_hash', 255);
            $table->string('ip_address', 45)->nullable();
            $table->timestamp('expires_at');
            $table->timestamp('revoked_at')->nullable();
            $table->timestamps();
            $table->softDeletes();

            $table->index(['user_id', 'device_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('auth_sessions');
    }
};
