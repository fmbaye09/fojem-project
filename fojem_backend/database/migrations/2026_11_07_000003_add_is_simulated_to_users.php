<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Comptes créés par le simulateur du dashboard (local uniquement) : on les
 * reconnaît pour les supprimer d'un coup, avec leurs trajets et réservations.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->boolean('is_simulated')->default(false)->index();
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropIndex(['is_simulated']);
            $table->dropColumn('is_simulated');
        });
    }
};
