<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('trips', function (Blueprint $table) {
            // Position of the last stop the driver has reached (0 = departure
            // once the trip starts). Drives "next stop" and ETAs.
            $table->unsignedSmallInteger('last_passed_stop_position')->nullable()->after('location_updated_at');
        });
    }

    public function down(): void
    {
        Schema::table('trips', function (Blueprint $table) {
            $table->dropColumn('last_passed_stop_position');
        });
    }
};
