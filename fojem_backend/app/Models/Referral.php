<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;

class Referral extends Model
{
    use HasUuids, SoftDeletes;

    public const STATUS_PENDING = 'pending';
    public const STATUS_FIRST_TRIP_COMPLETED = 'first_trip_completed';
    public const STATUS_REWARDED = 'rewarded';

    protected $fillable = ['referrer_id', 'referee_id', 'status', 'rewarded_at'];

    protected function casts(): array
    {
        return ['rewarded_at' => 'datetime'];
    }

    public function referrer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'referrer_id');
    }

    public function referee(): BelongsTo
    {
        return $this->belongsTo(User::class, 'referee_id');
    }
}
