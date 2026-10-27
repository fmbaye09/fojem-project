<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\Finance\ProcessPayoutRequestRequest;
use App\Models\PayoutRequest;
use App\Services\AuditLogger;
use App\Services\WalletService;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

class PayoutRequestController extends Controller
{
    public function index(Request $request)
    {
        $query = PayoutRequest::query()->with('driver.user')->latest();

        if ($status = $request->string('status')->value()) {
            $query->where('status', $status);
        }

        return response()->json($query->paginate($request->integer('per_page', 20)));
    }

    /**
     * Mark a payout request processed or rejected. On "processed" this
     * debits the driver's wallet for the payout amount through the existing
     * WalletService (never duplicating its locking/idempotency logic here),
     * which also inserts the corresponding append-only `transactions` row
     * of type "payout".
     */
    public function process(ProcessPayoutRequestRequest $request, PayoutRequest $payoutRequest, WalletService $wallets)
    {
        if ($payoutRequest->status !== 'pending') {
            throw ValidationException::withMessages([
                'status' => ['Cette demande de retrait a deja ete traitee.'],
            ]);
        }

        $admin = $request->user();
        $newStatus = $request->string('status')->value();
        $old = ['status' => $payoutRequest->status];

        if ($newStatus === 'processed') {
            $wallet = $payoutRequest->driver->user->wallet;

            if (! $wallet || bccomp((string) $wallet->balance, (string) $payoutRequest->amount, 2) < 0) {
                throw ValidationException::withMessages([
                    'amount' => ['Solde du portefeuille insuffisant pour ce retrait.'],
                ]);
            }

            // transactions.payment_method does not have a "bank_account"
            // value (only wave/orange_money/free_money/card/cash/wallet -
            // see the transactions migration), while payout_requests.destination
            // does allow "bank_account". Map that one case to "wallet" (an
            // internal transfer out of the platform ledger) rather than
            // widening the ledger's payment_method enum for a destination
            // that has no real payment-method equivalent.
            $paymentMethod = $payoutRequest->destination === 'bank_account' ? 'wallet' : $payoutRequest->destination;

            $wallets->debit(
                $wallet,
                'payout',
                (float) $payoutRequest->amount,
                $paymentMethod,
                'payout_request:'.$payoutRequest->id,
            );
        }

        $payoutRequest->update([
            'status' => $newStatus,
            'processed_by_admin_id' => $admin->id,
        ]);

        AuditLogger::logFromRequest(
            $request,
            'payout_request.processed',
            'payout_request',
            $payoutRequest->id,
            $old,
            ['status' => $newStatus],
        );

        return response()->json(['payout_request' => $payoutRequest->fresh()]);
    }
}
