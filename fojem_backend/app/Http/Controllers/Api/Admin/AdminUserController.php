<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\AdminUsers\StoreAdminUserRequest;
use App\Models\AdminRole;
use App\Models\AdminUser;
use App\Services\AuditLogger;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

class AdminUserController extends Controller
{
    public function index(Request $request)
    {
        $query = AdminUser::query()->with('role')->latest();

        return response()->json($query->paginate($request->integer('per_page', 20)));
    }

    /**
     * Creating admin accounts is reserved for super_admin, on top of the
     * `admin_users.edit` permission check already done by the
     * admin.permission route middleware: a support/finance admin could in
     * theory be granted admin_users.edit via a custom role, but minting new
     * admin accounts stays a super_admin-only capability regardless of
     * fine-grained permission wiring, checked explicitly here via the role.
     */
    public function store(StoreAdminUserRequest $request)
    {
        $actor = $request->user();

        if ($actor->role?->name !== AdminRole::SUPER_ADMIN) {
            throw ValidationException::withMessages([
                'role_id' => ['Seul un super_admin peut creer un compte administrateur.'],
            ]);
        }

        $admin = AdminUser::create([
            'full_name' => $request->string('full_name'),
            'email' => strtolower($request->string('email')),
            'password_hash' => Hash::make($request->string('password')),
            'role_id' => $request->string('role_id'),
            'is_active' => $request->boolean('is_active', true),
        ]);

        AuditLogger::logFromRequest(
            $request,
            'admin_user.created',
            'admin_user',
            $admin->id,
            null,
            ['email' => $admin->email, 'role_id' => $admin->role_id],
        );

        return response()->json(['admin_user' => $admin->load('role')], 201);
    }
}
