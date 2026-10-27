<?php

namespace App\Services;

use App\Models\AuditLog;
use Illuminate\Http\Request;

/**
 * Single write path into `audit_logs`. Any sensitive admin action
 * (document validation, account suspension, refund, tariff change, ...)
 * MUST go through this service so the journal stays complete and
 * consistent - never insert into audit_logs directly.
 */
class AuditLogger
{
    public static function log(
        ?string $actorAdminId,
        string $action,
        string $targetType,
        string $targetId,
        ?array $oldValue = null,
        ?array $newValue = null,
        ?string $ipAddress = null,
    ): AuditLog {
        return AuditLog::create([
            'actor_admin_id' => $actorAdminId,
            'action' => $action,
            'target_type' => $targetType,
            'target_id' => $targetId,
            'old_value' => $oldValue,
            'new_value' => $newValue,
            'ip_address' => $ipAddress,
            'created_at' => now(),
        ]);
    }

    public static function logFromRequest(
        Request $request,
        string $action,
        string $targetType,
        string $targetId,
        ?array $oldValue = null,
        ?array $newValue = null,
    ): AuditLog {
        $admin = $request->user('admin') ?? $request->user();

        return self::log(
            $admin?->id,
            $action,
            $targetType,
            $targetId,
            $oldValue,
            $newValue,
            $request->ip(),
        );
    }
}
