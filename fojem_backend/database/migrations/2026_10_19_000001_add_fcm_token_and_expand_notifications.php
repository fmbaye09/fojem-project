<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // 1. Add FCM token storage on users
        Schema::table('users', function (Blueprint $table) {
            $table->string('fcm_token', 512)->nullable()->after('language');
        });

        // 2. Expand the notification type enum to cover booking/chat events
        //    and add a human-readable title column.
        //    PostgreSQL requires rebuilding the enum via a temporary column.
        DB::statement("ALTER TABLE notifications ADD COLUMN type_new VARCHAR(50)");
        DB::statement("UPDATE notifications SET type_new = type::text");
        DB::statement("ALTER TABLE notifications DROP COLUMN type");
        DB::statement("ALTER TABLE notifications RENAME COLUMN type_new TO type");

        Schema::table('notifications', function (Blueprint $table) {
            $table->string('title', 255)->nullable()->after('type');
        });
    }

    public function down(): void
    {
        Schema::table('notifications', function (Blueprint $table) {
            $table->dropColumn('title');
        });

        // Revert type back to original enum (best effort)
        DB::statement("ALTER TABLE notifications ALTER COLUMN type TYPE VARCHAR(50)");

        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('fcm_token');
        });
    }
};
