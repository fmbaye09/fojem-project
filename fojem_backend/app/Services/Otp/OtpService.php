<?php

namespace App\Services\Otp;

use App\Models\OtpCode;
use App\Support\SenegalPhone;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

/**
 * Codes de connexion à 6 chiffres envoyés par WhatsApp ou SMS.
 *
 * - un seul code valable à la fois par numéro, pendant 10 minutes ;
 * - un nouveau code au plus toutes les 60 s, et 5 par heure ;
 * - 5 essais par code ;
 * - le code n'est jamais stocké en clair (HMAC avec la clé de l'appli).
 *
 * Un nouveau client dont le numéro est vérifié reçoit un jeton d'inscription
 * valable 30 minutes, échangé contre son compte une fois son nom donné.
 */
class OtpService
{
    public const CODE_LENGTH = 6;

    public const TTL_MINUTES = 10;

    public const RESEND_SECONDS = 60;

    public const MAX_SENDS_PER_HOUR = 5;

    public const MAX_ATTEMPTS = 5;

    public const SIGNUP_MINUTES = 30;

    public function __construct(private readonly OtpSender $sender)
    {
    }

    /** Crée et envoie un code au numéro ; renvoie le code en clair (voir exposesCodes). */
    public function send(string $phoneNumber, string $channel, ?string $ip = null): string
    {
        $last = OtpCode::where('phone_number', $phoneNumber)->latest('id')->first();
        if ($last !== null) {
            $elapsed = abs($last->created_at->diffInSeconds(now()));
            if ($elapsed < self::RESEND_SECONDS) {
                $wait = max(1, (int) ceil(self::RESEND_SECONDS - $elapsed));
                throw ValidationException::withMessages([
                    'phone_number' => ["Patientez {$wait} s avant de demander un nouveau code."],
                ]);
            }
        }

        $sentLastHour = OtpCode::where('phone_number', $phoneNumber)
            ->where('created_at', '>', now()->subHour())
            ->count();
        if ($sentLastHour >= self::MAX_SENDS_PER_HOUR) {
            throw ValidationException::withMessages([
                'phone_number' => ['Trop de codes demandés pour ce numéro. Réessayez dans une heure.'],
            ]);
        }

        $testCode = $this->testCodeFor($phoneNumber);
        $code = $testCode ?? $this->randomCode();

        DB::transaction(function () use ($phoneNumber, $channel, $ip, $code) {
            // Un seul code valable à la fois : les précédents sont fermés.
            OtpCode::where('phone_number', $phoneNumber)
                ->whereNull('used_at')
                ->whereNull('verified_at')
                ->update(['used_at' => now()]);

            OtpCode::create([
                'phone_number' => $phoneNumber,
                'code_hash' => $this->hash($code),
                'channel' => $channel,
                'expires_at' => now()->addMinutes(self::TTL_MINUTES),
                'ip_address' => $ip,
            ]);
        });

        // Numéros de test (testeurs, validation des stores) : code fixe, aucun envoi.
        if ($testCode === null) {
            $this->sender->send($phoneNumber, $code, $channel);
        }

        return $code;
    }

    /** Vérifie le code saisi ; erreur de validation sur `code` sinon. */
    public function verify(string $phoneNumber, string $code): OtpCode
    {
        // Le résultat sort de la transaction avant toute erreur, pour que
        // l'essai raté reste compté.
        [$outcome, $otp] = DB::transaction(function () use ($phoneNumber, $code) {
            $otp = OtpCode::where('phone_number', $phoneNumber)
                ->whereNull('used_at')
                ->whereNull('verified_at')
                ->latest('id')
                ->lockForUpdate()
                ->first();

            if ($otp === null || $otp->expires_at->isPast()) {
                return ['expired', null];
            }
            if ($otp->attempts >= self::MAX_ATTEMPTS) {
                return ['locked', $otp];
            }
            if (! hash_equals($otp->code_hash, $this->hash($code))) {
                $otp->increment('attempts');

                return ['wrong', $otp];
            }

            $otp->update(['verified_at' => now()]);

            return ['ok', $otp];
        });

        if ($outcome === 'ok') {
            return $otp;
        }

        $left = $otp ? self::MAX_ATTEMPTS - $otp->attempts : 0;
        $message = match (true) {
            $outcome === 'expired' => 'Ce code a expiré. Demandez-en un nouveau.',
            $left <= 0 => 'Trop d’essais avec ce code. Demandez-en un nouveau.',
            default => 'Code incorrect. Il vous reste '.$left.' essai'.($left > 1 ? 's' : '').'.',
        };

        throw ValidationException::withMessages(['code' => [$message]]);
    }

    /** Jeton remis à un nouveau client pour créer son compte avec ce numéro vérifié. */
    public function startSignup(OtpCode $otp): string
    {
        $token = Str::random(48);
        $otp->update(['signup_token_hash' => hash('sha256', $token)]);

        return $token;
    }

    /** Le code vérifié derrière un jeton d'inscription encore valable. */
    public function signupFor(string $token): OtpCode
    {
        $otp = OtpCode::where('signup_token_hash', hash('sha256', $token))->whereNull('used_at')->first();

        if ($otp === null || $otp->verified_at === null
            || $otp->verified_at->lt(now()->subMinutes(self::SIGNUP_MINUTES))) {
            throw ValidationException::withMessages([
                'signup_token' => ['Cette vérification a expiré. Recommencez avec votre numéro.'],
            ]);
        }

        return $otp;
    }

    /** Le code a servi : connexion faite ou compte créé. */
    public function close(OtpCode $otp): void
    {
        $otp->update(['used_at' => now()]);
    }

    /**
     * En local, avec l'envoi factice, l'appli reçoit le code dans la réponse
     * pour se tester sans WhatsApp ni SMS. Jamais ailleurs.
     */
    public function exposesCodes(): bool
    {
        return config('services.otp.driver') === 'log' && app()->environment('local');
    }

    private function randomCode(): string
    {
        return str_pad((string) random_int(0, 10 ** self::CODE_LENGTH - 1), self::CODE_LENGTH, '0', STR_PAD_LEFT);
    }

    private function hash(string $code): string
    {
        return hash_hmac('sha256', $code, (string) config('app.key'));
    }

    /** OTP_TEST_NUMBERS="+221700000902:123456,…" : numéros à code fixe, sans envoi. */
    private function testCodeFor(string $phoneNumber): ?string
    {
        foreach (explode(',', (string) config('services.otp.test_numbers')) as $pair) {
            [$number, $code] = array_pad(explode(':', trim($pair), 2), 2, '');
            if ($number !== '' && SenegalPhone::normalize($number) === $phoneNumber && preg_match('/^\d{6}$/', $code)) {
                return $code;
            }
        }

        return null;
    }
}
