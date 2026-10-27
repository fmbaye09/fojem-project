<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Append-only financial ledger row. No SoftDeletes trait on purpose: rows
 * are never deleted or updated once written (see WalletService, the only
 * place allowed to insert into this table).
 */
class Transaction extends Model
{
    use HasUuids;

    public const TYPE_PAYMENT = 'payment';
    public const TYPE_PAYOUT = 'payout';
    public const TYPE_COMMISSION = 'commission';
    public const TYPE_REFUND = 'refund';
    public const TYPE_REFERRAL_BONUS = 'referral_bonus';

    public const STATUS_PENDING = 'pending';
    public const STATUS_COMPLETED = 'completed';
    public const STATUS_FAILED = 'failed';
    public const STATUS_REVERSED = 'reversed';

    protected $fillable = [
        'wallet_id', 'booking_id', 'type', 'amount', 'payment_method',
        'idempotency_key', 'status', 'external_reference',
    ];

    protected function casts(): array
    {
        return ['amount' => 'decimal:2'];
    }

    public function wallet(): BelongsTo
    {
        return $this->belongsTo(Wallet::class);
    }

    public function booking(): BelongsTo
    {
        return $this->belongsTo(Booking::class);
    }
}
