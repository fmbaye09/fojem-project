<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Resend, Postmark, AWS, and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    'postmark' => [
        'key' => env('POSTMARK_API_KEY'),
    ],

    'resend' => [
        'key' => env('RESEND_API_KEY'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],

    'fcm' => [
        'server_key' => env('FCM_SERVER_KEY'),
    ],

    // Durées de route pour les heures de passage en direct. Serveur public
    // par défaut ; un OSRM auto-hébergé se branche par OSRM_URL. Vide :
    // désactivé, estimation à vol d'oiseau.
    'osrm' => [
        'url' => env('OSRM_URL', 'https://router.project-osrm.org'),
        'timeout' => (float) env('OSRM_TIMEOUT', 4),
        // Au plus un calcul par trajet et par minute (règles d'usage du serveur public).
        'refresh_seconds' => (int) env('OSRM_REFRESH_SECONDS', 60),
        // Corrige les durées « route dégagée » d'OSRM pour le trafic réel.
        'duration_factor' => (float) env('OSRM_DURATION_FACTOR', 1.0),
    ],

    // Lieux de rendez-vous d'OpenStreetMap (gares routières, stations, péages),
    // importés une fois par mois pour tout le pays (fojem:import-meeting-places).
    'overpass' => [
        'url' => env('OVERPASS_URL', 'https://overpass-api.de/api/interpreter'),
        'timeout' => (float) env('OVERPASS_TIMEOUT', 200),
    ],

];
