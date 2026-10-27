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
            'departure_type' => ['required', 'in:now,scheduled'],
            'scheduled_at' => ['required_if:departure_type,scheduled', 'nullable', 'date', 'after:now'],
            // Full-route price per seat; intermediate segments are priced
            // through each stop's price_from_origin.
            'price_per_seat' => ['required', 'numeric', 'min:0'],
            'toll_fees' => ['sometimes', 'numeric', 'min:0'],
            'seats_available' => ['required', 'integer', 'min:1', 'max:25'],
            'is_recurring' => ['sometimes', 'boolean'],
            'women_only' => ['sometimes', 'boolean'],

            // Meeting points, departure first and arrival last.
            'stops' => ['required_without:origin_lat', 'array', 'min:2', 'max:12'],
            'stops.*.name' => ['required_with:stops', 'string', 'max:120'],
            'stops.*.address' => ['sometimes', 'nullable', 'string', 'max:255'],
            'stops.*.lat' => ['required_with:stops', 'numeric', 'between:-90,90'],
            'stops.*.lng' => ['required_with:stops', 'numeric', 'between:-180,180'],
            'stops.*.scheduled_at' => ['sometimes', 'nullable', 'date'],
            'stops.*.price_from_origin' => ['sometimes', 'nullable', 'numeric', 'min:0'],

            // Legacy shape (older app versions): origin / waypoints / destination.
            'origin_lat' => ['required_without:stops', 'numeric', 'between:-90,90'],
            'origin_lng' => ['required_without:stops', 'numeric', 'between:-180,180'],
            'destination_lat' => ['required_without:stops', 'numeric', 'between:-90,90'],
            'destination_lng' => ['required_without:stops', 'numeric', 'between:-180,180'],
            'origin_name' => ['sometimes', 'nullable', 'string', 'max:120'],
            'destination_name' => ['sometimes', 'nullable', 'string', 'max:120'],
            'waypoints' => ['sometimes', 'nullable', 'array'],
            'waypoints.*.name' => ['sometimes', 'nullable', 'string', 'max:120'],
            'waypoints.*.lat' => ['required_with:waypoints', 'numeric', 'between:-90,90'],
            'waypoints.*.lng' => ['required_with:waypoints', 'numeric', 'between:-180,180'],
        ];
    }
}
