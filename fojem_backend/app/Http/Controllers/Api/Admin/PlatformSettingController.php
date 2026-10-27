<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\Settings\UpdatePlatformSettingRequest;
use App\Models\PlatformSetting;
use App\Services\AuditLogger;

class PlatformSettingController extends Controller
{
    public function index()
    {
        return response()->json(['data' => PlatformSetting::orderBy('zone_name')->get()]);
    }

    public function update(UpdatePlatformSettingRequest $request, PlatformSetting $platformSetting)
    {
        $admin = $request->user();
        $old = $platformSetting->only(['zone_name', 'price_per_km', 'commission_pct']);

        $platformSetting->update([
            ...$request->only(['zone_name', 'price_per_km', 'commission_pct']),
            'updated_by_admin_id' => $admin->id,
        ]);

        AuditLogger::logFromRequest(
            $request,
            'platform_setting.updated',
            'platform_setting',
            $platformSetting->id,
            $old,
            $platformSetting->fresh()->only(['zone_name', 'price_per_km', 'commission_pct']),
        );

        return response()->json(['platform_setting' => $platformSetting->fresh()]);
    }
}
