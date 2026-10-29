<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Morceau audio enregistré pendant une alerte SOS (disque privé). */
class SosRecording extends Model
{
    use HasUuids;

    protected $fillable = ['sos_alert_id', 'file_path', 'duration_ms'];

    protected $hidden = ['file_path'];

    public function sosAlert(): BelongsTo
    {
        return $this->belongsTo(SosAlert::class);
    }
}
