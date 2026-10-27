<?php

namespace App\Http\Requests\Vehicles;

use Illuminate\Foundation\Http\FormRequest;

class StoreVehicleRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        // plate_number stays globally unique across all vehicles (any
        // driver, any of their vehicles) - store() always inserts a new
        // row now, there is no "own existing vehicle" to ignore anymore.
        return [
            'plate_number' => ['required', 'string', 'max:20', 'unique:vehicles,plate_number'],
            'brand' => ['required', 'string', 'max:60'],
            'model' => ['required', 'string', 'max:60'],
            'color' => ['required', 'string', 'max:60'],
            'seat_count' => ['required', 'integer', 'min:1', 'max:8'],
        ];
    }
}
