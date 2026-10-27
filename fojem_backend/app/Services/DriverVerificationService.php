<?php

namespace App\Services;

use App\Models\Driver;
use App\Models\DriverDocument;
use App\Models\Vehicle;
use Illuminate\Support\Facades\Log;

/**
 * Single source of truth for deriving drivers.verification_status from its
 * documents. Used both when an admin reviews a document and when a driver
 * (re-)uploads one, so the status can never drift out of sync with the
 * documents it summarizes.
 */
class DriverVerificationService
{
    /**
     * - any required document rejected  -> driver stays/becomes "rejected"
     * - all required documents approved -> driver becomes "approved"
     * - otherwise (missing and/or pending documents remain) -> "pending"
     */
    public static function recompute(Driver $driver): void
    {
        $documents = $driver->documents()->get(['document_type', 'status']);

        $hasRejected = $documents->contains(fn ($d) => $d->status === DriverDocument::STATUS_REJECTED);

        $approvedTypes = $documents->where('status', DriverDocument::STATUS_APPROVED)
            ->pluck('document_type')
            ->unique();

        $allRequiredApproved = collect(DriverDocument::REQUIRED_TYPES)
            ->diff($approvedTypes)
            ->isEmpty();

        $newStatus = match (true) {
            $allRequiredApproved => Driver::STATUS_APPROVED,
            $hasRejected => Driver::STATUS_REJECTED,
            default => Driver::STATUS_PENDING,
        };

        $becomesApproved = $newStatus === Driver::STATUS_APPROVED && $driver->verification_status !== $newStatus;

        if ($driver->verification_status !== $newStatus) {
            $driver->update([
                'verification_status' => $newStatus,
                'verified_at' => $newStatus === Driver::STATUS_APPROVED ? now() : $driver->verified_at,
            ]);
        }

        if ($becomesApproved) {
            self::createVehicleFromPendingInfo($driver);
        }
    }

    /**
     * First-time approval only: turns the vehicle info the driver entered
     * during activation (drivers.pending_vehicle_*) into a real Vehicle row,
     * then clears those columns. No-ops if the driver already has a
     * vehicle (re-approval after a later document re-review) or never
     * entered that info (older account / activation flow skipped it).
     */
    private static function createVehicleFromPendingInfo(Driver $driver): void
    {
        if ($driver->vehicles()->exists() || ! $driver->pending_vehicle_plate_number) {
            return;
        }

        try {
            Vehicle::create([
                'driver_id' => $driver->id,
                'plate_number' => $driver->pending_vehicle_plate_number,
                'brand' => $driver->pending_vehicle_brand,
                'model' => $driver->pending_vehicle_model,
                'color' => $driver->pending_vehicle_color,
                'seat_count' => $driver->pending_vehicle_seat_count,
                'is_active' => true,
            ]);

            $driver->update([
                'pending_vehicle_brand' => null,
                'pending_vehicle_model' => null,
                'pending_vehicle_color' => null,
                'pending_vehicle_plate_number' => null,
                'pending_vehicle_seat_count' => null,
            ]);
        } catch (\Throwable $e) {
            // Most likely plate_number was taken by someone else between
            // activation and approval. Never let this block the driver's
            // approval - they can still declare a vehicle manually via
            // POST /api/vehicles.
            Log::warning('Echec de creation automatique du vehicule a l\'approbation du chauffeur.', [
                'driver_id' => $driver->id,
                'error' => $e->getMessage(),
            ]);
        }
    }
}
