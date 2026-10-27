<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;

class LuggagePhoto extends Model
{
    use HasUuids, SoftDeletes;

    protected $fillable = ['booking_id', 'photo_url', 'uploaded_at'];

    protected function casts(): array
    {
        return ['uploaded_at' => 'datetime'];
    }

    public function getPhotoUrlAttribute($value): ?string
    {
        if (! $value) {
            return null;
        }
        if (str_starts_with($value, 'http://') || str_starts_with($value, 'https://')) {
            return $value;
        }
        return url('/storage/' . ltrim($value, '/'));
    }

    public function booking(): BelongsTo
    {
        return $this->belongsTo(Booking::class);
    }
}
