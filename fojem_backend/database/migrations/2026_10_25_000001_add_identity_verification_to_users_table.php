<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('identity_status', 20)->default('none')->index(); // 'none', 'pending', 'approved', 'rejected'
            $table->string('identity_document_type', 30)->nullable(); // 'id_card', 'driver_license'
            $table->string('identity_document_number', 60)->nullable();
            $table->string('identity_front_url', 255)->nullable();
            $table->string('identity_back_url', 255)->nullable();
            $table->text('identity_rejection_reason')->nullable();
            $table->timestamp('identity_submitted_at')->nullable();
            $table->timestamp('identity_reviewed_at')->nullable();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn([
                'identity_status',
                'identity_document_type',
                'identity_document_number',
                'identity_front_url',
                'identity_back_url',
                'identity_rejection_reason',
                'identity_submitted_at',
                'identity_reviewed_at',
            ]);
        });
    }
};
