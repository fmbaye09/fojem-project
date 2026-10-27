<?php

namespace App\Models;

use App\Concerns\HasGeoPoints;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

class Trip extends Model
{
    use HasGeoPoints, HasUuids, SoftDeletes;

    public const STATUS_OPEN = 'open';
    public const STATUS_FULL = 'full';
    public const STATUS_IN_PROGRESS = 'in_progress';
    public const STATUS_COMPLETED = 'completed';
    public const STATUS_CANCELLED = 'cancelled';

    protected $fillable = [
        'driver_id', 'vehicle_id', 'departure_type', 'scheduled_at',
        'price_per_seat', 'toll_fees', 'seats_available', 'is_recurring',
        'recurrence_rule', 'status', 'closed_by', 'women_only',
        'origin_name', 'destination_name',
        'current_lat', 'current_lng', 'current_heading', 'location_updated_at', 'waypoints',
    ];

    protected $appends = [
        'origin_name',
        'destination_name',
    ];

    protected function casts(): array
    {
        return [
            'scheduled_at' => 'datetime',
            'location_updated_at' => 'datetime',
            'price_per_seat' => 'decimal:2',
            'toll_fees' => 'decimal:2',
            'is_recurring' => 'boolean',
            'women_only' => 'boolean',
            'origin_lat' => 'float',
            'origin_lng' => 'float',
            'destination_lat' => 'float',
            'destination_lng' => 'float',
            'current_lat' => 'float',
            'current_lng' => 'float',
            'current_heading' => 'float',
            'waypoints' => 'array',
        ];
    }

    public const CITIES = [
        'Dakar' => ['lat' => 14.6928, 'lng' => -17.4467],
        'Thiès' => ['lat' => 14.7910, 'lng' => -16.9359],
        'Mbour' => ['lat' => 14.4198, 'lng' => -16.9641],
        'Saint-Louis' => ['lat' => 16.0179, 'lng' => -16.4896],
        'Ziguinchor' => ['lat' => 12.5665, 'lng' => -16.2733],
        'Kaolack' => ['lat' => 14.1652, 'lng' => -16.0726],
        'Tambacounda' => ['lat' => 13.7707, 'lng' => -13.6673],
        'Touba' => ['lat' => 14.8500, 'lng' => -15.8833],
        'Diourbel' => ['lat' => 14.6559, 'lng' => -16.2333],
        'Louga' => ['lat' => 15.6173, 'lng' => -16.2240],
        'Fatick' => ['lat' => 14.3390, 'lng' => -16.4110],
        'Kolda' => ['lat' => 12.8983, 'lng' => -14.9412],
        'Sédhiou' => ['lat' => 12.7081, 'lng' => -15.5569],
        'Kaffrine' => ['lat' => 14.1059, 'lng' => -15.5508],
        'Kédougou' => ['lat' => 12.5556, 'lng' => -12.1746],
        'Matam' => ['lat' => 15.6559, 'lng' => -13.2548],
    ];

    public static function closestCity(?float $lat, ?float $lng): string
    {
        if ($lat === null || $lng === null || ($lat == 0 && $lng == 0)) {
            return 'Dakar';
        }

        $closest = 'Dakar';
        $minDist = PHP_FLOAT_MAX;

        foreach (self::CITIES as $name => $coords) {
            $dLat = $coords['lat'] - $lat;
            $dLng = $coords['lng'] - $lng;
            $dist = ($dLat * $dLat) + ($dLng * $dLng);
            if ($dist < $minDist) {
                $minDist = $dist;
                $closest = $name;
            }
        }

        return $closest;
    }

    public function getOriginNameAttribute(?string $value): string
    {
        if (!empty($value)) {
            return $value;
        }

        return self::closestCity($this->origin_lat, $this->origin_lng);
    }

    public function getDestinationNameAttribute(?string $value): string
    {
        if (!empty($value)) {
            return $value;
        }

        return self::closestCity($this->destination_lat, $this->destination_lng);
    }

    public function setOriginPoint(float $lat, float $lng): static
    {
        return $this->setPointAttribute('origin_geom', $lat, $lng);
    }

    public function setDestinationPoint(float $lat, float $lng): static
    {
        return $this->setPointAttribute('destination_geom', $lat, $lng);
    }

    public function driverProfile(): BelongsTo
    {
        return $this->belongsTo(Driver::class, 'driver_id');
    }

    public function vehicle(): BelongsTo
    {
        return $this->belongsTo(Vehicle::class);
    }

    public function bookings(): HasMany
    {
        return $this->hasMany(Booking::class);
    }

    public function matchingScores(): HasMany
    {
        return $this->hasMany(MatchingScore::class);
    }

    public function reoptimizationEvents(): HasMany
    {
        return $this->hasMany(TripReoptimizationEvent::class);
    }

    /** Adds origin_lat/origin_lng/destination_lat/destination_lng to the select. */
    public function scopeWithLatLng(Builder $query): Builder
    {
        return $query->addSelect([
            'trips.*',
            \Illuminate\Support\Facades\DB::raw('ST_Y(origin_geom::geometry) as origin_lat'),
            \Illuminate\Support\Facades\DB::raw('ST_X(origin_geom::geometry) as origin_lng'),
            \Illuminate\Support\Facades\DB::raw('ST_Y(destination_geom::geometry) as destination_lat'),
            \Illuminate\Support\Facades\DB::raw('ST_X(destination_geom::geometry) as destination_lng'),
        ]);
    }

    /**
     * Trips whose origin AND destination both lie within $radiusMeters of
     * the given search points. Used by the public trip search endpoint.
     */
    public function scopeNear(Builder $query, float $originLat, float $originLng, float $destLat, float $destLng, int $radiusMeters = 5000): Builder
    {
        return $query
            ->whereRaw(
                'ST_DWithin(origin_geom, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)',
                [$originLng, $originLat, $radiusMeters]
            )
            ->whereRaw(
                'ST_DWithin(destination_geom, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)',
                [$destLng, $destLat, $radiusMeters]
            );
    }

    /**
     * Great-circle distance in meters between two WGS84 points.
     */
    public static function haversineMeters(float $lat1, float $lng1, float $lat2, float $lng2): float
    {
        $earthRadius = 6371000.0;
        $dLat = deg2rad($lat2 - $lat1);
        $dLng = deg2rad($lng2 - $lng1);
        $a = sin($dLat / 2) ** 2
            + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * (sin($dLng / 2) ** 2);
        return 2 * $earthRadius * asin(min(1.0, sqrt($a)));
    }

    /**
     * Checks if the ordered path [origin, ...waypoints, destination] passes within
     * $radiusMeters of ($originLat, $originLng) and later within $radiusMeters of ($destLat, $destLng).
     */
    public function matchesPathWithWaypoints(float $originLat, float $originLng, float $destLat, float $destLng, float $radiusMeters = 15000): bool
    {
        $path = [];
        if ($this->origin_lat !== null && $this->origin_lng !== null) {
            $path[] = ['lat' => (float) $this->origin_lat, 'lng' => (float) $this->origin_lng];
        }
        if (is_array($this->waypoints)) {
            foreach ($this->waypoints as $wp) {
                if (isset($wp['lat'], $wp['lng'])) {
                    $path[] = ['lat' => (float) $wp['lat'], 'lng' => (float) $wp['lng']];
                }
            }
        }
        if ($this->destination_lat !== null && $this->destination_lng !== null) {
            $path[] = ['lat' => (float) $this->destination_lat, 'lng' => (float) $this->destination_lng];
        }

        if (count($path) < 2) {
            return false;
        }

        $bestOriginIdx = -1;
        $bestOriginDist = PHP_FLOAT_MAX;
        foreach ($path as $i => $pt) {
            $d = self::haversineMeters($originLat, $originLng, $pt['lat'], $pt['lng']);
            if ($d < $bestOriginDist) {
                $bestOriginDist = $d;
                $bestOriginIdx = $i;
            }
        }

        if ($bestOriginIdx === -1 || $bestOriginDist > $radiusMeters) {
            return false;
        }

        $bestDestIdx = -1;
        $bestDestDist = PHP_FLOAT_MAX;
        for ($i = $bestOriginIdx + 1; $i < count($path); $i++) {
            $d = self::haversineMeters($destLat, $destLng, $path[$i]['lat'], $path[$i]['lng']);
            if ($d < $bestDestDist) {
                $bestDestDist = $d;
                $bestDestIdx = $i;
            }
        }

        return $bestDestIdx !== -1 && $bestDestDist <= $radiusMeters;
    }
}
