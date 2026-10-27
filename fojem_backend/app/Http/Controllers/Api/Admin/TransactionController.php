<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Models\Transaction;
use Illuminate\Http\Request;

class TransactionController extends Controller
{
    public function index(Request $request)
    {
        $query = Transaction::query()->with('wallet.user')->latest();

        if ($type = $request->string('type')->value()) {
            $query->where('type', $type);
        }

        if ($status = $request->string('status')->value()) {
            $query->where('status', $status);
        }

        if ($from = $request->string('from')->value()) {
            $query->where('created_at', '>=', $from);
        }

        if ($to = $request->string('to')->value()) {
            $query->where('created_at', '<=', $to);
        }

        return response()->json($query->paginate($request->integer('per_page', 20)));
    }
}
