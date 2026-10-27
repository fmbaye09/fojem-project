<?php

namespace App\Http\Requests\Bookings;

use Illuminate\Foundation\Http\FormRequest;

class StoreBookingRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'trip_id' => ['required', 'uuid', 'exists:trips,id'],
            'ride_request_id' => ['sometimes', 'nullable', 'uuid', 'exists:ride_requests,id'],
            'seat_count' => ['sometimes', 'integer', 'min:1', 'max:8'],
            'pickup_lat' => ['required', 'numeric', 'between:-90,90'],
            'pickup_lng' => ['required', 'numeric', 'between:-180,180'],
            'has_heavy_luggage' => ['sometimes', 'boolean'],
            'luggage_photos' => ['sometimes', 'array'],
            'luggage_photos.*' => ['file', 'mimes:jpeg,png,jpg,webp', 'max:10240'],
        ];
    }
}
