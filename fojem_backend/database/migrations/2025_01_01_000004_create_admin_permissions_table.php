<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('admin_permissions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('role_id')->constrained('admin_roles')->cascadeOnDelete();
            $table->string('resource', 100);
            $table->enum('action', ['view', 'edit', 'delete']);
            $table->timestamps();
            $table->softDeletes();

            $table->unique(['role_id', 'resource', 'action']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('admin_permissions');
    }
};
