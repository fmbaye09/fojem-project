<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('trips', function (Blueprint $table) {
            $table->double('current_lat')->nullable()->after('destination_name');
            $table->double('current_lng')->nullable()->after('current_lat');
            $table->double('current_heading')->nullable()->after('current_lng');
            $table->timestamp('location_updated_at')->nullable()->after('current_heading');
            $table->jsonb('waypoints')->nullable()->after('location_updated_at');
        });
    }

    public function down(): void
    {
        Schema::table('trips', function (Blueprint $table) {
            $table->dropColumn([
                'current_lat',
                'current_lng',
                'current_heading',
                'location_updated_at',
                'waypoints',
            ]);
        });
    }
};

