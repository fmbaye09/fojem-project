<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Ajoute la carte d'identité (recto / verso) aux pièces du dossier chauffeur.
 * La colonne `document_type` est un enum Laravel, soit une contrainte CHECK
 * sous PostgreSQL : on la remplace par une contrainte qui inclut les deux
 * nouveaux types.
 */
return new class extends Migration
{
    private const BASE_TYPES = [
        'permis_recto', 'permis_verso', 'carte_grise',
        'vehicule_avant', 'vehicule_arriere', 'vehicule_gauche', 'vehicule_droite',
        'selfie_carte_grise', 'selfie_permis',
    ];

    public function up(): void
    {
        $this->setAllowedTypes([...self::BASE_TYPES, 'cni_recto', 'cni_verso']);
    }

    public function down(): void
    {
        DB::table('driver_documents')->whereIn('document_type', ['cni_recto', 'cni_verso'])->delete();
        $this->setAllowedTypes(self::BASE_TYPES);
    }

    private function setAllowedTypes(array $types): void
    {
        $list = implode(', ', array_map(fn ($t) => "'$t'", $types));
        DB::statement('ALTER TABLE driver_documents DROP CONSTRAINT IF EXISTS driver_documents_document_type_check');
        DB::statement("ALTER TABLE driver_documents ADD CONSTRAINT driver_documents_document_type_check CHECK (document_type IN ($list))");
    }
};
