<?php

namespace App\Services;

use App\Models\Notification;
use App\Models\User;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Central place to create in-app notifications and send FCM push.
 * Each public method creates a row in `notifications` and sends a
 * Firebase Cloud Messaging push notification to the user's device
 * when an FCM token is present.
 */
class NotificationService
{
    /**
     * Notify the trip's driver that a new booking request came in.
     */
    public function bookingNew(User $driver, array $bookingData): Notification
    {
        $passengerName = $bookingData['passenger_name'] ?? 'Un passager';
        $tripLabel     = $bookingData['trip_label'] ?? 'votre trajet';
        $hasHeavyLuggage = !empty($bookingData['has_heavy_luggage']);

        $message = $hasHeavyLuggage
            ? "$passengerName souhaite réserver une place sur $tripLabel (bagages lourds signalés)."
            : "$passengerName souhaite réserver une place sur $tripLabel.";

        return $this->create(
            $driver,
            Notification::TYPE_BOOKING_NEW,
            '🚗 Nouvelle réservation',
            $message,
            $bookingData,
        );
    }

    /**
     * Notify the passenger that their booking was confirmed by the driver.
     */
    public function bookingConfirmed(User $passenger, array $bookingData): Notification
    {
        $tripLabel = $bookingData['trip_label'] ?? 'votre trajet';

        return $this->create(
            $passenger,
            Notification::TYPE_BOOKING_CONFIRMED,
            '✅ Réservation confirmée',
            "Votre réservation pour $tripLabel a été confirmée. Bon voyage !",
            $bookingData,
        );
    }

    /**
     * Notify the passenger that their booking was rejected.
     */
    public function bookingRejected(User $passenger, array $bookingData): Notification
    {
        $tripLabel = $bookingData['trip_label'] ?? 'un trajet';

        return $this->create(
            $passenger,
            Notification::TYPE_BOOKING_REJECTED,
            '❌ Réservation refusée',
            "Votre demande de réservation pour $tripLabel a été refusée. Essayez un autre trajet.",
            $bookingData,
        );
    }

    /**
     * Notify the other party that a booking was cancelled.
     */
    public function bookingCancelled(User $recipient, string $cancellerName, array $bookingData): Notification
    {
        $tripLabel = $bookingData['trip_label'] ?? 'un trajet';

        return $this->create(
            $recipient,
            Notification::TYPE_BOOKING_CANCELLED,
            '🚫 Réservation annulée',
            "$cancellerName a annulé la réservation pour $tripLabel.",
            $bookingData,
        );
    }

    /**
     * Notify a passenger that the driver cancelled the whole trip.
     */
    public function tripCancelled(User $passenger, array $bookingData): Notification
    {
        $tripLabel = $bookingData['trip_label'] ?? 'votre trajet';

        return $this->create(
            $passenger,
            Notification::TYPE_TRIP_CANCELLED,
            '⚠️ Trajet annulé',
            "Le chauffeur a annulé le trajet $tripLabel. Votre réservation est annulée, recherchez un autre trajet.",
            $bookingData,
        );
    }

    /**
     * Notify the passenger that the trip is completed.
     */
    public function bookingCompleted(User $passenger, array $bookingData): Notification
    {
        $tripLabel = $bookingData['trip_label'] ?? 'votre trajet';

        return $this->create(
            $passenger,
            Notification::TYPE_BOOKING_COMPLETED,
            '🏁 Trajet terminé',
            "Votre trajet $tripLabel est terminé. N'oubliez pas de noter votre chauffeur ⭐",
            $bookingData,
        );
    }

    /** Libellés des documents du dossier chauffeur (DriverDocument::REQUIRED_TYPES). */
    private const DOCUMENT_LABELS = [
        'permis_recto' => 'permis de conduire (recto)',
        'permis_verso' => 'permis de conduire (verso)',
        'carte_grise' => 'carte grise',
        'vehicule_avant' => 'photo avant du véhicule',
        'vehicule_arriere' => 'photo arrière du véhicule',
        'vehicule_gauche' => 'photo côté gauche du véhicule',
        'vehicule_droite' => 'photo côté droit du véhicule',
        'selfie_carte_grise' => 'selfie avec la carte grise',
        'selfie_permis' => 'selfie avec le permis',
    ];

    /**
     * A document was rejected: the driver has to upload it again, so each
     * rejection is notified (approvals are not — see driverApproved()).
     */
    public function documentRejected(User $driver, string $docType, ?string $reason = null): Notification
    {
        $label = self::DOCUMENT_LABELS[$docType] ?? $docType;
        $body = "Votre $label n'a pas été accepté".($reason ? " : $reason" : '.')
            .' Envoyez-en un nouveau depuis l\'app.';

        return $this->create(
            $driver,
            Notification::TYPE_DOCUMENT_STATUS,
            '📄 Document à renvoyer',
            $body,
            ['document_type' => $docType, 'status' => 'rejected', 'driver_status' => 'rejected'],
        );
    }

    /**
     * Sent once, when the last required document is approved and the
     * driver account becomes "approved".
     */
    public function driverApproved(User $driver): Notification
    {
        return $this->create(
            $driver,
            Notification::TYPE_DOCUMENT_STATUS,
            '🎉 Compte chauffeur validé',
            'Tous vos documents sont approuvés. Vous pouvez maintenant publier vos trajets !',
            ['status' => 'approved', 'driver_status' => 'approved'],
        );
    }

    /**
     * Notify user that they received a new chat message.
     */
    public function chatMessage(User $recipient, User $sender, string $text, ?string $conversationId = null): Notification
    {
        $preview = mb_strimwidth($text, 0, 80, '...');
        return $this->create(
            $recipient,
            Notification::TYPE_CHAT_MESSAGE,
            "💬 {$sender->name}",
            $preview,
            [
                'sender_id' => $sender->id,
                'sender_name' => $sender->name,
                'conversation_id' => $conversationId,
                'message' => $text,
            ],
        );
    }

    /**
     * Generic system notification (welcome, promo, etc.).
     */
    public function system(User $user, string $title, string $body, array $extra = []): Notification
    {
        return $this->create($user, Notification::TYPE_SYSTEM, $title, $body, $extra);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Internal
    // ─────────────────────────────────────────────────────────────────────

    private function create(
        User   $user,
        string $type,
        string $title,
        string $body,
        array  $payload = [],
    ): Notification {
        $payload['type']  = $type;
        $payload['title'] = $title;
        $payload['body']  = $body;

        $notification = Notification::create([
            'user_id' => $user->id,
            'type'    => $type,
            'title'   => $title,
            'payload' => $payload,
            'sent_at' => now(),
        ]);

        // L'identifiant sert de clé d'affichage côté app : une même
        // notification ne peut pas apparaître deux fois.
        $this->sendFcmPush($user, $type, $title, $body, $payload + ['notification_id' => $notification->id]);

        return $notification;
    }

    /**
     * Send an FCM push notification to the user's device using Firebase
     * Cloud Messaging HTTP v1 API (via Service Account JSON key) or the
     * legacy API (via server key).
     */
    private function sendFcmPush(
        User   $user,
        string $type,
        string $title,
        string $body,
        array  $data = [],
    ): void {
        $fcmToken = $user->fcm_token;

        if (empty($fcmToken)) {
            return;
        }

        // Flatten data for FCM (all values must be strings)
        $fcmData = [
            'type'  => $type,
            'title' => $title,
            'body'  => $body,
        ];
        foreach ($data as $key => $value) {
            if (is_string($value) || is_numeric($value)) {
                $fcmData[$key] = (string) $value;
            }
        }

        // 1. Tenter la NOUVELLE VERSION : FCM HTTP v1 via le compte de service JSON
        $keyPath = storage_path('app/secrets/firebase-adminsdk.json');
        if (is_file($keyPath)) {
            try {
                $serviceAccount = json_decode(file_get_contents($keyPath), true);
                if (! empty($serviceAccount['project_id']) && ! empty($serviceAccount['private_key'])) {
                    $this->sendFcmHttpV1($serviceAccount, $fcmToken, $title, $body, $fcmData);
                    return;
                }
            } catch (\Throwable $e) {
                Log::warning('[FCM v1] Erreur push HTTP v1', [
                    'user_id' => $user->id,
                    'error'   => $e->getMessage(),
                ]);
            }
        }

        // 2. Repli : ANCIENNE VERSION via la clé serveur FCM_SERVER_KEY
        $serverKey = config('services.fcm.server_key');
        if (empty($serverKey)) {
            Log::debug('[FCM] Ni firebase-adminsdk.json ni FCM_SERVER_KEY configuré, push ignoré.');
            return;
        }

        try {
            $response = Http::withHeaders([
                'Authorization' => 'key=' . $serverKey,
                'Content-Type'  => 'application/json',
            ])->post('https://fcm.googleapis.com/fcm/send', [
                'to' => $fcmToken,
                'notification' => [
                    'title' => $title,
                    'body'  => $body,
                    'sound' => 'default',
                    'click_action' => 'FLUTTER_NOTIFICATION_CLICK',
                ],
                'data' => $fcmData,
                'priority' => 'high',
            ]);

            if ($response->failed()) {
                Log::warning('[FCM Legacy] Push failed', [
                    'user_id' => $user->id,
                    'status'  => $response->status(),
                    'body'    => $response->body(),
                ]);
            }
        } catch (\Throwable $e) {
            Log::warning('[FCM Legacy] Push exception', [
                'user_id' => $user->id,
                'error'   => $e->getMessage(),
            ]);
        }
    }

    /**
     * Envoie la notification via l'API FCM HTTP v1 (nouvelle version officielle de Google).
     */
    private function sendFcmHttpV1(
        array  $serviceAccount,
        string $fcmToken,
        string $title,
        string $body,
        array  $fcmData,
    ): void {
        $accessToken = $this->getGoogleAccessToken($serviceAccount);
        if (! $accessToken) {
            Log::warning('[FCM v1] Impossible d\'obtenir un jeton d\'accès Google OAuth2.');
            return;
        }

        $projectId = $serviceAccount['project_id'];
        $url = "https://fcm.googleapis.com/v1/projects/{$projectId}/messages:send";

        $response = Http::withToken($accessToken)->post($url, [
            'message' => [
                'token' => $fcmToken,
                'notification' => [
                    'title' => $title,
                    'body'  => $body,
                ],
                'data' => $fcmData,
                // No channel_id: each app (passenger / driver) declares its
                // own default channel in its manifest, and Android uses it.
                'android' => [
                    'priority' => 'HIGH',
                    'notification' => array_filter([
                        'sound' => 'default',
                        // Même tag = Android remplace au lieu d'empiler.
                        'tag' => $fcmData['notification_id'] ?? null,
                    ]),
                ],
            ],
        ]);

        if ($response->failed()) {
            Log::warning('[FCM v1] Push failed', [
                'status' => $response->status(),
                'body'   => $response->body(),
            ]);
        }
    }

    /**
     * Obtient un jeton d'accès OAuth2 Bearer via la clé privée du compte de service.
     */
    private function getGoogleAccessToken(array $serviceAccount): ?string
    {
        $cacheKey = 'gcp_fcm_access_token_' . md5($serviceAccount['client_email']);
        $cached = cache($cacheKey);
        if ($cached) {
            return $cached;
        }

        $now = time();
        $header = ['alg' => 'RS256', 'typ' => 'JWT'];
        $claims = [
            'iss'   => $serviceAccount['client_email'],
            'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
            'aud'   => 'https://oauth2.googleapis.com/token',
            'exp'   => $now + 3600,
            'iat'   => $now,
        ];

        $base64Header = $this->base64UrlEncode(json_encode($header));
        $base64Claims = $this->base64UrlEncode(json_encode($claims));
        $toSign = $base64Header . '.' . $base64Claims;

        $privateKey = openssl_pkey_get_private($serviceAccount['private_key']);
        if (! $privateKey) {
            return null;
        }

        $signature = '';
        if (! openssl_sign($toSign, $signature, $privateKey, OPENSSL_ALGO_SHA256)) {
            return null;
        }

        $jwt = $toSign . '.' . $this->base64UrlEncode($signature);

        $response = Http::asForm()->post('https://oauth2.googleapis.com/token', [
            'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion'  => $jwt,
        ]);

        if ($response->successful()) {
            $token = $response->json('access_token');
            // Mettre en cache pour 50 minutes (le token expire dans 60 min)
            cache([$cacheKey => $token], now()->addMinutes(50));
            return $token;
        }

        return null;
    }

    private function base64UrlEncode(string $data): string
    {
        return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
    }
}
