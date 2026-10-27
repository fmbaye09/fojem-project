<?php

namespace App\Http\Requests\Admin\AdminUsers;

use Illuminate\Foundation\Http\FormRequest;

class StoreAdminUserRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'full_name' => ['required', 'string', 'max:120'],
            'email' => ['required', 'email', 'max:160', 'unique:admin_users,email'],
            'password' => ['required', 'string', 'min:8'],
            'role_id' => ['required', 'uuid', 'exists:admin_roles,id'],
            'is_active' => ['sometimes', 'boolean'],
        ];
    }
}
