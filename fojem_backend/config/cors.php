<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Cross-Origin Resource Sharing (CORS) Configuration
    |--------------------------------------------------------------------------
    |
    | Publié depuis le défaut Laravel (auparavant seulement dans vendor/,
    | donc implicitement allowed_origins => ['*']) pour autoriser
    | explicitement l'origine du dashboard admin FOJEM (React/Vite) en
    | développement, plutôt que de laisser un wildcard ouvert sur /api/*.
    | L'auth admin passe par un Bearer token (pas de cookie Sanctum SPA),
    | donc supports_credentials reste false.
    |
    */

    'paths' => ['api/*', 'sanctum/csrf-cookie'],

    'allowed_methods' => ['*'],

    'allowed_origins' => [
        'http://localhost:5173',
        'http://127.0.0.1:5173',
        'http://169.58.156.95:8082',
    ],

    'allowed_origins_patterns' => [],

    'allowed_headers' => ['*'],

    'exposed_headers' => [],

    'max_age' => 0,

    'supports_credentials' => false,

];
