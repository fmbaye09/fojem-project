<?php

namespace App\Services;

use Kreait\Firebase\Factory;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * Mints Firebase custom tokens so the Flutter apps can sign in to Firebase
 * Auth with the SAME identifier as their Laravel account (users.id, a
 * UUID). The apps' Firestore security rules are written against
 * request.auth.uid, and chat stays on Firestore (product decision) - this
 * is what lets the two auth systems stay in sync without duplicating a
 * full auth stack.
 *
 * This service is explicitly best-effort: Firebase is never a hard
 * dependency of Sanctum-based auth. Any failure (missing service account
 * key, network error, malformed key...) is logged and swallowed here,
 * never thrown up into AuthController - callers get null back and put
 * `firebase_custom_token: null` in the response instead of failing login.
 */
class FirebaseTokenService
{
    /**
     * Path to the Firebase service account key. This file is a secret and
     * is never committed - see storage/app/secrets/ in .gitignore. It may
     * legitimately not exist yet (e.g. fresh checkout, CI, local dev
     * before the key was copied in), which is not an error condition for
     * the rest of the app.
     */
    private const SERVICE_ACCOUNT_PATH = 'app/secrets/firebase-adminsdk.json';

    /**
     * Mint a Firebase custom token for the given user, with uid = $userId
     * (same value as users.id in Postgres). Returns null - never throws -
     * if the service account key is missing or token generation fails for
     * any other reason, so this can always be called from a hot auth path
     * without risking the rest of the response.
     */
    public function mintCustomToken(string $userId): ?string
    {
        $keyPath = storage_path(self::SERVICE_ACCOUNT_PATH);

        if (! is_file($keyPath)) {
            Log::warning(
                'Clé de service Firebase absente à storage/app/secrets/firebase-adminsdk.json. '.
                'Impossible de générer un firebase_custom_token - voir README '.
                '(section Firebase) pour savoir où placer ce fichier.'
            );

            return null;
        }

        try {
            $auth = (new Factory())
                ->withServiceAccount($keyPath)
                ->createAuth();

            return $auth->createCustomToken($userId)->toString();
        } catch (Throwable $e) {
            Log::warning('Echec de generation du firebase_custom_token: '.$e->getMessage(), [
                'user_id' => $userId,
                'exception' => $e::class,
            ]);

            return null;
        }
    }
}
