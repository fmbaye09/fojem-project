import 'package:dio/dio.dart';
import '../core/network/api_client.dart';
import '../models/driver_document.dart';

/// État du formulaire d'activation tel que stocké par le backend
/// (`GET /driver/onboarding`) : infos véhicule déjà saisies + documents déjà
/// envoyés (un type absent de la liste est simplement "manquant").
class DriverOnboarding {
  final Map<String, String> vehicle;
  final List<DriverDocument> documents;

  /// Contact d'urgence (nom, téléphone), vide s'il n'a pas encore été donné.
  final ({String name, String phone})? emergencyContact;

  const DriverOnboarding({required this.vehicle, required this.documents, this.emergencyContact});
}

/// Un fichier à envoyer pour un type de pièce.
class OnboardingFile {
  final List<int> bytes;
  final String filename;

  const OnboardingFile({required this.bytes, required this.filename});
}

/// Formulaire d'activation chauffeur — contre l'API Laravel
/// (`/api/driver/onboarding`).
///
/// - `GET` renvoie les infos véhicule et les documents déjà enregistrés.
/// - `POST` (multipart) enregistre **en une seule fois** les infos véhicule
///   et les photos ; les types déjà envoyés sont facultatifs, ce qui permet
///   de ne renvoyer que les pièces refusées.
///
/// Le statut global du compte (`drivers.verification_status`) reste calculé
/// par le backend / l'admin : cette couche ne le déduit jamais des
/// documents.
class DriverDocumentRepository {
  final ApiClient _client;

  DriverDocumentRepository({ApiClient? client}) : _client = client ?? ApiClient();

  Future<DriverOnboarding> fetch() async {
    final body = await _client.get('/driver/onboarding');
    return _parse(body);
  }

  Future<DriverOnboarding> submit({
    String? brand,
    String? model,
    String? color,
    String? plateNumber,
    int? seatCount,
    String? emergencyContactName,
    String? emergencyContactPhone,
    required Map<DriverDocumentType, OnboardingFile> files,
  }) async {
    final form = FormData.fromMap({
      if (emergencyContactName != null) 'emergency_contact_name': emergencyContactName,
      if (emergencyContactPhone != null) 'emergency_contact_phone': emergencyContactPhone,
      if (brand != null) 'brand': brand,
      if (model != null) 'model': model,
      if (color != null) 'color': color,
      if (plateNumber != null) 'plate_number': plateNumber,
      if (seatCount != null) 'seat_count': seatCount,
      for (final e in files.entries)
        e.key.apiValue: MultipartFile.fromBytes(e.value.bytes, filename: e.value.filename),
    });
    final body = await _client.postMultipart('/driver/onboarding', form);
    return _parse(body);
  }

  DriverOnboarding _parse(Map<String, dynamic> body) {
    final vehicle = <String, String>{};
    final raw = body['vehicle'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v != null) vehicle['$k'] = '$v';
      });
    }
    final list = body['documents'] as List<dynamic>? ?? const [];
    final documents = list
        .whereType<Map<String, dynamic>>()
        .map(DriverDocument.fromJson)
        .whereType<DriverDocument>()
        .toList();
    final contact = body['emergency_contact'];
    return DriverOnboarding(
      vehicle: vehicle,
      documents: documents,
      emergencyContact: contact is Map
          ? (name: '${contact['name'] ?? ''}', phone: '${contact['phone'] ?? ''}')
          : null,
    );
  }

  /// Modifie le contact d'urgence depuis le profil.
  Future<void> updateEmergencyContact({required String name, required String phone}) async {
    await _client.put('/profile/emergency-contact', data: {'name': name, 'phone': phone});
  }
}
