<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;

class UserController extends Controller
{
    /**
     * Minimal public profile: no email, phone, account_status or other
     * sensitive field - just what the apps need to display who a
     * passenger/driver on a trip is.
     */
    public function show(User $user)
    {
        return response()->json([
            'user' => [
                'id' => $user->id,
                'full_name' => $user->full_name,
                'profile_photo_url' => $user->profile_photo_url,
                'gender' => $user->gender,
            ],
        ]);
    }
}
