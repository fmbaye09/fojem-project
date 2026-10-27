<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Models\AdminRole;

class AdminRoleController extends Controller
{
    public function index()
    {
        return response()->json(['data' => AdminRole::with('permissions')->get()]);
    }
}
