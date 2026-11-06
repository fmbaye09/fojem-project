import 'package:flutter/foundation.dart';

/// Configuration centralisée du backend Laravel FOJËM.
///
/// [baseUrl] pointe par défaut vers le serveur ; voir sa documentation pour
/// viser un backend local.
class ApiConfig {
  ApiConfig._();

  static const String _override = String.fromEnvironment('API_BASE_URL');

  /// Adresse de l'API, choisie à la compilation :
  /// - debug (Run d'Android Studio) : le backend Docker du poste, sur le
  ///   partage de connexion Windows auquel le téléphone est connecté ;
  /// - release (APK App Tester) : le serveur de test ;
  /// - `--dart-define=API_BASE_URL=...` l'emporte sur les deux
  ///   (`http://10.0.2.2:8000/api` depuis un émulateur Android).
  static const String baseUrl = _override != ''
      ? _override
      : kDebugMode
          ? 'http://192.168.137.1:8000/api'
          : 'http://169.58.156.95:8081/api';

  /// Délai avant abandon d'une requête — l'app doit rester utilisable même
  /// avec un réseau mobile médiocre, sans attendre indéfiniment non plus.
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);

  /// Résout une URL d'image/média pour s'assurer qu'elle pointe toujours
  /// vers l'hôte actif du backend même si elle a été sauvegardée avec une
  /// ancienne IP ou sous forme relative.
  static String? resolveMediaUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    final trimmed = url.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      final uri = Uri.parse(trimmed);
      final apiUri = Uri.parse(baseUrl);
      if (uri.host != apiUri.host || uri.port != apiUri.port) {
        return uri
            .replace(scheme: apiUri.scheme, host: apiUri.host, port: apiUri.port)
            .toString();
      }
      return trimmed;
    }
    final base = baseUrl.replaceAll('/api', '');
    return '$base/${trimmed.startsWith('/') ? trimmed.substring(1) : trimmed}';
  }
}
