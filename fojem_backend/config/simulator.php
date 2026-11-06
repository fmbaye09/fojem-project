<?php

return [
    /*
    |--------------------------------------------------------------------------
    | Simulateur du dashboard
    |--------------------------------------------------------------------------
    |
    | Comptes, trajets et positions simulés pour tester l'algorithme sur le
    | backend local, depuis la page « Simulateur » du dashboard. Actif
    | seulement avec SIMULATOR_ENABLED=true ET APP_ENV=local (ou testing) :
    | jamais en production, même si la variable y est posée par erreur
    | (voir EnsureSimulatorEnabled).
    |
    */
    'enabled' => (bool) env('SIMULATOR_ENABLED', false),
];
