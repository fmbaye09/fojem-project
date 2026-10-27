<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('driver_documents', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('driver_id')->constrained('drivers')->cascadeOnDelete();
            // The full activation checklist for a driver: permit (front/back),
            // vehicle registration card, 4 vehicle photos, and 2 selfies
            // holding the registration card / permit (anti-fraud proof that
            // the documents belong to this driver). See
            // App\Models\DriverDocument::REQUIRED_TYPES.
            $table->enum('document_type', [
                'permis_recto',
                'permis_verso',
                'carte_grise',
                'vehicule_avant',
                'vehicule_arriere',
                'vehicule_gauche',
                'vehicule_droite',
                'selfie_carte_grise',
                'selfie_permis',
            ]);
            // Never a public direct URL: this points at a private disk path,
            // resolved to a time-limited signed URL by the app when served.
            $table->string('file_url', 255);
            $table->enum('status', ['pending', 'approved', 'rejected'])->default('pending');
            $table->foreignUuid('reviewed_by_admin_id')->nullable()->constrained('admin_users')->nullOnDelete();
            $table->string('rejection_reason', 255)->nullable();
            $table->timestamps();
            $table->softDeletes();

            // A driver has at most one (current) document per type - a
            // re-upload replaces it rather than piling up duplicates.
            $table->unique(['driver_id', 'document_type']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('driver_documents');
    }
};
