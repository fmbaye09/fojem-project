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
            'seat_numbers' => ['sometimes', 'array', 'min:1', 'max:8'],
            'seat_numbers.*' => ['string', 'max:10', 'distinct'],
            // Meeting points chosen among the trip's stops; default to the
            // whole trip when omitted.
            'boarding_stop_id' => ['sometimes', 'nullable', 'uuid'],
            'alighting_stop_id' => ['sometimes', 'nullable', 'uuid'],
            // Ignored since meeting points replaced free pickup points;
            // still accepted from older app versions.
            'pickup_lat' => ['sometimes', 'nullable', 'numeric', 'between:-90,90'],
            'pickup_lng' => ['sometimes', 'nullable', 'numeric', 'between:-180,180'],
            'has_heavy_luggage' => ['sometimes', 'boolean'],
            'luggage_photos' => ['sometimes', 'array'],
            'luggage_photos.*' => ['file', 'mimes:jpeg,png,jpg,webp', 'max:10240'],
        ];
    }
}
