<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('payout_requests', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('driver_id')->constrained('drivers')->cascadeOnDelete();
            $table->decimal('amount', 12, 2);
            $table->enum('destination', ['wave', 'orange_money', 'bank_account']);
            // encrypted at the app layer (Laravel `encrypted` cast) - the DB
            // column is a plain text/string large enough for ciphertext.
            $table->text('destination_ref');
            $table->enum('status', ['pending', 'processed', 'rejected'])->default('pending');
            $table->foreignUuid('processed_by_admin_id')->nullable()->constrained('admin_users')->nullOnDelete();
            $table->timestamps();
            $table->softDeletes();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('payout_requests');
    }
};
