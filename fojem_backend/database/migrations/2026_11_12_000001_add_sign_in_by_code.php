<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Connexion par code (WhatsApp ou SMS) : un client s'inscrit avec son seul
 * numéro et son nom. L'e-mail, le mot de passe et le sexe deviennent donc
 * facultatifs ; l'inscription classique (FOJËM Pro) continue de les remplir.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::statement('ALTER TABLE users ALTER COLUMN email DROP NOT NULL');
        DB::statement('ALTER TABLE users ALTER COLUMN password_hash DROP NOT NULL');
        DB::statement('ALTER TABLE users ALTER COLUMN gender DROP NOT NULL');

        Schema::table('users', function (Blueprint $table) {
            $table->timestamp('phone_verified_at')->nullable();
        });

        Schema::create('otp_codes', function (Blueprint $table) {
            $table->id();
            $table->string('phone_number', 20)->index();
            // HMAC du code avec la clé de l'appli : jamais le code en clair.
            $table->string('code_hash', 64);
            $table->string('channel', 16);
            $table->unsignedTinyInteger('attempts')->default(0);
            $table->timestamp('expires_at');
            $table->timestamp('verified_at')->nullable();
            // Nouveau client : jeton qui lui permet de créer son compte une fois son nom donné.
            $table->string('signup_token_hash', 64)->nullable()->unique();
            // Code fermé : connexion faite, compte créé, ou remplacé par un code plus récent.
            $table->timestamp('used_at')->nullable();
            $table->string('ip_address', 45)->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('otp_codes');

        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('phone_verified_at');
        });
        // Les colonnes rendues facultatives le restent : des comptes créés
        // par code n'ont ni e-mail ni mot de passe.
    }
};
