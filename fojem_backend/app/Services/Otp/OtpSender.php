<?php

namespace App\Services\Otp;

/**
 * Envoi d'un code de connexion. Le canal (WhatsApp ou SMS) est choisi par
 * le client ; l'implémentation se choisit par OTP_DRIVER (voir
 * AppServiceProvider). Brancher un fournisseur ne touche que cette couche.
 */
interface OtpSender
{
    /**
     * @param  string  $phoneNumber  format +221XXXXXXXXX
     * @param  string  $channel  whatsapp | sms
     */
    public function send(string $phoneNumber, string $code, string $channel): void;
}
