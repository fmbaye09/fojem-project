<?php

namespace App\Http\Middleware;

use App\Models\AdminUser;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Baseline gate for every /api/admin/* route, applied on top of
 * auth:admin + abilities:admin. Those two alone are not enough: Sanctum
 * grants a token every ability ('*') by default when none is passed
 * explicitly (see HasApiTokens::createToken()), so a plain passenger/driver
 * token from /api/auth/login would also satisfy `abilities:admin`. The
 * real boundary is that the token's tokenable model actually resolves to
 * AdminUser (via the "admin" guard, config/auth.php) and that account is
 * still active - checked once here so every admin route, including the
 * ones with no resource-specific admin_permissions gate (overview, stats),
 * is protected the same way. EnsureAdminHasPermission re-checks this for
 * defense in depth on the routes it guards.
 */
class EnsureIsActiveAdmin
{
    public function handle(Request $request, Closure $next): Response
    {
        $admin = $request->user('admin') ?? $request->user();

        if (! $admin instanceof AdminUser || ! $admin->is_active) {
            return response()->json(['message' => 'Non autorise.'], 403);
        }

        return $next($request);
    }
}
