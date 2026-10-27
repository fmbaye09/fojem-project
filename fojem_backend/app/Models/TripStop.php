<?php

namespace App\Models;

use App\Concerns\HasGeoPoints;
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
        'trip_id', 'position', 'name', 'address', 'lat', 'lng', 'scheduled_at', 'price_from_origin',
    ];

    protected $hidden = ['location_geom', 'created_at', 'updated_at'];

    protected function casts(): array
    {
        return [
            'position' => 'integer',
            'lat' => 'float',
            'lng' => 'float',
            'scheduled_at' => 'datetime',
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
}
