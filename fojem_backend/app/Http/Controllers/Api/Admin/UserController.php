<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\Users\UpdateUserStatusRequest;
use App\Models\User;
use App\Services\AuditLogger;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class UserController extends Controller
{
    public function index(Request $request)
    {
        $query = User::query()->with('driver')->latest();

        if ($search = $request->string('search')->trim()->value()) {
            $query->where(function ($q) use ($search) {
                $q->where('full_name', 'ilike', "%{$search}%")
                    ->orWhere('email', 'ilike', "%{$search}%")
                    ->orWhere('phone_number', 'ilike', "%{$search}%");
            });
        }

        if ($status = $request->string('account_status')->value()) {
            $query->where('account_status', $status);
        }

        if ($identityStatus = $request->string('identity_status')->value()) {
            $query->where('identity_status', $identityStatus);
        }

        if ($request->has('is_driver')) {
            $query->where('is_driver', $request->boolean('is_driver'));
        }

        return response()->json($query->paginate($request->integer('per_page', 20)));
    }

    public function updateStatus(UpdateUserStatusRequest $request, User $user)
    {
        $old = $user->account_status;
        $new = $request->string('account_status')->value();

        $user->update(['account_status' => $new]);

        AuditLogger::logFromRequest(
            $request,
            'user.status_updated',
            'user',
            $user->id,
            ['account_status' => $old],
            ['account_status' => $new],
        );

        return response()->json(['user' => $user->fresh()]);
    }

    public function reviewIdentity(Request $request, User $user)
    {
        $request->validate([
            'status' => 'required|in:approved,rejected',
            'rejection_reason' => 'nullable|string|max:500',
        ]);

        $status = $request->string('status')->value();
        $reason = $request->input('rejection_reason');

        $user->update([
            'identity_status' => $status,
            'identity_rejection_reason' => $status === 'rejected' ? $reason : null,
            'identity_reviewed_at' => now(),
        ]);

        AuditLogger::logFromRequest(
            $request,
            'user.identity_reviewed',
            'user',
            $user->id,
            ['identity_status' => $user->getOriginal('identity_status')],
            ['identity_status' => $status, 'rejection_reason' => $reason],
        );

        return response()->json([
            'message' => $status === 'approved' ? 'Identité approuvée avec succès.' : 'Demande rejetée.',
            'user' => $user->fresh(),
        ]);
    }
}
