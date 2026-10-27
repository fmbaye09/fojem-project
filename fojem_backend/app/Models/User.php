<?php

namespace App\Models;

use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    /** @use HasFactory<UserFactory> */
    use HasApiTokens, HasFactory, HasUuids, Notifiable, SoftDeletes;

    protected $fillable = [
        'full_name',
        'email',
        'password_hash',
        'phone_number',
        'profile_photo_url',
        'gender',
        'account_status',
        'is_driver',
        'language',
        'fcm_token',
        'identity_status',
        'identity_document_type',
        'identity_document_number',
        'identity_front_url',
        'identity_back_url',
        'identity_rejection_reason',
        'identity_submitted_at',
        'identity_reviewed_at',
    ];

    protected $appends = [
        'identity_verified',
    ];

    protected $hidden = [
        'password_hash',
        'remember_token',
    ];

    /**
     * Laravel's Authenticatable contract expects a "password" attribute for
     * the auth guard/hashing helpers; we map it onto our `password_hash`
     * column so `Hash::check()` / `Auth::attempt()` keep working unchanged.
     */
    public function getAuthPassword(): string
    {
        return $this->password_hash;
    }

    protected function casts(): array
    {
        return [
            'password_hash' => 'hashed',
            'is_driver' => 'boolean',
            'identity_submitted_at' => 'datetime',
            'identity_reviewed_at' => 'datetime',
        ];
    }

    public function getIdentityVerifiedAttribute(): bool
    {
        if ($this->identity_status === 'approved') {
            return true;
        }

        // Si l'utilisateur est chauffeur et déjà validé, son identité est certifiée
        if ($this->is_driver && $this->relationLoaded('driver') && $this->driver?->verification_status === 'approved') {
            return true;
        }

        return false;
    }

    public function getIdentityFrontUrlAttribute($value): ?string
    {
        return $this->resolveMediaUrl($value);
    }

    public function getIdentityBackUrlAttribute($value): ?string
    {
        return $this->resolveMediaUrl($value);
    }

    private function resolveMediaUrl(?string $value): ?string
    {
        if (empty($value)) {
            return null;
        }

        if (str_starts_with($value, 'http://') || str_starts_with($value, 'https://')) {
            $path = parse_url($value, PHP_URL_PATH);
            if (request() && $path) {
                return request()->schemeAndHttpHost() . $path;
            }
            return $value;
        }

        return request() ? request()->schemeAndHttpHost() . '/' . ltrim($value, '/') : url($value);
    }

    public function getProfilePhotoUrlAttribute($value): ?string
    {
        if (empty($value)) {
            return null;
        }

        if (str_starts_with($value, 'http://') || str_starts_with($value, 'https://')) {
            $path = parse_url($value, PHP_URL_PATH);
            if (request() && $path) {
                return request()->schemeAndHttpHost() . $path;
            }
            return $value;
        }

        return request() ? request()->schemeAndHttpHost() . '/' . ltrim($value, '/') : url($value);
    }

    public function driver(): HasOne
    {
        return $this->hasOne(Driver::class);
    }

    public function wallet(): HasOne
    {
        return $this->hasOne(Wallet::class);
    }

    public function reputationScore(): HasOne
    {
        return $this->hasOne(ReputationScore::class);
    }

    public function authSessions(): HasMany
    {
        return $this->hasMany(AuthSession::class);
    }

    public function rideRequests(): HasMany
    {
        return $this->hasMany(RideRequest::class, 'passenger_id');
    }

    public function bookings(): HasMany
    {
        return $this->hasMany(Booking::class, 'passenger_id');
    }

    public function emergencyContacts(): HasMany
    {
        return $this->hasMany(EmergencyContact::class);
    }

    /**
     * Named to avoid colliding with Notifiable::notifications(), which
     * targets Laravel's own `notifications` table (unused here - our
     * app-level notifications live in the `notifications` model/table
     * defined by the FOJEM schema).
     */
    public function appNotifications(): HasMany
    {
        return $this->hasMany(Notification::class);
    }

    public function sosAlerts(): HasMany
    {
        return $this->hasMany(SosAlert::class);
    }
}
