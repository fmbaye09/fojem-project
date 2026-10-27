<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Append-only financial ledger: no soft deletes, rows are never updated
     * after being marked completed/failed/reversed (a correction is a new
     * `refund`/`reversed` row, not an edit of the original).
     */
    public function up(): void
    {
        Schema::create('transactions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('wallet_id')->constrained('wallets')->cascadeOnDelete();
            $table->foreignUuid('booking_id')->nullable()->constrained('bookings')->nullOnDelete();
            $table->enum('type', ['payment', 'payout', 'commission', 'refund', 'referral_bonus']);
            $table->decimal('amount', 12, 2);
            $table->enum('payment_method', ['cash', 'wave', 'orange_money', 'free_money', 'card', 'wallet']);
            $table->string('idempotency_key', 100)->unique();
            $table->enum('status', ['pending', 'completed', 'failed', 'reversed']);
            $table->string('external_reference', 150)->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('transactions');
    }
};
