<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

class AdminRole extends Model
{
    use HasUuids, SoftDeletes;

    public const SUPER_ADMIN = 'super_admin';
    public const SUPPORT = 'support';
    public const FINANCE = 'finance';

    protected $fillable = ['name'];

    public function permissions(): HasMany
    {
        return $this->hasMany(AdminPermission::class, 'role_id');
    }

    public function adminUsers(): HasMany
    {
        return $this->hasMany(AdminUser::class, 'role_id');
    }
}
