<?php

namespace App\Models;

use App\Concerns\HasGeoPoints;
use Carbon\CarbonImmutable;
use Carbon\CarbonInterface;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * A meeting point set by the driver (departure, intermediate stop or
 * arrival). Passengers board and leave only at these points.
 */
class TripStop extends Model
{
    use HasGeoPoints, HasUuids;

    protected $fillable = [
        'trip_id', 'position', 'name', 'address', 'lat', 'lng', 'scheduled_at', 'reached_at', 'left_at', 'price_from_origin',
    ];

    protected $hidden = ['location_geom', 'created_at', 'updated_at'];

    /** Heure limite d'attente du chauffeur, lue par les deux apps (compte à rebours). */
    protected $appends = ['wait_until'];

    /** Attente minimale du chauffeur au point de rendez-vous avant une absence. */
    public const WAIT_MINUTES = 5;

    protected function casts(): array
    {
        return [
            'position' => 'integer',
            'lat' => 'float',
            'lng' => 'float',
            'scheduled_at' => 'datetime',
            // First GPS fix of the driver at this stop (TripProgressService).
            'reached_at' => 'datetime',
            // First fix away from it afterwards, trip under way: he left.
            'left_at' => 'datetime',
            'price_from_origin' => 'decimal:2',
        ];
    }

    /** Keeps the PostGIS point used by search in sync with lat/lng. */
    protected static function booted(): void
    {
        static::saving(function (TripStop $stop) {
            if ($stop->isDirty(['lat', 'lng'])) {
                $stop->setPointAttribute('location_geom', (float) $stop->lat, (float) $stop->lng);
            }
        });
    }

    public function trip(): BelongsTo
    {
        return $this->belongsTo(Trip::class);
    }

    /**
     * Jusqu'à quand le chauffeur attend ses passagers à cet arrêt : 5 min
     * après l'heure prévue, ou après son arrivée s'il est en retard. Null
     * tant qu'il n'y est pas arrivé.
     */
    public function waitUntil(?CarbonInterface $fallbackScheduled = null): ?CarbonImmutable
    {
        if ($this->reached_at === null) {
            return null;
        }
        $from = CarbonImmutable::instance($this->reached_at);
        $scheduled = $this->scheduled_at ?? $fallbackScheduled;
        if ($scheduled !== null && $from->lessThan($scheduled)) {
            $from = CarbonImmutable::instance($scheduled);
        }

        return $from->addMinutes(self::WAIT_MINUTES);
    }

    public function getWaitUntilAttribute(): ?string
    {
        return $this->waitUntil()?->toIso8601String();
    }
}
