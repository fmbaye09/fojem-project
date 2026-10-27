<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;

class Notification extends Model
{
    use HasUuids, SoftDeletes;

    protected $table = 'notifications';

    protected $fillable = ['user_id', 'type', 'title', 'payload', 'sent_at', 'read_at'];

    // ---- Notification types ----
    const TYPE_BOOKING_NEW          = 'booking_new';
    const TYPE_BOOKING_CONFIRMED    = 'booking_confirmed';
    const TYPE_BOOKING_REJECTED     = 'booking_rejected';
    const TYPE_BOOKING_CANCELLED    = 'booking_cancelled';
    const TYPE_BOOKING_COMPLETED    = 'booking_completed';
    const TYPE_TRIP_CANCELLED       = 'trip_cancelled';
    const TYPE_DOCUMENT_STATUS      = 'document_status';
    const TYPE_CHAT_MESSAGE         = 'chat_message';
    const TYPE_SYSTEM               = 'system';
    const TYPE_DRIVER_NEARBY        = 'driver_nearby';
    const TYPE_ARRIVAL_IMMINENT     = 'arrival_imminent';
    const TYPE_CANCELLATION         = 'cancellation';
    const TYPE_ALTERNATIVE_FOUND    = 'alternative_found';
    const TYPE_RECURRING_MATCH      = 'recurring_match';
    const TYPE_SOS                  = 'sos';

    protected function casts(): array
    {
        return [
            'payload' => 'array',
            'sent_at' => 'datetime',
            'read_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
