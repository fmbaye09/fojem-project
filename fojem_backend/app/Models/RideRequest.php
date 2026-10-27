<?php

namespace App\Models;

use App\Concerns\HasGeoPoints;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Facades\DB;

class RideRequest extends Model
{
    use HasGeoPoints, HasUuids, SoftDeletes;

    public const STATUS_SEARCHING = 'searching';
    public const STATUS_MATCHED = 'matched';
    public const STATUS_CANCELLED = 'cancelled';
    public const STATUS_EXPIRED = 'expired';

    protected $fillable = [
        'passenger_id', 'requested_at', 'status', 'women_only',
        'origin_name', 'destination_name',
    ];

    protected $appends = [
        'origin_name',
        'destination_name',
    ];

    protected function casts(): array
    {
        return [
            'requested_at' => 'datetime',
            'women_only' => 'boolean',
            'origin_lat' => 'float',
            'origin_lng' => 'float',
            'destination_lat' => 'float',
            'destination_lng' => 'float',
        ];
    }

    public function getOriginNameAttribute(?string $value): string
    {
        if (!empty($value)) {
            return $value;
        }

        return Trip::closestCity($this->origin_lat, $this->origin_lng);
    }

    public function getDestinationNameAttribute(?string $value): string
    {
        if (!empty($value)) {
            return $value;
        }

        return Trip::closestCity($this->destination_lat, $this->destination_lng);
    }

    public function setOriginPoint(float $lat, float $lng): static
    {
        return $this->setPointAttribute('origin_geom', $lat, $lng);
    }

    public function setDestinationPoint(float $lat, float $lng): static
    {
        return $this->setPointAttribute('destination_geom', $lat, $lng);
    }

    public function passenger(): BelongsTo
    {
        return $this->belongsTo(User::class, 'passenger_id');
    }

    public function bookings(): HasMany
    {
        return $this->hasMany(Booking::class);
    }

    public function matchingScores(): HasMany
    {
        return $this->hasMany(MatchingScore::class);
    }

    public function scopeWithLatLng(Builder $query): Builder
    {
        return $query->addSelect([
            'ride_requests.*',
            DB::raw('ST_Y(origin_geom::geometry) as origin_lat'),
            DB::raw('ST_X(origin_geom::geometry) as origin_lng'),
            DB::raw('ST_Y(destination_geom::geometry) as destination_lat'),
            DB::raw('ST_X(destination_geom::geometry) as destination_lng'),
        ]);
    }

    /**
     * Open ride requests whose origin lies within $radiusMeters of a trip's
     * origin - used when a driver looks for nearby passengers wanting a lift.
     */
    public function scopeNearPoint(Builder $query, float $lat, float $lng, int $radiusMeters = 15000): Builder
    {
        return $query->whereRaw(
            'ST_DWithin(origin_geom, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)',
            [$lng, $lat, $radiusMeters]
        );
    }
}
