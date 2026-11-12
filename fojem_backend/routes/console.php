<?php

use App\Models\OtpCode;
use App\Services\MeetingPlaceImporter;
use App\Services\TripLifecycleService;
use App\Services\TripReminderService;
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

Artisan::command('fojem:send-reminders', function (TripReminderService $reminders) {
    $sent = $reminders->sendDue();
    $this->info("Rappels envoyés : {$sent['drivers']} chauffeur(s), {$sent['passengers']} passager(s).");
})->purpose('Rappelle le départ 30 min avant au chauffeur et aux passagers');

Schedule::command('fojem:send-reminders')->everyMinute()->withoutOverlapping();

Artisan::command('fojem:import-meeting-places {--attempts=4}', function (MeetingPlaceImporter $importer) {
    $result = $importer->import((int) $this->option('attempts'));
    if ($result === null) {
        $this->error('OpenStreetMap (Overpass) n’a pas répondu : lieux inchangés, réessayez plus tard.');

        return 1;
    }
    $this->info("Lieux de rendez-vous : {$result['imported']} importés, {$result['removed']} retirés.");
})->purpose('Importe les gares routières, stations, péages et ronds-points du Sénégal depuis OpenStreetMap');

Schedule::command('fojem:import-meeting-places')->monthlyOn(1, '03:30')->withoutOverlapping();

// Codes de connexion de plus d'un jour.
Schedule::command('model:prune', ['--model' => [OtpCode::class]])->dailyAt('04:00');
