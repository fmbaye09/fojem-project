<?php

namespace App\Http\Middleware;

use App\Models\AdminUser;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * RBAC gate for the (future) admin dashboard API: checks the authenticated
 * admin_users row's role against admin_roles/admin_permissions, never a
 * simple boolean "is_admin" flag. Usage: ->middleware('admin.permission:driver_documents,edit')
 */
class EnsureAdminHasPermission
{
    public function handle(Request $request, Closure $next, string $resource, string $action): Response
    {
        $admin = $request->user('admin') ?? $request->user();

        if (! $admin instanceof AdminUser || ! $admin->is_active) {
            return response()->json(['message' => 'Non autorise.'], 403);
        }

        if (! $admin->hasPermission($resource, $action)) {
            return response()->json(['message' => 'Permission refusee.'], 403);
        }

        return $next($request);
    }
}
