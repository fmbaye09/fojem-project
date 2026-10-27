<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('trips', function (Blueprint $table) {
            $table->string('origin_name')->nullable()->after('destination_geom');
            $table->string('destination_name')->nullable()->after('origin_name');
        });

        Schema::table('ride_requests', function (Blueprint $table) {
            $table->string('origin_name')->nullable()->after('destination_geom');
            $table->string('destination_name')->nullable()->after('origin_name');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('trips', function (Blueprint $table) {
            $table->dropColumn(['origin_name', 'destination_name']);
        });

        Schema::table('ride_requests', function (Blueprint $table) {
            $table->dropColumn(['origin_name', 'destination_name']);
        });
    }
};
