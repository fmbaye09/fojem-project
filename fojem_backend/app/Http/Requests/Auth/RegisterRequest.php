<?php

namespace App\Http\Requests\Auth;

use Illuminate\Foundation\Http\FormRequest;

class RegisterRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'full_name' => ['required', 'string', 'max:120'],
            'email' => ['required', 'email', 'max:160', 'unique:users,email'],
            'password' => ['required', 'string', 'min:8'],
            'phone_number' => ['required', 'string', 'max:20', 'unique:users,phone_number'],
            'gender' => ['required', 'in:male,female,other'],
            'language' => ['sometimes', 'in:fr,wo,en'],
            'client_type' => ['sometimes', 'in:passenger,driver'],
            'is_driver' => ['sometimes', 'boolean'],
            'device_id' => ['sometimes', 'string', 'max:255'],
        ];
    }
}
