<?php

namespace App\Models;

use App\Concerns\HasGeoPoints;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

class SosAlert extends Model
{
    use HasGeoPoints, HasUuids, SoftDeletes;

    public const STATUS_OPEN = 'open';
    public const STATUS_IN_PROGRESS = 'in_progress';
    public const STATUS_RESOLVED = 'resolved';

    public const ROLE_PASSENGER = 'passenger';
    public const ROLE_DRIVER = 'driver';

    /** Nombre de points gardés dans le parcours affiché à l'admin. */
    private const PATH_MAX_POINTS = 300;

    protected $fillable = [
        'user_id', 'booking_id', 'trip_id', 'role', 'triggered_at', 'status',
        'handled_by_admin_id', 'resolution_notes',
        'last_lat', 'last_lng', 'last_location_at', 'path', 'ended_at', 'notified_at',
    ];

    protected $hidden = ['location_geom'];

    protected function casts(): array
    {
        return [
            'triggered_at' => 'datetime',
            'last_location_at' => 'datetime',
            'ended_at' => 'datetime',
            'notified_at' => 'datetime',
            'last_lat' => 'float',
            'last_lng' => 'float',
            'path' => 'array',
        ];
    }

    public function setLocationPoint(float $lat, float $lng): static
    {
        return $this->setPointAttribute('location_geom', $lat, $lng);
    }

    /** Dernière position connue, ajoutée au parcours (les plus récents gardés). */
    public function recordPosition(float $lat, float $lng): static
    {
        $path = $this->path ?? [];
        $path[] = [round($lat, 6), round($lng, 6), now()->toIso8601String()];

        $this->fill([
            'last_lat' => $lat,
            'last_lng' => $lng,
            'last_location_at' => now(),
            'path' => array_slice($path, -self::PATH_MAX_POINTS),
        ]);

        return $this;
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function booking(): BelongsTo
    {
        return $this->belongsTo(Booking::class);
    }

    public function trip(): BelongsTo
    {
        return $this->belongsTo(Trip::class);
    }

    public function recordings(): HasMany
    {
        return $this->hasMany(SosRecording::class)->oldest();
    }

    public function handledByAdmin(): BelongsTo
    {
        return $this->belongsTo(AdminUser::class, 'handled_by_admin_id');
    }
}
