import type {
  AccountStatus,
  DriverDocument,
  DriverDocumentType,
  VerificationStatus,
  IdentityStatus,
  IdentityDocumentType,
} from "../../types/api";

// Libellés français + tons de Badge pour les statuts renvoyés bruts par
// l'API. Ne jamais afficher la valeur d'enum telle quelle à l'écran.
// Tons : uniquement ceux exposés par <Badge> (tokens Tailwind existants) —
// "primary" est l'orange de marque, utilisé pour "à traiter".

export const ACCOUNT_STATUS_LABEL: Record<AccountStatus, string> = {
  active: "Actif",
  disabled: "Désactivé",
  deleted: "Supprimé",
};

export const ACCOUNT_STATUS_TONE = { active: "success", disabled: "danger", deleted: "neutral" } as const;

export const VERIFICATION_LABEL: Record<VerificationStatus, string> = {
  pending: "En attente",
  approved: "Approuvé",
  rejected: "Rejeté",
};

export const VERIFICATION_TONE = { pending: "primary", approved: "success", rejected: "danger" } as const;

export const IDENTITY_STATUS_LABEL: Record<IdentityStatus, string> = {
  none: "Non soumis",
  pending: "En attente",
  approved: "Validé",
  rejected: "Rejeté",
};

export const IDENTITY_STATUS_TONE = {
  none: "neutral",
  pending: "primary",
  approved: "success",
  rejected: "danger",
} as const;

export const IDENTITY_DOC_TYPE_LABEL: Record<IdentityDocumentType, string> = {
  id_card: "Pièce d'identité (CNI/Passeport)",
  driver_license: "Permis de conduire",
};

/** Ordre d'affichage fixe des 9 pièces exigées. */
export const DOCUMENT_TYPES_ORDERED: readonly DriverDocumentType[] = [
  "permis_recto",
  "permis_verso",
  "carte_grise",
  "vehicule_avant",
  "vehicule_arriere",
  "vehicule_gauche",
  "vehicule_droite",
  "selfie_carte_grise",
  "selfie_permis",
];

export const DOCUMENT_TYPE_LABEL: Record<DriverDocumentType, string> = {
  permis_recto: "Permis de conduire (recto)",
  permis_verso: "Permis de conduire (verso)",
  carte_grise: "Carte grise",
  vehicule_avant: "Véhicule - face avant",
  vehicule_arriere: "Véhicule - face arrière",
  vehicule_gauche: "Véhicule - côté gauche",
  vehicule_droite: "Véhicule - côté droit",
  selfie_carte_grise: "Selfie avec la carte grise",
  selfie_permis: "Selfie avec le permis",
};

/**
 * Un chauffeur peut avoir renvoyé une pièce après un rejet : on ne garde que
 * la plus récente de chaque type (c'est elle qui compte pour la validation).
 */
export function latestDocumentByType(documents: DriverDocument[]): Partial<Record<DriverDocumentType, DriverDocument>> {
  const byType: Partial<Record<DriverDocumentType, DriverDocument>> = {};
  for (const doc of documents) {
    const current = byType[doc.document_type];
    if (!current || new Date(doc.created_at).getTime() > new Date(current.created_at).getTime()) {
      byType[doc.document_type] = doc;
    }
  }
  return byType;
}
