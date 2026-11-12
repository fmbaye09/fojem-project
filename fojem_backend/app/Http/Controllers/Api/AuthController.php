<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\Auth\LoginRequest;
use App\Http\Requests\Auth\RegisterRequest;
use App\Models\AuthSession;
use App\Models\Driver;
use App\Models\User;
use App\Models\Wallet;
use App\Services\FirebaseTokenService;
use App\Services\Otp\OtpService;
use App\Support\SenegalPhone;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    public function __construct(private readonly FirebaseTokenService $firebaseTokenService)
    {
    }

    /**
     * Register a new account. A user is always created with is_driver=false;
     * see becomeDriver() to add a driver profile on top of the same account.
     * Also provisions the user's wallet (1-1, balance starts at 0).
     */
    public function register(RegisterRequest $request)
    {
        $user = $this->createAccount([
            'full_name' => $request->string('full_name'),
            'email' => strtolower($request->string('email')),
            'password_hash' => Hash::make($request->string('password')),
            'phone_number' => $request->string('phone_number'),
            'gender' => $request->string('gender'),
            'language' => $request->input('language', 'fr'),
        ], $request->boolean('is_driver') || $request->input('client_type') === 'driver');

        return $this->issueTokenResponse($user, $request, 201);
    }

    /**
     * Connexion par code, étape 1 : envoie un code à 6 chiffres au numéro,
     * par WhatsApp (par défaut) ou par SMS. Même parcours pour un client
     * existant et un nouveau : on ne dit pas ici si le numéro a un compte.
     */
    public function sendCode(Request $request, OtpService $otp)
    {
        $data = $request->validate([
            'phone_number' => ['required', 'string', 'max:20'],
            'channel' => ['sometimes', 'in:whatsapp,sms'],
        ]);
        $phone = $this->senegalPhone($data['phone_number']);
        $channel = $data['channel'] ?? 'whatsapp';

        $code = $otp->send($phone, $channel, $request->ip());

        return response()->json([
            'phone_number' => $phone,
            'channel' => $channel,
            'expires_in' => OtpService::TTL_MINUTES * 60,
            'resend_in' => OtpService::RESEND_SECONDS,
            ...($otp->exposesCodes() ? ['dev_code' => $code] : []),
        ]);
    }

    /**
     * Étape 2 : vérifie le code. Un client existant est connecté
     * ({user, token}) ; un nouveau reçoit {new_user, signup_token} et donne
     * son nom à l'étape 3.
     */
    public function verifyCode(Request $request, OtpService $otp)
    {
        $data = $request->validate([
            'phone_number' => ['required', 'string', 'max:20'],
            'code' => ['required', 'string', 'max:12'],
            'device_id' => ['sometimes', 'string', 'max:255'],
        ]);
        $phone = $this->senegalPhone($data['phone_number']);
        $verified = $otp->verify($phone, preg_replace('/\D/', '', $data['code']));

        $user = User::whereIn('phone_number', SenegalPhone::variants($phone))->first();
        if ($user === null) {
            if (User::onlyTrashed()->whereIn('phone_number', SenegalPhone::variants($phone))->exists()) {
                $otp->close($verified);
                throw ValidationException::withMessages([
                    'code' => ['Ce numéro est lié à un compte supprimé. Contactez le support FOJËM.'],
                ]);
            }

            return response()->json(['new_user' => true, 'signup_token' => $otp->startSignup($verified)]);
        }

        $otp->close($verified);

        return $this->signInVerified($user, $request);
    }

    /** Étape 3 (nouveau client) : crée le compte avec le numéro vérifié et le nom. */
    public function registerWithCode(Request $request, OtpService $otp)
    {
        $data = $request->validate([
            'signup_token' => ['required', 'string', 'max:100'],
            'first_name' => ['required', 'string', 'max:60'],
            'last_name' => ['required', 'string', 'max:60'],
            'device_id' => ['sometimes', 'string', 'max:255'],
        ]);
        $verified = $otp->signupFor($data['signup_token']);
        $phone = $verified->phone_number;

        // Compte créé entre-temps avec ce numéro (autre appareil) : le
        // numéro vient d'être prouvé, on connecte plutôt que d'échouer.
        $user = User::whereIn('phone_number', SenegalPhone::variants($phone))->first();
        $created = $user === null;
        $user ??= $this->createAccount([
            'full_name' => Str::squish($data['first_name']).' '.Str::squish($data['last_name']),
            'phone_number' => $phone,
            'language' => 'fr',
        ], false);

        $otp->close($verified);

        return $this->signInVerified($user, $request, $created ? 201 : 200);
    }

    public function login(LoginRequest $request)
    {
        $loginInput = $request->input('phone_number') ?? $request->input('login') ?? $request->input('email');
        $loginInput = trim((string) $loginInput);

        $cleanedPhone = preg_replace('/[^\d+]/', '', $loginInput);

        $user = User::where('email', strtolower($loginInput))
            ->orWhere('phone_number', $loginInput)
            ->when(! empty($cleanedPhone), function ($q) use ($cleanedPhone) {
                $q->orWhere('phone_number', $cleanedPhone)
                  ->orWhere('phone_number', ltrim($cleanedPhone, '+'));
            })
            ->first();

        if (! $user || ! Hash::check($request->string('password'), $user->password_hash)) {
            throw ValidationException::withMessages([
                'email' => ['Identifiants invalides.'],
            ]);
        }

        if ($user->account_status !== 'active') {
            throw ValidationException::withMessages([
                'email' => ['Ce compte est desactive.'],
            ]);
        }

        $clientType = $request->input('client_type');
        if ($clientType === 'driver') {
            if (! $user->is_driver || ! $user->driver) {
                throw ValidationException::withMessages([
                    'email' => ['Aucun compte chauffeur associé à ces identifiants. Veuillez créer un compte chauffeur.'],
                ]);
            }
        }

        return $this->issueTokenResponse($user, $request, 200);
    }

    public function logout(Request $request)
    {
        $token = $request->user()->currentAccessToken();

        AuthSession::where('user_id', $request->user()->id)
            ->where('token_hash', hash('sha256', explode('|', (string) $request->bearerToken())[1] ?? ''))
            ->update(['revoked_at' => now()]);

        $token?->delete();

        // The device no longer belongs to this account: stop its pushes.
        $request->user()->update(['fcm_token' => null]);

        return response()->json(['message' => 'Deconnecte.']);
    }

    public function me(Request $request)
    {
        $user = $request->user();

        return response()->json([
            'user' => $user->load('driver', 'wallet'),
            'firebase_custom_token' => $this->firebaseTokenService->mintCustomToken($user->id),
        ]);
    }

    /**
     * Turns the current account into a driver account: sets is_driver=true
     * and creates the drivers profile row (verification_status=pending).
     * Publishing a trip is blocked elsewhere until an admin approves it.
     */
    public function becomeDriver(Request $request)
    {
        $user = $request->user();

        if ($user->driver()->exists()) {
            return response()->json(['message' => 'Profil chauffeur deja existant.', 'driver' => $user->driver], 200);
        }

        $driver = DB::transaction(function () use ($user) {
            $user->update(['is_driver' => true]);

            return Driver::create([
                'user_id' => $user->id,
                'verification_status' => Driver::STATUS_PENDING,
            ]);
        });

        return response()->json(['message' => 'Profil chauffeur cree, en attente de validation.', 'driver' => $driver], 201);
    }

    /**
     * Crée un compte et son portefeuille (1-1, solde à 0), plus le profil
     * chauffeur en attente de validation si c'en est un.
     */
    private function createAccount(array $attributes, bool $isDriver): User
    {
        return DB::transaction(function () use ($attributes, $isDriver) {
            $user = User::create([...$attributes, 'is_driver' => $isDriver, 'account_status' => 'active']);

            Wallet::create([
                'user_id' => $user->id,
                'balance' => 0,
                'held_balance' => 0,
            ]);

            if ($isDriver) {
                Driver::create([
                    'user_id' => $user->id,
                    'verification_status' => 'pending',
                ]);
            }

            return $user;
        });
    }

    /** Numéro de mobile sénégalais au format +221…, ou erreur de validation. */
    private function senegalPhone(string $input): string
    {
        return SenegalPhone::normalize($input) ?? throw ValidationException::withMessages([
            'phone_number' => ['Entrez un numéro de mobile sénégalais : 9 chiffres, commençant par 7.'],
        ]);
    }

    /** Connecte un compte dont le numéro vient d'être vérifié par code. */
    private function signInVerified(User $user, Request $request, int $status = 200)
    {
        if ($user->account_status !== 'active') {
            throw ValidationException::withMessages([
                'code' => ['Ce compte est désactivé. Contactez le support FOJËM.'],
            ]);
        }

        if ($user->phone_verified_at === null) {
            $user->forceFill(['phone_verified_at' => now()])->save();
        }

        return $this->issueTokenResponse($user, $request, $status);
    }

    private function issueTokenResponse(User $user, Request $request, int $status)
    {
        $deviceId = $request->input('device_id', 'unknown-device');
        $plainToken = $user->createToken($deviceId)->plainTextToken;

        // The bearer token is "{id}|{plain}"; we hash only the plain part so
        // token_hash can be compared against future raw tokens the same way
        // Sanctum itself hashes what it stores.
        $tokenPart = explode('|', $plainToken, 2)[1] ?? $plainToken;

        AuthSession::create([
            'user_id' => $user->id,
            'device_id' => $deviceId,
            'token_hash' => hash('sha256', $tokenPart),
            'ip_address' => $request->ip(),
            'expires_at' => now()->addDays(30),
        ]);

        // Best-effort: this is an additional field for the Flutter apps to
        // sign in to Firebase Auth (chat/Firestore) with the same uid as
        // this Laravel account. It must never block Sanctum auth - see
        // FirebaseTokenService for the fallback-to-null behaviour.
        $firebaseCustomToken = $this->firebaseTokenService->mintCustomToken($user->id);

        return response()->json([
            'user' => $user,
            'token' => $plainToken,
            'firebase_custom_token' => $firebaseCustomToken,
        ], $status);
    }
}
