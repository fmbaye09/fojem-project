<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

class BusinessAccount extends Model
{
    use HasUuids, SoftDeletes;

    protected $fillable = ['name', 'type', 'discount_pct'];

    protected function casts(): array
    {
        return ['discount_pct' => 'decimal:2'];
    }

    public function members(): HasMany
    {
        return $this->hasMany(BusinessAccountMember::class);
    }
}
