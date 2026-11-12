<?php

namespace App\Support;

/**
 * Numéros de mobile sénégalais : 9 chiffres commençant par 7, stockés au
 * format +221XXXXXXXXX. Les codes de connexion ne partent que vers ces
 * numéros, ce qui écarte aussi l'envoi de SMS surtaxés vers l'étranger.
 */
final class SenegalPhone
{
    /** « 77 123 45 67 », « +221771234567 » ou « 00221 77… » → « +221771234567 » ; null si invalide. */
    public static function normalize(?string $input): ?string
    {
        $digits = preg_replace('/\D/', '', (string) $input);

        if (str_starts_with($digits, '00221')) {
            $digits = substr($digits, 5);
        } elseif (strlen($digits) === 12 && str_starts_with($digits, '221')) {
            $digits = substr($digits, 3);
        }

        return preg_match('/^7\d{8}$/', $digits) ? '+221'.$digits : null;
    }

    /**
     * Écritures possibles d'un même numéro en base : les comptes anciens ne
     * sont pas tous enregistrés au format +221.
     *
     * @return list<string>
     */
    public static function variants(string $normalized): array
    {
        $national = substr($normalized, 4);

        return [$normalized, '221'.$national, $national];
    }
}
