<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\Auth\AdminLoginRequest;
use App\Models\AdminUser;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

/**
 * Auth for the admin dashboard, entirely separate from the passenger/driver
 * `users` auth (App\Http\Controllers\Api\AuthController): a distinct model
 * (AdminUser), a distinct Sanctum guard ("admin", see config/auth.php), and
 * tokens minted with the `admin` ability so a leaked/mis-scoped `users`
 * token can never pass the `abilities:admin` middleware guarding every
 * /api/admin/* route (see routes/api.php).
 */
class AdminAuthController extends Controller
{
    public function login(AdminLoginRequest $request)
    {
        $admin = AdminUser::where('email', strtolower($request->string('email')))->first();

        if (! $admin || ! Hash::check($request->string('password'), $admin->password_hash)) {
            throw ValidationException::withMessages([
                'email' => ['Identifiants invalides.'],
            ]);
        }

        if (! $admin->is_active) {
            throw ValidationException::withMessages([
                'email' => ['Ce compte administrateur est desactive.'],
            ]);
        }

        $deviceId = $request->input('device_id', 'admin-dashboard');
        // Admin sessions expire (unlike passenger/driver app tokens, which
        // stay valid indefinitely like any normal consumer app): a dashboard
        // handling sensitive data (documents, payouts, account status)
        // should not stay logged in forever on a shared or unattended
        // machine. 8h covers a full admin workday without re-login.
        $expiresAt = now()->addHours(8);
        $plainToken = $admin->createToken($deviceId, ['admin'], $expiresAt)->plainTextToken;

        return response()->json([
            'admin' => $admin->load('role.permissions'),
            'token' => $plainToken,
        ]);
    }

    public function logout(Request $request)
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json(['message' => 'Deconnecte.']);
    }

    /**
     * Current admin + effective role/permissions, so the dashboard SPA can
     * build its nav/guards without re-deriving RBAC logic client-side.
     */
    public function me(Request $request)
    {
        $admin = $request->user()->load('role.permissions');

        return response()->json([
            'admin' => $admin,
            'role' => $admin->role?->name,
            'permissions' => $admin->role
                ? $admin->role->permissions->map(fn ($p) => ['resource' => $p->resource, 'action' => $p->action])
                : [],
        ]);
    }
}
