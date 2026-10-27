<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;

class IdentityVerificationController extends Controller
{
    /**
     * Get current identity verification state for the authenticated user.
     */
    public function show(Request $request)
    {
        $user = $request->user();

        return response()->json([
            'identity_status' => $user->identity_status ?? 'none',
            'document_type' => $user->identity_document_type,
            'document_number' => $user->identity_document_number,
            'front_url' => $user->identity_front_url,
            'back_url' => $user->identity_back_url,
            'rejection_reason' => $user->identity_rejection_reason,
            'submitted_at' => $user->identity_submitted_at?->toIso8601String(),
            'reviewed_at' => $user->identity_reviewed_at?->toIso8601String(),
            'is_verified' => (bool) $user->identity_verified,
        ]);
    }

    /**
     * Submit identity documents for verification (choice: CNI / id_card OR Permis / driver_license).
     */
    public function submit(Request $request)
    {
        $user = $request->user();

        $request->validate([
            'document_type' => 'required|string|in:id_card,driver_license',
            'document_number' => 'nullable|string|max:80',
            'front_file' => 'required|file|mimes:jpeg,png,jpg,webp,pdf|max:10240',
            'back_file' => 'nullable|file|mimes:jpeg,png,jpg,webp,pdf|max:10240',
        ], [
            'document_type.required' => 'Veuillez choisir un type de document (pièce d’identité ou permis).',
            'document_type.in' => 'Le document doit être une pièce d’identité (id_card) ou un permis (driver_license).',
            'front_file.required' => 'La photo recto du document est obligatoire.',
            'front_file.max' => 'La taille maximale autorisée pour le fichier est de 10 Mo.',
            'back_file.max' => 'La taille maximale autorisée pour le verso est de 10 Mo.',
        ]);

        $folder = "identity-documents/{$user->id}";

        // Upload recto
        $frontPath = $request->file('front_file')->store($folder, 'public');
        $frontUrl = $request->schemeAndHttpHost() . '/storage/' . $frontPath;

        // Upload verso (optionnel)
        $backUrl = null;
        if ($request->hasFile('back_file')) {
            $backPath = $request->file('back_file')->store($folder, 'public');
            $backUrl = $request->schemeAndHttpHost() . '/storage/' . $backPath;
        }

        $user->update([
            'identity_document_type' => $request->string('document_type')->value(),
            'identity_document_number' => $request->filled('document_number') ? $request->string('document_number')->value() : null,
            'identity_front_url' => $frontUrl,
            'identity_back_url' => $backUrl ?? $user->identity_back_url,
            'identity_status' => 'pending',
            'identity_rejection_reason' => null,
            'identity_submitted_at' => now(),
            'identity_reviewed_at' => null,
        ]);

        return response()->json([
            'message' => 'Documents d’identité reçus. Votre demande est en cours de vérification.',
            'user' => $user->fresh(),
            'verification' => [
                'identity_status' => 'pending',
                'document_type' => $user->identity_document_type,
                'document_number' => $user->identity_document_number,
                'front_url' => $user->identity_front_url,
                'back_url' => $user->identity_back_url,
                'is_verified' => false,
            ],
        ], 200);
    }
}
