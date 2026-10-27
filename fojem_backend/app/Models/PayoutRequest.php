<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;

class PayoutRequest extends Model
{
    use HasUuids, SoftDeletes;

    protected $fillable = [
        'driver_id', 'amount', 'destination', 'destination_ref', 'status', 'processed_by_admin_id',
    ];

    protected function casts(): array
    {
        return [
            'amount' => 'decimal:2',
            // sensitive payout destination reference (bank/mobile-money id),
            // encrypted at rest via Laravel's encrypted cast.
            'destination_ref' => 'encrypted',
        ];
    }

    public function driver(): BelongsTo
    {
        return $this->belongsTo(Driver::class);
    }

    public function processedByAdmin(): BelongsTo
    {
        return $this->belongsTo(AdminUser::class, 'processed_by_admin_id');
    }
}
