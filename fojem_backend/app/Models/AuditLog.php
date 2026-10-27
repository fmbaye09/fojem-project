<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Write-once audit trail: no updated_at column, no soft deletes. Always
 * write through App\Services\AuditLogger, never Model::create() directly
 * elsewhere, so every sensitive admin action is consistently captured.
 */
class AuditLog extends Model
{
    use HasUuids;

    const UPDATED_AT = null;

    protected $fillable = [
        'actor_admin_id', 'action', 'target_type', 'target_id',
        'old_value', 'new_value', 'ip_address', 'created_at',
    ];

    protected function casts(): array
    {
        return [
            'old_value' => 'array',
            'new_value' => 'array',
            'created_at' => 'datetime',
        ];
    }

    public function actorAdmin(): BelongsTo
    {
        return $this->belongsTo(AdminUser::class, 'actor_admin_id');
    }
}
