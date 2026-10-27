<?php

namespace App\Models;

use App\Concerns\HasGeoPoints;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;

class SosAlert extends Model
{
    use HasGeoPoints, HasUuids, SoftDeletes;

    public const STATUS_OPEN = 'open';
    public const STATUS_IN_PROGRESS = 'in_progress';
    public const STATUS_RESOLVED = 'resolved';

    protected $fillable = [
        'user_id', 'booking_id', 'triggered_at', 'status',
        'handled_by_admin_id', 'resolution_notes',
    ];

    protected function casts(): array
    {
        return ['triggered_at' => 'datetime'];
    }

    public function setLocationPoint(float $lat, float $lng): static
    {
        return $this->setPointAttribute('location_geom', $lat, $lng);
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function booking(): BelongsTo
    {
        return $this->belongsTo(Booking::class);
    }

    public function handledByAdmin(): BelongsTo
    {
        return $this->belongsTo(AdminUser::class, 'handled_by_admin_id');
    }
}
