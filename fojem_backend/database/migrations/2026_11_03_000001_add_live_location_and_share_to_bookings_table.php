<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * - Position du passager partagée avec son chauffeur (sur son choix, le jour
 *   du trajet, jusqu'à l'embarquement).
 * - Lien de suivi du trajet que le passager envoie à un proche.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('bookings', function (Blueprint $table) {
            $table->double('passenger_lat')->nullable();
            $table->double('passenger_lng')->nullable();
            $table->timestamp('passenger_location_at')->nullable();
            $table->string('share_token', 64)->nullable()->unique();
            $table->timestamp('share_expires_at')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('bookings', function (Blueprint $table) {
            $table->dropUnique(['share_token']);
            $table->dropColumn(['passenger_lat', 'passenger_lng', 'passenger_location_at', 'share_token', 'share_expires_at']);
        });
    }
};
