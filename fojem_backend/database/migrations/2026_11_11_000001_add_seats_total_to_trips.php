<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Nombre de places publiées par le chauffeur. `seats_available` baisse à
 * chaque réservation acceptée : sans le total, l'app chauffeur ne savait
 * pas afficher « 2 réservées sur 4 » pour un trajet publié depuis un autre
 * téléphone ou après une réinstallation.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('trips', function (Blueprint $table) {
            $table->smallInteger('seats_total')->nullable()->after('seats_available');
        });

        // Trajets existants : places encore libres + places tenues par les
        // réservations qui en ont décompté.
        DB::statement(<<<'SQL'
            UPDATE trips SET seats_total = seats_available + COALESCE((
                SELECT SUM(b.seat_count) FROM bookings b
                WHERE b.trip_id = trips.id
                  AND b.status IN ('confirmed', 'completed')
            ), 0)
        SQL);
    }

    public function down(): void
    {
        Schema::table('trips', function (Blueprint $table) {
            $table->dropColumn('seats_total');
        });
    }
};
