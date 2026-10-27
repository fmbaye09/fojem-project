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
            'origin_lat' => ['required', 'numeric', 'between:-90,90'],
            'origin_lng' => ['required', 'numeric', 'between:-180,180'],
            'destination_lat' => ['required', 'numeric', 'between:-90,90'],
            'destination_lng' => ['required', 'numeric', 'between:-180,180'],
            // Max distance between the passenger's point and a meeting point.
            'radius_m' => ['sometimes', 'integer', 'min:500', 'max:50000'],
            'women_only' => ['sometimes', 'boolean'],
            // Day of boarding (Y-m-d) and seats needed.
            'date' => ['sometimes', 'nullable', 'date_format:Y-m-d'],
            'seats' => ['sometimes', 'integer', 'min:1', 'max:8'],
        ];
    }
}
