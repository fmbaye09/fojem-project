<?php

namespace App\Models;

use App\Concerns\HasGeoPoints;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Lieu de rendez-vous connu d'OpenStreetMap (OverpassService), suggéré aux
 * chauffeurs qui publient un trajet passant à côté.
 */
class MeetingPlace extends Model
{
    use HasGeoPoints, HasUuids;

    protected $fillable = ['osm_id', 'kind', 'name', 'address', 'lat', 'lng'];

    protected $hidden = ['location_geom'];

    protected function casts(): array
    {
        return [
            'lat' => 'float',
            'lng' => 'float',
        ];
    }

    protected static function booted(): void
    {
        static::saving(function (MeetingPlace $place) {
            if ($place->isDirty(['lat', 'lng'])) {
                $place->setPointAttribute('location_geom', (float) $place->lat, (float) $place->lng);
            }
        });
    }
}
