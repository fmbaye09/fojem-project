<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Le départ du chauffeur de chaque arrêt (première position à plus de
 * 400 m une fois l'arrêt atteint, trajet en cours) : il dit s'il a attendu
 * ses passagers jusqu'au bout.
 *
 * Et l'issue « manqué » d'une réservation : le passager n'est pas monté
 * sans que ce soit une absence prouvée (chauffeur reparti avant la fin de
 * l'attente, ou jamais venu à l'arrêt). Aucune pénalité pour le passager.
 */
return new class extends Migration
{
    private const STATUSES = ['pending_driver', 'confirmed', 'rejected', 'cancelled_passenger', 'cancelled_driver', 'completed', 'no_show'];

    public function up(): void
    {
        Schema::table('trip_stops', function (Blueprint $table) {
            $table->timestamp('left_at')->nullable();
        });

        $this->statusCheck([...self::STATUSES, 'missed']);
    }

    public function down(): void
    {
        DB::table('bookings')->where('status', 'missed')->update(['status' => 'cancelled_driver']);
        $this->statusCheck(self::STATUSES);

        Schema::table('trip_stops', function (Blueprint $table) {
            $table->dropColumn('left_at');
        });
    }

    private function statusCheck(array $statuses): void
    {
        $list = implode(', ', array_map(fn (string $s) => "'{$s}'", $statuses));
        DB::statement('ALTER TABLE bookings DROP CONSTRAINT IF EXISTS bookings_status_check');
        DB::statement("ALTER TABLE bookings ADD CONSTRAINT bookings_status_check CHECK (status::text = ANY (ARRAY[{$list}]::text[]))");
    }
};
