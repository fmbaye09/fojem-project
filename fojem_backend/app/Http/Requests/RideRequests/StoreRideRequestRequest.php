<?php

namespace App\Http\Requests\RideRequests;

use Illuminate\Foundation\Http\FormRequest;

class StoreRideRequestRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'origin_lat' => ['required', 'numeric', 'between:-90,90'],
            'origin_lng' => ['required', 'numeric', 'between:-180,180'],
            'destination_lat' => ['required', 'numeric', 'between:-90,90'],
            'destination_lng' => ['required', 'numeric', 'between:-180,180'],
            'requested_at' => ['sometimes', 'nullable', 'date'],
            'women_only' => ['sometimes', 'boolean'],
            'origin_name' => ['sometimes', 'nullable', 'string', 'max:255'],
            'destination_name' => ['sometimes', 'nullable', 'string', 'max:255'],
        ];
    }
}
