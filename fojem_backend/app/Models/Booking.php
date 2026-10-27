<?php

namespace App\Models;

use App\Concerns\HasGeoPoints;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Database\Eloquent\SoftDeletes;

class Booking extends Model
{
    use HasGeoPoints, HasUuids, SoftDeletes;

    public const STATUS_PENDING_DRIVER = 'pending_driver';
    public const STATUS_CONFIRMED = 'confirmed';
    public const STATUS_REJECTED = 'rejected';
    public const STATUS_CANCELLED_PASSENGER = 'cancelled_passenger';
    public const STATUS_CANCELLED_DRIVER = 'cancelled_driver';
    public const STATUS_COMPLETED = 'completed';
    public const STATUS_NO_SHOW = 'no_show';

    protected $fillable = [
        'trip_id', 'ride_request_id', 'passenger_id', 'seat_count', 'seat_numbers', 'has_heavy_luggage', 'status',
        'departure_code', 'price_charged', 'confirmed_at', 'started_at', 'completed_at',
    ];

    protected $appends = ['luggage_photos'];

    protected function casts(): array
    {
        return [
            'price_charged' => 'decimal:2',
            'seat_numbers' => 'array',
            'has_heavy_luggage' => 'boolean',
            'confirmed_at' => 'datetime',
            'started_at' => 'datetime',
            'completed_at' => 'datetime',
        ];
    }

    public function getLuggagePhotosAttribute()
    {
        return $this->relationLoaded('luggagePhotos')
            ? $this->getRelation('luggagePhotos')
            : $this->luggagePhotos()->get();
    }

    /**
     * Statuses during which a booking keeps its seats on the vehicle plan.
     * A pending request already holds its seats so two passengers can't
     * pick the same one while the driver decides.
     */
    public const SEAT_HOLDING_STATUSES = [
        self::STATUS_PENDING_DRIVER,
        self::STATUS_CONFIRMED,
        self::STATUS_COMPLETED,
    ];

    /**
     * Seat ids currently held on a trip, across all passengers.
     *
     * @return list<string>
     */
    public static function occupiedSeatNumbers(string $tripId): array
    {
        return static::where('trip_id', $tripId)
            ->whereIn('status', self::SEAT_HOLDING_STATUSES)
            ->whereNotNull('seat_numbers')
            ->pluck('seat_numbers')
            ->flatten()
            ->map(fn ($seat) => (string) $seat)
            ->unique()
            ->values()
            ->all();
    }

    public function setPickupPoint(float $lat, float $lng): static
    {
        return $this->setPointAttribute('pickup_point_geom', $lat, $lng);
    }

    public function trip(): BelongsTo
    {
        return $this->belongsTo(Trip::class);
    }

    public function rideRequest(): BelongsTo
    {
        return $this->belongsTo(RideRequest::class);
    }

    public function passenger(): BelongsTo
    {
        return $this->belongsTo(User::class, 'passenger_id');
    }

    public function luggagePhotos(): HasMany
    {
        return $this->hasMany(LuggagePhoto::class);
    }

    public function review(): HasOne
    {
        return $this->hasOne(Review::class);
    }

    public function transactions(): HasMany
    {
        return $this->hasMany(Transaction::class);
    }

    public function disputes(): HasMany
    {
        return $this->hasMany(Dispute::class);
    }

    public static function generateDepartureCode(): string
    {
        return str_pad((string) random_int(0, 9999), 4, '0', STR_PAD_LEFT);
    }
}
