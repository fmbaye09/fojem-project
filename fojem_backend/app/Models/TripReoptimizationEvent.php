<?php

namespace App\Models;

use App\Concerns\HasGeoPoints;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;

class TripReoptimizationEvent extends Model
{
    use HasGeoPoints, HasUuids, SoftDeletes;

    protected $fillable = [
        'trip_id', 'freed_at', 'candidate_type', 'matched_booking_id',
    ];

    protected function casts(): array
    {
        return ['freed_at' => 'datetime'];
    }

    public function setFreedAtPoint(float $lat, float $lng): static
    {
        return $this->setPointAttribute('freed_at_geom', $lat, $lng);
    }

    public function trip(): BelongsTo
    {
        return $this->belongsTo(Trip::class);
    }

    public function matchedBooking(): BelongsTo
    {
        return $this->belongsTo(Booking::class, 'matched_booking_id');
    }
}
