<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

class Driver extends Model
{
    use HasUuids, SoftDeletes;

    public const STATUS_PENDING = 'pending';
    public const STATUS_APPROVED = 'approved';
    public const STATUS_REJECTED = 'rejected';

    protected $fillable = [
        'user_id', 'verification_status', 'verified_at', 'verified_by_admin_id',
        'average_rating', 'total_trips_completed',
        'pending_vehicle_brand', 'pending_vehicle_model', 'pending_vehicle_color',
        'pending_vehicle_plate_number', 'pending_vehicle_seat_count',
    ];

    protected $appends = [
        'has_submitted_documents',
        'documents_count',
    ];

    public function getHasSubmittedDocumentsAttribute(): bool
    {
        return $this->documents()->exists();
    }

    public function getDocumentsCountAttribute(): int
    {
        return $this->documents()->count();
    }

    protected function casts(): array
    {
        return [
            'verified_at' => 'datetime',
            'average_rating' => 'float',
            'total_trips_completed' => 'integer',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function verifiedByAdmin(): BelongsTo
    {
        return $this->belongsTo(AdminUser::class, 'verified_by_admin_id');
    }

    public function documents(): HasMany
    {
        return $this->hasMany(DriverDocument::class);
    }

    public function vehicles(): HasMany
    {
        return $this->hasMany(Vehicle::class);
    }

    public function trips(): HasMany
    {
        return $this->hasMany(Trip::class);
    }

    public function payoutRequests(): HasMany
    {
        return $this->hasMany(PayoutRequest::class);
    }

    public function isApproved(): bool
    {
        return $this->verification_status === self::STATUS_APPROVED;
    }
}
