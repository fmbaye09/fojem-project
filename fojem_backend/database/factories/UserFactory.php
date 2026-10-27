<?php

namespace Database\Factories;

use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

/**
 * @extends Factory<User>
 */
class UserFactory extends Factory
{
    /**
     * The current password being used by the factory.
     */
    protected static ?string $password;

    /**
     * Define the model's default state.
     *
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'full_name' => fake()->name(),
            'email' => fake()->unique()->safeEmail(),
            'password_hash' => static::$password ??= Hash::make('password'),
            'phone_number' => '+221' . fake()->unique()->numerify('7#######'),
            'gender' => fake()->randomElement(['male', 'female', 'other']),
            'account_status' => 'active',
            'is_driver' => false,
            'language' => 'fr',
            'remember_token' => Str::random(10),
        ];
    }
}
