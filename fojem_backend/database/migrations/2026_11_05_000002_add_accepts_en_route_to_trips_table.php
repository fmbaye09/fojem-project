<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Le chauffeur accepte des passagers une fois parti : ils réservent un
 * arrêt qu'il n'a pas encore atteint, confirmés d'office pour qu'il n'ait
 * rien à valider en roulant.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('trips', function (Blueprint $table) {
            $table->boolean('accepts_en_route')->default(false)->after('women_only');
        });
    }

    public function down(): void
    {
        Schema::table('trips', function (Blueprint $table) {
            $table->dropColumn('accepts_en_route');
        });
    }
};
