<?php

namespace App\Services;

use App\Models\Booking;
use App\Models\Driver;
use App\Models\Trip;
use App\Models\User;
use App\Models\Vehicle;
use App\Models\Wallet;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

/**
 * Comptes et données du simulateur du dashboard (local uniquement). Les
 * acteurs simulés passent ensuite par l'API publique, comme les applis : le
 * simulateur ne contourne aucune règle, il ne fait que créer des comptes,
 * vieillir un scénario et tout nettoyer à la fin.
 */
class SimulatorService
{
    public const ROLE_DRIVER = 'driver';
    public const ROLE_PASSENGER = 'passenger';

    private const FIRST_NAMES = [
        'male' => ['Moussa', 'Ibrahima', 'Cheikh', 'Ousmane', 'Mamadou', 'Abdoulaye', 'Modou', 'Pape', 'Serigne', 'Babacar'],
        'female' => ['Awa', 'Fatou', 'Aminata', 'Mariama', 'Khady', 'Ndeye', 'Coumba', 'Astou', 'Bineta', 'Seynabou'],
    ];
    private const LAST_NAMES = ['Ndiaye', 'Diop', 'Sow', 'Fall', 'Ba', 'Mbaye', 'Diallo', 'Sy', 'Gueye', 'Sarr', 'Faye', 'Cissé', 'Seck', 'Thiam'];

    /**
     * Un compte simulé prêt à l'emploi et son jeton d'API. Un chauffeur est
     * déjà validé, avec un véhicule et un portefeuille.
     *
     * @return array{user: User, token: string, vehicle_id: ?string}
     */
    public function createActor(string $role, ?string $name = null, int $seats = 7): array
    {
        return DB::transaction(function () use ($role, $name, $seats) {
            $gender = random_int(0, 1) === 1 ? 'female' : 'male';
            $user = User::create([
                'full_name' => trim((string) $name) !== '' ? trim((string) $name) : $this->randomName($gender),
                'email' => 'sim-'.Str::lower(Str::random(12)).'@simulateur.fojem.test',
                'password_hash' => Hash::make(Str::random(32)),
                'phone_number' => $this->uniquePhone(),
                'gender' => $gender,
                'account_status' => 'active',
                'is_driver' => $role === self::ROLE_DRIVER,
                'language' => 'fr',
            ]);
            $user->forceFill(['is_simulated' => true])->save();

            $vehicleId = null;
            if ($role === self::ROLE_DRIVER) {
                Wallet::create(['user_id' => $user->id]);
                $driver = Driver::create([
                    'user_id' => $user->id,
                    'verification_status' => Driver::STATUS_APPROVED,
                    'verified_at' => now(),
                ]);
                $vehicleId = Vehicle::create([
                    'driver_id' => $driver->id,
                    'plate_number' => 'SIM-'.random_int(1000, 9999).'-'.Str::upper(Str::random(2)),
                    'brand' => 'Toyota',
                    'model' => 'Hiace',
                    'color' => 'Blanc',
                    'seat_count' => max(1, min($seats, 15)),
                    'is_active' => true,
                ])->id;
            }

            return [
                'user' => $user,
                'token' => $user->createToken('simulateur')->plainTextToken,
                'vehicle_id' => $vehicleId,
            ];
        });
    }

    /**
     * Fait comme si le trajet et ces réservations dataient de $minutes : les
     * rappels « 30 min avant » ne partent que pour un trajet publié (et une
     * place confirmée) au moins 30 min avant. Seulement sur des données du
     * simulateur.
     *
     * @param  list<string>  $bookingIds
     * @return array{trips: int, bookings: int}
     */
    public function backdate(?Trip $trip, array $bookingIds, int $minutes): array
    {
        $at = now()->subMinutes($minutes);
        $trips = 0;
        $bookings = 0;

        if ($trip !== null && $this->isSimulatedTrip($trip)) {
            $trips = DB::table('trips')->where('id', $trip->id)->update(['created_at' => $at]);
            $bookings += $this->backdateBookings(Booking::where('trip_id', $trip->id)->pluck('id'), $at);
        }
        if ($bookingIds !== []) {
            $simulated = Booking::whereIn('id', $bookingIds)
                ->whereHas('passenger', fn ($q) => $q->where('is_simulated', true))
                ->pluck('id');
            $bookings += $this->backdateBookings($simulated, $at);
        }

        return ['trips' => $trips, 'bookings' => $bookings];
    }

    public function isSimulatedTrip(Trip $trip): bool
    {
        return User::whereKey($trip->driverProfile?->user_id)->where('is_simulated', true)->exists();
    }

    /**
     * Supprime tous les comptes simulés et ce qui en dépend : leurs trajets
     * (avec arrêts et réservations, même celles d'un vrai téléphone), leurs
     * réservations sur de vrais trajets (dont les places sont rendues) et
     * leurs notifications.
     *
     * @return array{users: int, trips: int}
     */
    public function reset(): array
    {
        $userIds = DB::table('users')->where('is_simulated', true)->pluck('id');
        if ($userIds->isEmpty()) {
            return ['users' => 0, 'trips' => 0];
        }
        $driverIds = DB::table('drivers')->whereIn('user_id', $userIds)->pluck('id');
        $tripIds = DB::table('trips')->whereIn('driver_id', $driverIds)->pluck('id');

        DB::transaction(function () use ($userIds, $tripIds) {
            $this->releaseSeatsOnRealTrips($userIds, $tripIds);

            if ($tripIds->isNotEmpty()) {
                // Ce que de vrais comptes ont reçu à propos de ces trajets.
                DB::table('notifications')->whereIn(DB::raw("payload->>'trip_id'"), $tripIds->all())->delete();
                // Arrêts et réservations suivent (clés étrangères en cascade).
                DB::table('trips')->whereIn('id', $tripIds)->delete();
            }
            DB::table('personal_access_tokens')
                ->where('tokenable_type', User::class)
                ->whereIn('tokenable_id', $userIds)
                ->delete();
            // Chauffeur, véhicule, portefeuille, notifications, réservations… en cascade.
            DB::table('users')->whereIn('id', $userIds)->delete();
        });

        return ['users' => $userIds->count(), 'trips' => $tripIds->count()];
    }

    /** Un passager simulé sur un vrai trajet y libère sa place et son éventuel arrêt ajouté. */
    private function releaseSeatsOnRealTrips(Collection $userIds, Collection $simulatedTripIds): void
    {
        $bookings = Booking::whereIn('passenger_id', $userIds)
            ->whereNotIn('trip_id', $simulatedTripIds)
            ->get();
        $planner = app(StopInsertionPlanner::class);

        foreach ($bookings as $booking) {
            $trip = Trip::whereKey($booking->trip_id)->lockForUpdate()->first();
            if ($trip === null) {
                continue;
            }
            if ($booking->status === Booking::STATUS_CONFIRMED
                && in_array($trip->status, [Trip::STATUS_OPEN, Trip::STATUS_FULL, Trip::STATUS_IN_PROGRESS], true)) {
                $trip->increment('seats_available', $booking->seat_count);
                if ($trip->status === Trip::STATUS_FULL) {
                    $trip->update(['status' => Trip::STATUS_OPEN]);
                }
            }
            $insertedStopId = $booking->proposed_stop['inserted_stop_id'] ?? null;
            DB::table('bookings')->where('id', $booking->id)->delete();
            if ($insertedStopId) {
                $planner->removeIfUnused($trip->fresh(), $insertedStopId);
            }
        }
    }

    private function backdateBookings(Collection $ids, \DateTimeInterface $at): int
    {
        if ($ids->isEmpty()) {
            return 0;
        }

        $count = DB::table('bookings')->whereIn('id', $ids)->update(['created_at' => $at]);
        DB::table('bookings')->whereIn('id', $ids)->whereNotNull('confirmed_at')->update(['confirmed_at' => $at]);

        return $count;
    }

    private function randomName(string $gender): string
    {
        $first = self::FIRST_NAMES[$gender][array_rand(self::FIRST_NAMES[$gender])];
        $last = self::LAST_NAMES[array_rand(self::LAST_NAMES)];

        return "{$first} {$last} (sim)";
    }

    private function uniquePhone(): string
    {
        do {
            $phone = '+22170'.str_pad((string) random_int(0, 9_999_999), 7, '0', STR_PAD_LEFT);
        } while (User::withTrashed()->where('phone_number', $phone)->exists());

        return $phone;
    }
}
