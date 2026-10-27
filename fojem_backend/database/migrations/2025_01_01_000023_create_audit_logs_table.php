<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Write-once journal: no soft deletes, no updated_at (rows are never
     * modified after insert). Written exclusively through
     * app/Services/AuditLogger.php / the LogsAuditTrail trait.
     */
    public function up(): void
    {
        Schema::create('audit_logs', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('actor_admin_id')->nullable()->constrained('admin_users')->nullOnDelete();
            $table->string('action', 100);
            $table->string('target_type', 60);
            $table->uuid('target_id');
            $table->jsonb('old_value')->nullable();
            $table->jsonb('new_value')->nullable();
            $table->string('ip_address', 45)->nullable();
            $table->timestamp('created_at');

            $table->index(['target_type', 'target_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('audit_logs');
    }
};
