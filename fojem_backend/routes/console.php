<?php

use App\Services\TripLifecycleService;
use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

Artisan::command('fojem:sync-lifecycle', function () {
    $this->info('Synchronisation automatique du cycle de vie FOJEM en cours...');
    $result = TripLifecycleService::sync();
    $this->info("Terminé : {$result['expired_bookings']} réservations expirées, {$result['cancelled_stale_trips']} trajets obsolètes annulés, {$result['expired_ride_requests']} demandes expirées.");
})->purpose('Synchronise automatiquement les statuts de trajets, réservations et demandes');

Schedule::command('fojem:sync-lifecycle')->everyMinute();
