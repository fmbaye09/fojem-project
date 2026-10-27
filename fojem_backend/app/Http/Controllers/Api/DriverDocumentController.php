<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\DriverDocuments\StoreDriverDocumentRequest;
use App\Models\Driver;
use App\Models\DriverDocument;
use App\Services\DriverVerificationService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

class DriverDocumentController extends Controller
{
    /**
     * All documents submitted so far by the authenticated driver, so the
     * app can render the activation checklist (which of
     * DriverDocument::REQUIRED_TYPES are missing/pending/approved/rejected).
     */
    public function index(Request $request)
    {
        $driver = $this->driverOrFail($request);

        return response()->json([
            'documents' => $driver->documents()->get([
                'id', 'document_type', 'status', 'rejection_reason', 'created_at', 'updated_at',
            ]),
        ]);
    }

    /**
     * Uploads (or re-uploads after a rejection) one of the required
     * document types. Re-submitting a type always resets it to pending and
     * clears any prior rejection/review - a single rejected piece doesn't
     * require re-uploading everything else. verification_status is then
     * re-derived the same way an admin review does (see
     * DriverVerificationService), so a resubmission after a rejection can
     * bring the driver back to "pending" instead of staying "rejected".
     */
    public function store(StoreDriverDocumentRequest $request)
    {
        $driver = $this->driverOrFail($request);
        $type = $request->string('document_type')->value();

        $existing = DriverDocument::where('driver_id', $driver->id)
            ->where('document_type', $type)
            ->first();

        $path = $request->file('file')->store("driver-documents/{$driver->id}", 'local');

        $document = DriverDocument::updateOrCreate(
            ['driver_id' => $driver->id, 'document_type' => $type],
            [
                'file_url' => $path,
                'status' => DriverDocument::STATUS_PENDING,
                'rejection_reason' => null,
                'reviewed_by_admin_id' => null,
            ],
        );

        if ($existing && $existing->file_url !== $path) {
            Storage::disk('local')->delete($existing->file_url);
        }

        DriverVerificationService::recompute($driver);

        return response()->json(['document' => $document->fresh()], 201);
    }

    /**
     * Get current onboarding state for the driver (vehicle info + documents).
     */
    public function getOnboarding(Request $request)
    {
        $driver = $this->driverOrFail($request);

        $vehicle = [
            'brand' => $driver->pending_vehicle_brand,
            'model' => $driver->pending_vehicle_model,
            'color' => $driver->pending_vehicle_color,
            'plate_number' => $driver->pending_vehicle_plate_number,
            'seat_count' => $driver->pending_vehicle_seat_count ? (string) $driver->pending_vehicle_seat_count : null,
        ];

        $documents = $driver->documents()->get([
            'id', 'document_type', 'status', 'rejection_reason', 'updated_at',
        ]);

        return response()->json([
            'vehicle' => $vehicle,
            'documents' => $documents,
        ]);
    }

    /**
     * Multipart single-shot submission for vehicle info + document photos.
     */
    public function submitOnboarding(Request $request)
    {
        $driver = $this->driverOrFail($request);

        $vehicleFields = [];
        if ($request->has('brand')) $vehicleFields['pending_vehicle_brand'] = $request->input('brand');
        if ($request->has('model')) $vehicleFields['pending_vehicle_model'] = $request->input('model');
        if ($request->has('color')) $vehicleFields['pending_vehicle_color'] = $request->input('color');
        if ($request->has('plate_number')) $vehicleFields['pending_vehicle_plate_number'] = $request->input('plate_number');
        if ($request->has('seat_count')) $vehicleFields['pending_vehicle_seat_count'] = $request->input('seat_count');

        if (! empty($vehicleFields)) {
            $driver->update($vehicleFields);
        }

        foreach (DriverDocument::REQUIRED_TYPES as $type) {
            if ($request->hasFile($type)) {
                $file = $request->file($type);
                $path = $file->store("driver-documents/{$driver->id}", 'local');

                $existing = DriverDocument::where('driver_id', $driver->id)
                    ->where('document_type', $type)
                    ->first();

                DriverDocument::updateOrCreate(
                    ['driver_id' => $driver->id, 'document_type' => $type],
                    [
                        'file_url' => $path,
                        'status' => DriverDocument::STATUS_PENDING,
                        'rejection_reason' => null,
                        'reviewed_by_admin_id' => null,
                    ]
                );

                if ($existing && $existing->file_url !== $path) {
                    Storage::disk('local')->delete($existing->file_url);
                }
            }
        }

        DriverVerificationService::recompute($driver);

        return $this->getOnboarding($request);
    }

    private function driverOrFail(Request $request): Driver
    {
        $user = $request->user();
        if (! $user->is_driver) {
            abort(403, 'Profil chauffeur requis.');
        }

        $driver = $user->driver ?? Driver::firstOrCreate(
            ['user_id' => $user->id],
            ['verification_status' => Driver::STATUS_PENDING]
        );

        return $driver;
    }
}
