<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * SOS en direct : trajet concerné, rôle de l'auteur, dernière position et
 * parcours, fin de l'alerte par l'utilisateur, et enregistrements audio
 * envoyés par morceaux pendant l'alerte.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('sos_alerts', function (Blueprint $table) {
            $table->foreignUuid('trip_id')->nullable()->after('booking_id')->constrained('trips')->nullOnDelete();
            $table->string('role', 20)->default('passenger')->after('trip_id');
            $table->double('last_lat')->nullable();
            $table->double('last_lng')->nullable();
            $table->timestamp('last_location_at')->nullable();
            // [[lat, lng, iso8601], …] — les derniers points, pour la carte admin.
            $table->jsonb('path')->nullable();
            // « Je suis en sécurité » : l'alerte reste à traiter par un admin.
            $table->timestamp('ended_at')->nullable();
            // Prévu pour le SMS au contact d'urgence (pas encore envoyé).
            $table->timestamp('notified_at')->nullable();
        });

        Schema::create('sos_recordings', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('sos_alert_id')->constrained('sos_alerts')->cascadeOnDelete();
            $table->string('file_path', 255);
            $table->unsignedInteger('duration_ms');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('sos_recordings');
        Schema::table('sos_alerts', function (Blueprint $table) {
            $table->dropConstrainedForeignId('trip_id');
            $table->dropColumn(['role', 'last_lat', 'last_lng', 'last_location_at', 'path', 'ended_at', 'notified_at']);
        });
    }
};
