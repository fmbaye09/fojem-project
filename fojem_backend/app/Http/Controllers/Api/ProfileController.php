<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\Profile\UpdateProfilePhotoRequest;
use App\Http\Requests\Profile\UpdateProfileRequest;
use Illuminate\Support\Facades\Storage;

class ProfileController extends Controller
{
    public function update(UpdateProfileRequest $request)
    {
        $user = $request->user();
        $fields = [];
        if ($request->filled('full_name')) {
            $fields['full_name'] = $request->string('full_name')->value();
        }
        if ($request->filled('phone_number')) {
            $fields['phone_number'] = $request->string('phone_number')->value();
        }

        if (! empty($fields)) {
            $user->update($fields);
        }

        return response()->json(['user' => $user->fresh()]);
    }

    /** Profile photos are public (shown to other users on trips), unlike driver documents. */
    public function updatePhoto(UpdateProfilePhotoRequest $request)
    {
        $user = $request->user();

        $path = $request->file('photo')->store('profile-photos', 'public');
        $photoUrl = $request->schemeAndHttpHost() . '/storage/' . $path;
        $user->update(['profile_photo_url' => $photoUrl]);

        return response()->json(['user' => $user->fresh()]);
    }
}
