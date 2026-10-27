<?php

namespace App\Http\Requests\Admin\Settings;

use Illuminate\Foundation\Http\FormRequest;

class UpdatePlatformSettingRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'zone_name' => ['sometimes', 'string', 'max:100'],
            'price_per_km' => ['sometimes', 'numeric', 'min:0'],
            'commission_pct' => ['sometimes', 'numeric', 'min:0', 'max:100'],
        ];
    }
}
