<?php

namespace App\Services;

use App\Models\Transaction;
use App\Models\Wallet;
use Illuminate\Support\Facades\DB;

/**
 * Only allowed write path into wallets.balance. Every credit/debit is a
 * DB transaction that (a) inserts an append-only `transactions` row and
 * (b) atomically adjusts the wallet balance with a locked row read, so
 * `wallets.balance` is always derivable from - and never diverges from -
 * the sum of its transactions.
 */
class WalletService
{
    /**
     * @param  'payment'|'payout'|'commission'|'refund'|'referral_bonus'  $type
     * @param  'cash'|'wave'|'orange_money'|'free_money'|'card'|'wallet'  $paymentMethod
     */
    public function credit(
        Wallet $wallet,
        string $type,
        float $amount,
        string $paymentMethod,
        string $idempotencyKey,
        ?string $bookingId = null,
        ?string $externalReference = null,
    ): Transaction {
        return $this->applyDelta($wallet, $type, abs($amount), $paymentMethod, $idempotencyKey, $bookingId, $externalReference);
    }

    public function debit(
        Wallet $wallet,
        string $type,
        float $amount,
        string $paymentMethod,
        string $idempotencyKey,
        ?string $bookingId = null,
        ?string $externalReference = null,
    ): Transaction {
        return $this->applyDelta($wallet, $type, -abs($amount), $paymentMethod, $idempotencyKey, $bookingId, $externalReference);
    }

    private function applyDelta(
        Wallet $wallet,
        string $type,
        float $signedAmount,
        string $paymentMethod,
        string $idempotencyKey,
        ?string $bookingId,
        ?string $externalReference,
    ): Transaction {
        return DB::transaction(function () use ($wallet, $type, $signedAmount, $paymentMethod, $idempotencyKey, $bookingId, $externalReference) {
            $existing = Transaction::where('idempotency_key', $idempotencyKey)->first();
            if ($existing) {
                return $existing;
            }

            $locked = Wallet::where('id', $wallet->id)->lockForUpdate()->firstOrFail();
            $locked->balance = bcadd((string) $locked->balance, (string) $signedAmount, 2);
            $locked->save();

            return Transaction::create([
                'wallet_id' => $wallet->id,
                'booking_id' => $bookingId,
                'type' => $type,
                'amount' => abs($signedAmount),
                'payment_method' => $paymentMethod,
                'idempotency_key' => $idempotencyKey,
                'status' => Transaction::STATUS_COMPLETED,
                'external_reference' => $externalReference,
            ]);
        });
    }
}
