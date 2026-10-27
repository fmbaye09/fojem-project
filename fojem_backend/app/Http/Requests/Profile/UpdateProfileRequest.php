<?php

namespace App\Http\Requests\Profile;

use Illuminate\Foundation\Http\FormRequest;

class UpdateProfileRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'full_name' => ['sometimes', 'string', 'max:120'],
            'phone_number' => ['sometimes', 'string', 'max:20', 'unique:users,phone_number,' . $this->user()?->id],
        ];
    }
}
