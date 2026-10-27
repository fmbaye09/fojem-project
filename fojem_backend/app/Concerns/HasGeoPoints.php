<?php

namespace App\Concerns;

use Illuminate\Support\Facades\DB;

/**
 * Small helper for models that store PostGIS `geography(Point,4326)`
 * columns. Eloquent has no native geography type, so:
 *  - writing a point sets the attribute to a raw SQL expression
 *    (ST_MakePoint), which Eloquent inserts/updates literally;
 *  - reading lat/lng back requires the query to explicitly select
 *    ST_Y()/ST_X() aliases (see the `withLatLng` scope on each model),
 *    because the raw PDO value for a geography column is an opaque
 *    EWKB hex string, not something PHP can use directly.
 */
trait HasGeoPoints
{
    public function setPointAttribute(string $column, float $lat, float $lng): static
    {
        // number_format (not sprintf %F) to stay locale-independent: some
        // locales format decimals with a comma, which would corrupt the SQL.
        $lngStr = number_format($lng, 8, '.', '');
        $latStr = number_format($lat, 8, '.', '');

        $this->attributes[$column] = DB::raw(
            "ST_SetSRID(ST_MakePoint({$lngStr}, {$latStr}), 4326)::geography"
        );

        return $this;
    }
}
