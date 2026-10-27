<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;
use LogicException;

/**
 * A vehicle declared by a driver.
 *
 * IMMUTABILITY (anti-fraud): once created, `plate_number`, `brand`, `model`,
 * `color` and `seat_count` can never change. This is a deliberate product
 * decision, not an oversight - there is no `PATCH /api/vehicles/{id}`
 * route, and this is enforced here too (not just by omission of a route)
 * so no future controller/service/tinker session can silently mutate a
 * verified vehicle's identity. Without this, a chauffeur could get a nice
 * vehicle verified and then quietly swap in an unverified one under the
 * same `vehicles` row. Only technical bookkeeping columns
 * (`updated_at`, `deleted_at`) and `is_active` (used to deactivate a
 * vehicle, e.g. sold/retired - never to redefine it) may be updated after
 * creation. Need to correct a mistake? Soft-delete the row and declare a
 * new vehicle instead.
 */
class Vehicle extends Model
{
    use HasUuids, SoftDeletes;

    protected $fillable = [
        'driver_id', 'plate_number', 'brand', 'model', 'color', 'seat_count', 'is_active',
    ];

    /** Columns that remain mutable after the vehicle has been created. */
    private const MUTABLE_AFTER_CREATE = ['is_active', 'updated_at', 'deleted_at'];

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
            'seat_count' => 'integer',
        ];
    }

    protected static function boot(): void
    {
        parent::boot();

        static::updating(function (Vehicle $vehicle) {
            $changedImmutableColumns = array_diff(
                array_keys($vehicle->getDirty()),
                self::MUTABLE_AFTER_CREATE
            );

            if ($changedImmutableColumns !== []) {
                throw new LogicException(
                    'Vehicle identity fields are immutable after creation: '
                    .implode(', ', $changedImmutableColumns)
                    .'. Declare a new vehicle instead of editing this one.'
                );
            }
        });
    }

    public function driver(): BelongsTo
    {
        return $this->belongsTo(Driver::class);
    }

    public function trips(): HasMany
    {
        return $this->hasMany(Trip::class);
    }
}
