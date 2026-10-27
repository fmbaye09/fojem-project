<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Laravel\Sanctum\HasApiTokens;

class AdminUser extends Authenticatable
{
    use HasApiTokens, HasUuids, SoftDeletes;

    protected $fillable = ['full_name', 'email', 'password_hash', 'role_id', 'is_active'];

    protected $hidden = ['password_hash', 'remember_token'];

    public function getAuthPassword(): string
    {
        return $this->password_hash;
    }

    protected function casts(): array
    {
        return [
            'password_hash' => 'hashed',
            'is_active' => 'boolean',
        ];
    }

    public function role(): BelongsTo
    {
        return $this->belongsTo(AdminRole::class, 'role_id');
    }

    /**
     * True when this admin's role has the given permission
     * (resource + action), e.g. hasPermission('driver_documents', 'edit').
     * Used by the RBAC middleware instead of a boolean "is_admin" flag.
     */
    public function hasPermission(string $resource, string $action): bool
    {
        if (! $this->role) {
            return false;
        }

        return $this->role->permissions()
            ->whereIn('resource', [$resource, '*'])
            ->where('action', $action)
            ->exists();
    }
}
