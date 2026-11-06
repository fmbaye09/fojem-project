<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Le simulateur n'existe qu'en local : ailleurs, ses routes répondent 404
 * comme si elles n'existaient pas, même avec SIMULATOR_ENABLED=true.
 */
class EnsureSimulatorEnabled
{
    public function handle(Request $request, Closure $next): Response
    {
        if (! config('simulator.enabled') || ! app()->environment(['local', 'testing'])) {
            abort(404);
        }

        return $next($request);
    }
}
