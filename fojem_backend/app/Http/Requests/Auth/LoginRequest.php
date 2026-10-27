<?php

namespace App\Http\Requests\Auth;

use Illuminate\Foundation\Http\FormRequest;

class LoginRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'email' => ['required_without_all:phone_number,login', 'nullable', 'string'],
            'phone_number' => ['required_without_all:email,login', 'nullable', 'string'],
            'login' => ['required_without_all:email,phone_number', 'nullable', 'string'],
            'password' => ['required', 'string'],
            'client_type' => ['sometimes', 'string', 'in:passenger,driver'],
            'device_id' => ['sometimes', 'string', 'max:255'],
        ];
    }
}
