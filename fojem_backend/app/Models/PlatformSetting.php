<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;

class PlatformSetting extends Model
{
    use HasUuids, SoftDeletes;

    protected $fillable = ['zone_name', 'price_per_km', 'commission_pct', 'updated_by_admin_id'];

    protected function casts(): array
    {
        return [
            'price_per_km' => 'decimal:2',
            'commission_pct' => 'decimal:2',
        ];
    }

    public function updatedByAdmin(): BelongsTo
    {
        return $this->belongsTo(AdminUser::class, 'updated_by_admin_id');
    }
}
