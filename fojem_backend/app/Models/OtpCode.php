<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\MassPrunable;
use Illuminate\Database\Eloquent\Model;

/** Code de connexion envoyé par WhatsApp ou SMS (voir OtpService). */
class OtpCode extends Model
{
    use MassPrunable;

    protected $fillable = [
        'phone_number',
        'code_hash',
        'channel',
        'attempts',
        'expires_at',
        'verified_at',
        'signup_token_hash',
        'used_at',
        'ip_address',
    ];

    protected $hidden = [
        'code_hash',
        'signup_token_hash',
    ];

    protected function casts(): array
    {
        return [
            'attempts' => 'integer',
            'expires_at' => 'datetime',
            'verified_at' => 'datetime',
            'used_at' => 'datetime',
        ];
    }

    /** Gardés une journée : assez pour les limites d'envoi et le support. */
    public function prunable(): Builder
    {
        return static::where('created_at', '<', now()->subDay());
    }
}
