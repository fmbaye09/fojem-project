<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;

class MatchingScore extends Model
{
    use HasUuids, SoftDeletes;

    protected $fillable = [
        'ride_request_id', 'trip_id', 'compatibility_score',
        'detour_distance_m', 'detour_duration_s', 'computed_at',
    ];

    protected function casts(): array
    {
        return [
            'compatibility_score' => 'decimal:2',
            'computed_at' => 'datetime',
        ];
    }

    public function rideRequest(): BelongsTo
    {
        return $this->belongsTo(RideRequest::class);
    }

    public function trip(): BelongsTo
    {
        return $this->belongsTo(Trip::class);
    }
}
