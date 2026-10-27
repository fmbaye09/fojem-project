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
        $user = DB::transaction(function () use ($request) {
            $isDriver = $request->boolean('is_driver') || $request->input('client_type') === 'driver';
            $user = User::create([
                'full_name' => $request->string('full_name'),
                'email' => strtolower($request->string('email')),
                'password_hash' => Hash::make($request->string('password')),
                'phone_number' => $request->string('phone_number'),
                'gender' => $request->string('gender'),
                'language' => $request->input('language', 'fr'),
                'is_driver' => $isDriver,
            ]);

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

        return $this->issueTokenResponse($user, $request, 201);
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
