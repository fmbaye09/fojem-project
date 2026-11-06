<?php

namespace App\Http\Requests\Trips;

use Illuminate\Foundation\Http\FormRequest;

class SearchTripsRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            // Each point is optional, but its latitude and longitude go together.
            'origin_lat' => ['nullable', 'required_with:origin_lng', 'numeric', 'between:-90,90'],
            'origin_lng' => ['nullable', 'required_with:origin_lat', 'numeric', 'between:-180,180'],
            'destination_lat' => ['nullable', 'required_with:destination_lng', 'numeric', 'between:-90,90'],
            'destination_lng' => ['nullable', 'required_with:destination_lat', 'numeric', 'between:-180,180'],
            // Max distance between the passenger's point and a meeting point.
            'radius_m' => ['sometimes', 'integer', 'min:500', 'max:50000'],
            'women_only' => ['sometimes', 'boolean'],
            // Day of boarding (Y-m-d) and seats needed.
            'date' => ['sometimes', 'nullable', 'date_format:Y-m-d'],
            'seats' => ['sometimes', 'integer', 'min:1', 'max:8'],
        ];
    }
}
