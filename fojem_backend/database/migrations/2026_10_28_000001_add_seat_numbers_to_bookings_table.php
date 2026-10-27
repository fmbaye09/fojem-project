<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('bookings', function (Blueprint $table) {
            // Seat ids picked on the vehicle plan (e.g. ["1","3"]). Nullable:
            // older bookings and clients that only send seat_count have none.
            $table->jsonb('seat_numbers')->nullable()->after('seat_count');
        });
    }

    public function down(): void
    {
        Schema::table('bookings', function (Blueprint $table) {
            $table->dropColumn('seat_numbers');
        });
    }
};
