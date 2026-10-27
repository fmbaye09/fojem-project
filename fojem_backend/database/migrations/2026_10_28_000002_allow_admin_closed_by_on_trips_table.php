<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * `closed_by` was created as enum('driver','system'), which Laravel maps
     * to a CHECK constraint on PostgreSQL. Admins can now cancel a trip from
     * the dashboard, so 'admin' becomes a valid value.
     */
    public function up(): void
    {
        DB::statement('ALTER TABLE trips DROP CONSTRAINT IF EXISTS trips_closed_by_check');
        DB::statement("ALTER TABLE trips ADD CONSTRAINT trips_closed_by_check CHECK (closed_by::text = ANY (ARRAY['driver', 'system', 'admin']::text[]))");
    }

    public function down(): void
    {
        DB::table('trips')->where('closed_by', 'admin')->update(['closed_by' => 'system']);
        DB::statement('ALTER TABLE trips DROP CONSTRAINT IF EXISTS trips_closed_by_check');
        DB::statement("ALTER TABLE trips ADD CONSTRAINT trips_closed_by_check CHECK (closed_by::text = ANY (ARRAY['driver', 'system']::text[]))");
    }
};
