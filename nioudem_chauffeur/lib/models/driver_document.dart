import 'package:flutter/material.dart';

/// Les 9 pièces exigées pour valider un profil chauffeur. [apiValue] est la
/// valeur exacte attendue par le backend dans le champ `document_type` de
/// `POST /driver/documents` (toute autre valeur est refusée en 422).
enum DriverDocumentType {
  permisRecto('permis_recto', 'Permis de conduire (recto)', Icons.badge_outlined),
  permisVerso('permis_verso', 'Permis de conduire (verso)', Icons.badge_outlined),
  carteGrise('carte_grise', 'Carte grise du véhicule', Icons.description_outlined),
  vehiculeAvant('vehicule_avant', 'Véhicule — vue de face', Icons.directions_car_outlined),
  vehiculeArriere('vehicule_arriere', 'Véhicule — vue de derrière', Icons.directions_car_outlined),
  vehiculeGauche('vehicule_gauche', 'Véhicule — côté gauche', Icons.directions_car_outlined),
  vehiculeDroite('vehicule_droite', 'Véhicule — côté droit', Icons.directions_car_outlined),
  selfieCarteGrise(
      'selfie_carte_grise', 'Vous, tenant votre carte grise', Icons.person_pin_outlined),
  selfiePermis('selfie_permis', 'Vous, tenant votre permis', Icons.person_pin_outlined);

  final String apiValue;
  final String label;
  final IconData icon;

  const DriverDocumentType(this.apiValue, this.label, this.icon);

  static DriverDocumentType? fromApi(String? value) {
    for (final type in values) {
      if (type.apiValue == value) return type;
    }
    return null;
  }
}

/// Statut de revue d'un document soumis (`driver_documents.status`).
/// `missing` n'existe pas côté backend : c'est l'absence du type dans la
/// réponse de `GET /driver/documents`.
enum DriverDocumentStatus { missing, pending, approved, rejected }

DriverDocumentStatus _statusFromString(String? value) {
  switch (value) {
    case 'approved':
      return DriverDocumentStatus.approved;
    case 'rejected':
      return DriverDocumentStatus.rejected;
    default:
      // Tout document présent côté serveur sans statut connu est traité
      // comme en attente de revue — jamais comme "validé".
      return DriverDocumentStatus.pending;
  }
}

class DriverDocument {
  final String id;
  final DriverDocumentType type;
  final DriverDocumentStatus status;
  final String? rejectionReason;
  final DateTime? updatedAt;

  const DriverDocument({
    required this.id,
    required this.type,
    required this.status,
    this.rejectionReason,
    this.updatedAt,
  });

  /// Retourne null si le `document_type` est inconnu de cette version de
  /// l'app (ex. nouveau type ajouté côté backend) plutôt que de planter.
  static DriverDocument? fromJson(Map<String, dynamic> json) {
    final type = DriverDocumentType.fromApi(json['document_type'] as String?);
    if (type == null) return null;
    final reason = json['rejection_reason'] as String?;
    return DriverDocument(
      id: '${json['id'] ?? ''}',
      type: type,
      status: _statusFromString(json['status'] as String?),
      rejectionReason: (reason == null || reason.trim().isEmpty) ? null : reason.trim(),
      updatedAt: DateTime.tryParse('${json['updated_at'] ?? ''}'),
    );
  }
}
