<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;

class ReputationScore extends Model
{
    use SoftDeletes;

    // Primary key is user_id (1-1 with users), not an auto-generated uuid.
    protected $primaryKey = 'user_id';
    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'user_id', 'punctuality_pct', 'trips_completed_pct',
        'bookings_honored_pct', 'no_show_count', 'last_computed_at',
    ];

    protected function casts(): array
    {
        return [
            'punctuality_pct' => 'decimal:2',
            'trips_completed_pct' => 'decimal:2',
            'bookings_honored_pct' => 'decimal:2',
            'last_computed_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
