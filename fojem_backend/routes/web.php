<?php

use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});

// Page de suivi d'un trajet partagé par un passager (sans app ni compte).
Route::get('/suivi/{token}', fn (string $token) => view('share', ['token' => $token]))
    ->where('token', '[A-Za-z0-9]{20,64}');
