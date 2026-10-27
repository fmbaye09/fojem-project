<?php

namespace App\Http\Requests\Trips;

use Illuminate\Foundation\Http\FormRequest;

class StoreTripRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'vehicle_id' => ['required', 'uuid', 'exists:vehicles,id'],
            'origin_lat' => ['required', 'numeric', 'between:-90,90'],
            'origin_lng' => ['required', 'numeric', 'between:-180,180'],
            'destination_lat' => ['required', 'numeric', 'between:-90,90'],
            'destination_lng' => ['required', 'numeric', 'between:-180,180'],
            'departure_type' => ['required', 'in:now,scheduled'],
            'scheduled_at' => ['required_if:departure_type,scheduled', 'nullable', 'date', 'after:now'],
            'price_per_seat' => ['required', 'numeric', 'min:0'],
            'toll_fees' => ['sometimes', 'numeric', 'min:0'],
            'seats_available' => ['required', 'integer', 'min:1', 'max:25'],
            'is_recurring' => ['sometimes', 'boolean'],
            'women_only' => ['sometimes', 'boolean'],
            'origin_name' => ['sometimes', 'nullable', 'string', 'max:255'],
            'destination_name' => ['sometimes', 'nullable', 'string', 'max:255'],
            'waypoints' => ['sometimes', 'nullable', 'array'],
            'waypoints.*.name' => ['sometimes', 'nullable', 'string', 'max:255'],
            'waypoints.*.lat' => ['required_with:waypoints', 'numeric', 'between:-90,90'],
            'waypoints.*.lng' => ['required_with:waypoints', 'numeric', 'between:-180,180'],
        ];
    }
}
