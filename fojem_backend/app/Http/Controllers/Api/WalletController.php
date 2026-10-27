<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;

class WalletController extends Controller
{
    public function show(Request $request)
    {
        $wallet = $request->user()->wallet;

        return response()->json(['wallet' => $wallet]);
    }

    public function transactions(Request $request)
    {
        $wallet = $request->user()->wallet;

        $transactions = $wallet
            ? $wallet->transactions()->orderByDesc('created_at')->paginate(20)
            : ['data' => []];

        return response()->json($transactions);
    }
}
