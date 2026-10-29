<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;

class DriverDocument extends Model
{
    use HasUuids, SoftDeletes;

    public const STATUS_PENDING = 'pending';
    public const STATUS_APPROVED = 'approved';
    public const STATUS_REJECTED = 'rejected';

    /**
     * The full set of document types a driver must have approved before
     * drivers.verification_status can move to "approved" (see
     * App\Services\DriverVerificationService::recompute()). Mirrors the
     * `document_type` enum in the driver_documents migration (CNI added by
     * 2026_11_01_000001_add_cni_to_driver_documents_table).
     */
    public const REQUIRED_TYPES = [
        'cni_recto',
        'cni_verso',
        'permis_recto',
        'permis_verso',
        'carte_grise',
        'vehicule_avant',
        'vehicule_arriere',
        'vehicule_gauche',
        'vehicule_droite',
        'selfie_carte_grise',
        'selfie_permis',
    ];

    protected $fillable = [
        'driver_id', 'document_type', 'file_url', 'status',
        'reviewed_by_admin_id', 'rejection_reason',
    ];

    public function driver(): BelongsTo
    {
        return $this->belongsTo(Driver::class);
    }

    public function reviewedByAdmin(): BelongsTo
    {
        return $this->belongsTo(AdminUser::class, 'reviewed_by_admin_id');
    }
}
