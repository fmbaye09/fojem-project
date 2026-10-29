<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\Drivers\ReviewDriverDocumentRequest;
use App\Models\Driver;
use App\Models\DriverDocument;
use App\Services\AuditLogger;
use App\Services\DriverVerificationService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

class DriverController extends Controller
{
    public function index(Request $request)
    {
        $query = Driver::query()->with('user')->latest();

        if ($status = $request->string('verification_status')->value()) {
            $query->where('verification_status', $status);
        }

        return response()->json($query->paginate($request->integer('per_page', 20)));
    }

    public function documents(Driver $driver)
    {
        // The raw storage path (file_url) never leaves this controller -
        // documents are sensitive personal/vehicle data, so admins fetch the
        // actual image/PDF through file() below (authenticated + permission
        // gated), not a public direct URL.
        $documents = $driver->documents()->latest()->get()->map(fn (DriverDocument $doc) => [
            'id' => $doc->id,
            'document_type' => $doc->document_type,
            'status' => $doc->status,
            'file_endpoint' => url("/api/admin/drivers/{$driver->id}/documents/{$doc->id}/file"),
            'rejection_reason' => $doc->rejection_reason,
            'reviewed_by_admin_id' => $doc->reviewed_by_admin_id,
            'created_at' => $doc->created_at,
            'updated_at' => $doc->updated_at,
        ]);

        return response()->json(['driver_id' => $driver->id, 'documents' => $documents]);
    }

    /** Streams a document's file to an authenticated, permission-checked admin. */
    public function file(Driver $driver, DriverDocument $docId)
    {
        $document = $docId;
        abort_if($document->driver_id !== $driver->id, 404);

        return Storage::disk('local')->response($document->file_url);
    }

    /**
     * Approve or reject one document, then re-derive drivers.verification_status
     * from the full set of required documents:
     *  - any required document rejected  -> driver stays/becomes "rejected"
     *  - all required documents approved -> driver becomes "approved"
     *  - otherwise (missing and/or pending documents remain) -> "pending"
     * This is intentionally simple/deterministic rather than a manual admin
     * toggle, so verification_status can never drift from the documents it
     * is supposed to summarize.
     */
    public function reviewDocument(ReviewDriverDocumentRequest $request, Driver $driver, DriverDocument $docId)
    {
        $document = $docId;
        abort_if($document->driver_id !== $driver->id, 404);

        $admin = $request->user();
        $old = ['status' => $document->status, 'rejection_reason' => $document->rejection_reason];

        $document->update([
            'status' => $request->string('status')->value(),
            'rejection_reason' => $request->string('status')->value() === 'rejected'
                ? $request->string('rejection_reason')->value()
                : null,
            'reviewed_by_admin_id' => $admin->id,
        ]);

        AuditLogger::logFromRequest(
            $request,
            'driver_document.reviewed',
            'driver_document',
            $document->id,
            $old,
            ['status' => $document->status, 'rejection_reason' => $document->rejection_reason],
        );

        $wasApproved = $driver->verification_status === Driver::STATUS_APPROVED;
        DriverVerificationService::recompute($driver);
        $driver->refresh();

        // Pas une notification par document approuvé : une seule quand le
        // compte passe « approuvé ». Un refus, lui, demande une action.
        if ($driver->user) {
            $notifications = app(\App\Services\NotificationService::class);
            if ($document->status === DriverDocument::STATUS_REJECTED) {
                $notifications->documentRejected($driver->user, $document->document_type, $document->rejection_reason);
            } elseif (! $wasApproved && $driver->verification_status === Driver::STATUS_APPROVED) {
                $notifications->driverApproved($driver->user);
            }
        }

        return response()->json([
            'document' => $document->fresh(),
            'driver' => $driver->fresh(),
        ]);
    }
}
