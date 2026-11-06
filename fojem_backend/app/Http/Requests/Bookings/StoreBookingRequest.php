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
            // Or a new point the passenger proposes instead of one of them;
            // the driver accepts it, with its detour, or not.
            'proposed_stop' => ['sometimes', 'nullable', 'array'],
            'proposed_stop.role' => ['required_with:proposed_stop', 'in:boarding,alighting'],
            'proposed_stop.lat' => ['required_with:proposed_stop', 'numeric', 'between:-90,90'],
            'proposed_stop.lng' => ['required_with:proposed_stop', 'numeric', 'between:-180,180'],
            'proposed_stop.name' => ['sometimes', 'nullable', 'string', 'max:120'],
            'proposed_stop.address' => ['sometimes', 'nullable', 'string', 'max:255'],
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
