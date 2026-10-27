<?php

namespace Database\Seeders;

use App\Models\AdminPermission;
use App\Models\AdminRole;
use App\Models\AdminUser;
use App\Models\Driver;
use App\Models\Trip;
use App\Models\User;
use App\Models\Vehicle;
use App\Models\Wallet;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class DatabaseSeeder extends Seeder
{
    /**
     * Seed the application's database with:
     *  - the three baseline admin roles (super_admin/support/finance) and
     *    a starter permission set for each, plus one admin_users account
     *    per role (all password "password") for manually testing the
     *    RBAC middleware;
     *  - a handful of passenger/driver demo accounts (also "password")
     *    with vehicles and open trips, so the two Flutter apps (and
     *    manual API testing) have something real to search/book against.
     */
    public function run(): void
    {
        $this->seedAdminRolesAndPermissions();
        $this->seedDemoRideData();
    }

    private function seedAdminRolesAndPermissions(): void
    {
        $roles = [
            AdminRole::SUPER_ADMIN => [
                ['resource' => '*', 'action' => 'view'],
                ['resource' => '*', 'action' => 'edit'],
                ['resource' => '*', 'action' => 'delete'],
            ],
            AdminRole::SUPPORT => [
                ['resource' => 'users', 'action' => 'view'],
                ['resource' => 'users', 'action' => 'edit'],
                ['resource' => 'driver_documents', 'action' => 'view'],
                ['resource' => 'driver_documents', 'action' => 'edit'],
                ['resource' => 'disputes', 'action' => 'view'],
                ['resource' => 'disputes', 'action' => 'edit'],
                ['resource' => 'sos_alerts', 'action' => 'view'],
                ['resource' => 'sos_alerts', 'action' => 'edit'],
                ['resource' => 'trips', 'action' => 'view'],
                ['resource' => 'trips', 'action' => 'edit'],
            ],
            AdminRole::FINANCE => [
                ['resource' => 'payout_requests', 'action' => 'view'],
                ['resource' => 'payout_requests', 'action' => 'edit'],
                ['resource' => 'transactions', 'action' => 'view'],
                ['resource' => 'platform_settings', 'action' => 'view'],
                ['resource' => 'platform_settings', 'action' => 'edit'],
            ],
        ];

        foreach ($roles as $roleName => $permissions) {
            $role = AdminRole::firstOrCreate(['name' => $roleName]);

            foreach ($permissions as $permission) {
                AdminPermission::firstOrCreate([
                    'role_id' => $role->id,
                    'resource' => $permission['resource'],
                    'action' => $permission['action'],
                ]);
            }

            AdminUser::firstOrCreate(
                ['email' => "{$roleName}@fojem.sn"],
                [
                    'full_name' => ucfirst(str_replace('_', ' ', $roleName)),
                    'password_hash' => Hash::make('password'),
                    'role_id' => $role->id,
                    'is_active' => true,
                ]
            );
        }
    }

    private function seedDemoRideData(): void
    {
        // Dakar-area demo points (Plateau -> Ouakam) so geo search/matching
        // has something plausible to find.
        $driverUser = User::firstOrCreate(
            ['email' => 'demo.driver@fojem.sn'],
            [
                'full_name' => 'Ibrahima Ndiaye',
                'password_hash' => Hash::make('password'),
                'phone_number' => '+221770000001',
                'gender' => 'male',
                'account_status' => 'active',
                'is_driver' => true,
                'language' => 'fr',
            ]
        );
        Wallet::firstOrCreate(['user_id' => $driverUser->id], ['balance' => 0, 'held_balance' => 0]);

        $driver = Driver::firstOrCreate(
            ['user_id' => $driverUser->id],
            ['verification_status' => Driver::STATUS_APPROVED, 'verified_at' => now(), 'average_rating' => 4.8, 'total_trips_completed' => 12]
        );

        $vehicle = Vehicle::firstOrCreate(
            ['plate_number' => 'DK-2024-AB'],
            [
                'driver_id' => $driver->id,
                'brand' => 'Renault',
                'model' => 'Logan',
                'color' => 'Gris',
                'seat_count' => 4,
                'is_active' => true,
            ]
        );

        if (! Trip::where('driver_id', $driver->id)->where('status', Trip::STATUS_OPEN)->exists()) {
            $trip = new Trip([
                'driver_id' => $driver->id,
                'vehicle_id' => $vehicle->id,
                'departure_type' => 'scheduled',
                'scheduled_at' => now()->addHours(2),
                'price_per_seat' => 2500,
                'toll_fees' => 500,
                'seats_available' => 3,
                'status' => Trip::STATUS_OPEN,
                'women_only' => false,
            ]);
            $trip->setOriginPoint(14.6937, -17.4441); // Plateau, Dakar
            $trip->setDestinationPoint(14.7358, -17.4900); // Ouakam, Dakar
            $trip->save();
            $trip->ensureStops();
        }

        $passengerUser = User::firstOrCreate(
            ['email' => 'demo.passenger@fojem.sn'],
            [
                'full_name' => 'Fatou Sow',
                'password_hash' => Hash::make('password'),
                'phone_number' => '+221770000002',
                'gender' => 'female',
                'account_status' => 'active',
                'is_driver' => false,
                'language' => 'fr',
            ]
        );
        Wallet::firstOrCreate(['user_id' => $passengerUser->id], ['balance' => 5000, 'held_balance' => 0]);
    }
}
