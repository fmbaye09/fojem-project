<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Lieux de rendez-vous connus d'OpenStreetMap (gares routières, stations,
 * péages, ronds-points), importés chaque mois pour être suggérés aux
 * chauffeurs le long de leur route.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('meeting_places', function (Blueprint $table) {
            $table->uuid('id')->primary();
            // « node/123 » : identifiant OSM, pour mettre à jour sans doublon.
            $table->string('osm_id', 40)->unique();
            $table->string('kind', 20);
            $table->string('name', 120);
            $table->string('address', 255)->nullable();
            $table->double('lat');
            $table->double('lng');
            $table->timestamps();
        });

        DB::statement('ALTER TABLE meeting_places ADD COLUMN location_geom geography(Point, 4326)');
        DB::statement('CREATE INDEX meeting_places_location_geom_idx ON meeting_places USING GIST (location_geom)');
    }

    public function down(): void
    {
        Schema::dropIfExists('meeting_places');
    }
};
