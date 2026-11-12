<?php

namespace App\Providers;

use App\Services\Otp\LogOtpSender;
use App\Services\Otp\OtpSender;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        // Envoi des codes de connexion : seul l'envoi factice existe pour
        // l'instant ; WhatsApp et SMS s'ajouteront ici selon OTP_DRIVER.
        $this->app->bind(OtpSender::class, fn () => match (config('services.otp.driver')) {
            default => new LogOtpSender,
        });
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        //
    }
}
