<?php

namespace App\Services\Otp;

use Illuminate\Support\Facades\Log;

/**
 * Développement : le code n'est envoyé à personne, il est écrit dans le
 * journal Laravel (et renvoyé à l'appli en local, voir OtpService::exposesCodes).
 */
class LogOtpSender implements OtpSender
{
    public function send(string $phoneNumber, string $code, string $channel): void
    {
        Log::info("Code de connexion FOJËM pour {$phoneNumber} ({$channel}) : {$code}");
    }
}
