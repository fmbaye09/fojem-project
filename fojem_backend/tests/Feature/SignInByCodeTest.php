<?php

namespace Tests\Feature;

use App\Models\User;
use App\Services\Otp\OtpSender;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** Connexion et inscription des clients par numéro + code (WhatsApp ou SMS). */
class SignInByCodeTest extends TestCase
{
    use RefreshDatabase;

    /** Messages « envoyés » pendant le test. */
    private object $sender;

    protected function setUp(): void
    {
        parent::setUp();

        $this->sender = new class implements OtpSender
        {
            /** @var list<array{phone: string, code: string, channel: string}> */
            public array $sent = [];

            public function send(string $phoneNumber, string $code, string $channel): void
            {
                $this->sent[] = ['phone' => $phoneNumber, 'code' => $code, 'channel' => $channel];
            }
        };
        $this->app->instance(OtpSender::class, $this->sender);
    }

    private function lastCode(): string
    {
        return end($this->sender->sent)['code'];
    }

    private function sendCode(string $phone, array $extra = [])
    {
        return $this->postJson('/api/auth/code/send', ['phone_number' => $phone, ...$extra]);
    }

    private function verify(string $phone, string $code)
    {
        return $this->postJson('/api/auth/code/verify', ['phone_number' => $phone, 'code' => $code]);
    }

    public function test_a_new_customer_signs_up_with_a_phone_number_a_code_and_a_name(): void
    {
        $this->sendCode('77 123 45 67')
            ->assertOk()
            ->assertJson(['phone_number' => '+221771234567', 'channel' => 'whatsapp', 'resend_in' => 60])
            ->assertJsonMissingPath('dev_code');

        $this->assertCount(1, $this->sender->sent);
        $this->assertSame('+221771234567', $this->sender->sent[0]['phone']);
        $this->assertSame('whatsapp', $this->sender->sent[0]['channel']);
        $this->assertMatchesRegularExpression('/^\d{6}$/', $this->lastCode());

        $token = $this->verify('+221771234567', $this->lastCode())
            ->assertOk()
            ->assertJson(['new_user' => true])
            ->json('signup_token');
        $this->assertNotEmpty($token);
        $this->assertDatabaseMissing('users', ['phone_number' => '+221771234567']);

        $this->postJson('/api/auth/code/register', [
            'signup_token' => $token,
            'first_name' => '  Awa ',
            'last_name' => 'Ndiaye',
        ])->assertCreated()->assertJsonStructure(['user', 'token', 'firebase_custom_token']);

        $user = User::where('phone_number', '+221771234567')->firstOrFail();
        $this->assertSame('Awa Ndiaye', $user->full_name);
        $this->assertNull($user->email);
        $this->assertNull($user->password_hash);
        $this->assertNull($user->gender);
        $this->assertNotNull($user->phone_verified_at);
        $this->assertFalse($user->is_driver);
        $this->assertNotNull($user->wallet);

        // Le jeton d'inscription ne sert qu'une fois.
        $this->postJson('/api/auth/code/register', [
            'signup_token' => $token,
            'first_name' => 'Awa',
            'last_name' => 'Ndiaye',
        ])->assertStatus(422)->assertJsonValidationErrors('signup_token');
    }

    public function test_an_existing_customer_is_signed_in_by_the_code_alone(): void
    {
        $user = User::factory()->create(['phone_number' => '+221781112233']);

        $this->sendCode('781112233', ['channel' => 'sms'])->assertOk()->assertJson(['channel' => 'sms']);
        $this->assertSame('sms', $this->sender->sent[0]['channel']);
        $code = $this->lastCode();

        $this->verify('78 111 22 33', $code)
            ->assertOk()
            ->assertJsonStructure(['user', 'token', 'firebase_custom_token'])
            ->assertJsonPath('user.id', $user->id);
        $this->assertNotNull($user->fresh()->phone_verified_at);

        // Un code ne sert qu'une fois.
        $this->verify('781112233', $code)->assertStatus(422)->assertJsonValidationErrors('code');
    }

    public function test_older_accounts_saved_without_the_country_code_are_found(): void
    {
        $user = User::factory()->create(['phone_number' => '781112233']);

        $this->sendCode('+221781112233')->assertOk();

        $this->verify('+221781112233', $this->lastCode())->assertOk()->assertJsonPath('user.id', $user->id);
    }

    public function test_a_customer_without_a_password_is_refused_politely_by_the_password_login(): void
    {
        User::factory()->create(['phone_number' => '+221781112233', 'password_hash' => null, 'email' => null]);

        $this->postJson('/api/auth/login', ['phone_number' => '+221781112233', 'password' => 'password'])
            ->assertStatus(422);
    }

    public function test_a_wrong_code_counts_down_the_attempts_then_needs_a_new_code(): void
    {
        $this->sendCode('771234567')->assertOk();
        $good = $this->lastCode();
        $wrong = $good === '000000' ? '111111' : '000000';

        $this->verify('771234567', $wrong)
            ->assertStatus(422)
            ->assertJsonPath('errors.code.0', 'Code incorrect. Il vous reste 4 essais.');
        foreach (range(1, 3) as $_) {
            $this->verify('771234567', $wrong)->assertStatus(422);
        }
        $this->verify('771234567', $wrong)
            ->assertJsonPath('errors.code.0', 'Trop d’essais avec ce code. Demandez-en un nouveau.');

        // Même le bon code ne passe plus : il faut en demander un autre.
        $this->verify('771234567', $good)->assertStatus(422)->assertJsonValidationErrors('code');
    }

    public function test_only_senegalese_mobile_numbers_receive_a_code(): void
    {
        foreach (['33 821 00 00', '+33612345678', '7712', 'abc'] as $number) {
            $this->sendCode($number)->assertStatus(422)->assertJsonValidationErrors('phone_number');
        }

        $this->assertSame([], $this->sender->sent);
    }

    public function test_a_new_code_waits_a_minute_and_replaces_the_previous_one(): void
    {
        $this->sendCode('771234567')->assertOk();
        $first = $this->lastCode();

        $this->sendCode('771234567')
            ->assertStatus(422)
            ->assertJsonValidationErrors('phone_number');
        $this->assertCount(1, $this->sender->sent);

        $this->travel(61)->seconds();
        $this->sendCode('771234567', ['channel' => 'sms'])->assertOk();
        $second = $this->lastCode();

        if ($first !== $second) {
            $this->verify('771234567', $first)->assertStatus(422);
        }
        $this->verify('771234567', $second)->assertOk()->assertJson(['new_user' => true]);
    }

    public function test_codes_per_number_are_capped_each_hour(): void
    {
        foreach (range(1, 5) as $_) {
            $this->sendCode('771234567')->assertOk();
            $this->travel(61)->seconds();
        }

        $this->sendCode('771234567')
            ->assertStatus(422)
            ->assertJsonPath('errors.phone_number.0', 'Trop de codes demandés pour ce numéro. Réessayez dans une heure.');

        $this->travel(1)->hours();
        $this->sendCode('771234567')->assertOk();
    }

    public function test_a_code_expires_after_ten_minutes(): void
    {
        $this->sendCode('771234567')->assertOk();

        $this->travel(11)->minutes();

        $this->verify('771234567', $this->lastCode())
            ->assertStatus(422)
            ->assertJsonPath('errors.code.0', 'Ce code a expiré. Demandez-en un nouveau.');
    }

    public function test_the_name_must_be_given_within_half_an_hour(): void
    {
        $this->sendCode('771234567')->assertOk();
        $token = $this->verify('771234567', $this->lastCode())->json('signup_token');

        $this->travel(31)->minutes();

        $this->postJson('/api/auth/code/register', [
            'signup_token' => $token,
            'first_name' => 'Awa',
            'last_name' => 'Ndiaye',
        ])->assertStatus(422)->assertJsonValidationErrors('signup_token');
        $this->assertDatabaseMissing('users', ['phone_number' => '+221771234567']);
    }

    public function test_test_numbers_get_a_fixed_code_and_no_message(): void
    {
        config(['services.otp.test_numbers' => '+221700000902:123456, 700000903:654321']);

        $this->sendCode('70 000 09 02')->assertOk();
        $this->sendCode('700000903')->assertOk();

        $this->assertSame([], $this->sender->sent);
        $this->verify('700000902', '123456')->assertOk()->assertJson(['new_user' => true]);
        $this->verify('700000903', '654321')->assertOk()->assertJson(['new_user' => true]);
    }

    public function test_the_code_is_returned_to_the_app_only_in_local_development(): void
    {
        $this->sendCode('771234567')->assertOk()->assertJsonMissingPath('dev_code');

        $this->app['env'] = 'local';
        config(['services.otp.driver' => 'log']);
        $this->sendCode('781112233')->assertOk()->assertJsonPath('dev_code', $this->lastCode());

        config(['services.otp.driver' => 'whatsapp']);
        $this->sendCode('761112233')->assertOk()->assertJsonMissingPath('dev_code');
    }

    public function test_a_disabled_account_cannot_sign_in_by_code(): void
    {
        User::factory()->create(['phone_number' => '+221781112233', 'account_status' => 'disabled']);

        $this->sendCode('781112233')->assertOk();

        $this->verify('781112233', $this->lastCode())
            ->assertStatus(422)
            ->assertJsonPath('errors.code.0', 'Ce compte est désactivé. Contactez le support FOJËM.');
    }

    public function test_the_number_of_a_deleted_account_cannot_open_a_new_one(): void
    {
        User::factory()->create(['phone_number' => '+221781112233'])->delete();

        $this->sendCode('781112233')->assertOk();

        $this->verify('781112233', $this->lastCode())
            ->assertStatus(422)
            ->assertJsonPath('errors.code.0', 'Ce numéro est lié à un compte supprimé. Contactez le support FOJËM.');
    }
}
