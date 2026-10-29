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
        'trip_id', 'boarding_stop_id', 'alighting_stop_id', 'ride_request_id', 'passenger_id',
        'seat_count', 'seat_numbers', 'has_heavy_luggage', 'status',
        'departure_code', 'price_charged', 'confirmed_at', 'started_at', 'completed_at',
        'passenger_lat', 'passenger_lng', 'passenger_location_at', 'share_token', 'share_expires_at',
    ];

    /** Au-delà, la position partagée par le passager n'est plus montrée. */
    public const PASSENGER_LOCATION_FRESH_SECONDS = 180;

    protected $appends = ['luggage_photos', 'passenger_location'];

    // Position brute et lien de partage : exposés uniquement via leurs routes.
    protected $hidden = ['passenger_lat', 'passenger_lng', 'passenger_location_at', 'share_token', 'share_expires_at'];

    /** Where the passenger boards and leaves: shown on every booking. */
    protected $with = ['boardingStop', 'alightingStop'];

    protected function casts(): array
    {
        return [
            'price_charged' => 'decimal:2',
            'seat_numbers' => 'array',
            'has_heavy_luggage' => 'boolean',
            'confirmed_at' => 'datetime',
            'started_at' => 'datetime',
            'completed_at' => 'datetime',
            'passenger_location_at' => 'datetime',
            'share_expires_at' => 'datetime',
        ];
    }

    /**
     * Position partagée par le passager, si elle est récente et qu'il n'est
     * pas encore à bord (après l'embarquement, le chauffeur n'en a plus besoin).
     */
    public function getPassengerLocationAttribute(): ?array
    {
        $at = $this->passenger_location_at;
        if ($this->passenger_lat === null || ! $at || $this->started_at
            || $at->diffInSeconds(now(), true) > self::PASSENGER_LOCATION_FRESH_SECONDS) {
            return null;
        }

        return ['lat' => (float) $this->passenger_lat, 'lng' => (float) $this->passenger_lng, 'updated_at' => $at->toIso8601String()];
    }

    /** Le lien de suivi est valable jusqu'à sa date d'expiration, tant que la réservation tient. */
    public function shareIsActive(): bool
    {
        return $this->share_token !== null
            && $this->share_expires_at?->isFuture()
            && in_array($this->status, [self::STATUS_PENDING_DRIVER, self::STATUS_CONFIRMED], true);
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

    public function boardingStop(): BelongsTo
    {
        return $this->belongsTo(TripStop::class, 'boarding_stop_id');
    }

    public function alightingStop(): BelongsTo
    {
        return $this->belongsTo(TripStop::class, 'alighting_stop_id');
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
