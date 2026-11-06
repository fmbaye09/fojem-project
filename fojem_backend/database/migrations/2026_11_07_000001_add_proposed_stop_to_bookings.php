<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Arrêt proposé par le passager quand aucun point de rendez-vous ne lui
 * convient (StopInsertionPlanner) : le point, le détour pour le chauffeur,
 * l'heure et le prix estimés, puis l'arrêt créé si le chauffeur accepte.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('bookings', function (Blueprint $table) {
            $table->json('proposed_stop')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('bookings', function (Blueprint $table) {
            $table->dropColumn('proposed_stop');
        });
    }
};
