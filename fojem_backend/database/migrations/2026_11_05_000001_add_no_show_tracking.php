<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Absences au point de rendez-vous et fiabilité des passagers :
 * - l'heure à laquelle le chauffeur atteint chaque arrêt (preuve GPS d'une
 *   absence, mesure de l'écart des ETA) ;
 * - l'heure des annulations et des absences, pour le score de fiabilité ;
 * - les pourcentages du score restent vides tant qu'ils ne sont pas mesurés.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('trip_stops', function (Blueprint $table) {
            $table->timestamp('reached_at')->nullable()->after('scheduled_at');
        });

        Schema::table('bookings', function (Blueprint $table) {
            $table->timestamp('cancelled_at')->nullable()->after('completed_at');
            $table->timestamp('no_show_at')->nullable()->after('cancelled_at');
        });

        Schema::table('reputation_scores', function (Blueprint $table) {
            $table->decimal('punctuality_pct', 5, 2)->nullable()->change();
            $table->decimal('trips_completed_pct', 5, 2)->nullable()->change();
            $table->decimal('bookings_honored_pct', 5, 2)->nullable()->change();
        });
    }

    public function down(): void
    {
        Schema::table('trip_stops', function (Blueprint $table) {
            $table->dropColumn('reached_at');
        });

        Schema::table('bookings', function (Blueprint $table) {
            $table->dropColumn(['cancelled_at', 'no_show_at']);
        });
    }
};
