/// Configuration centralisée du backend Laravel FOJËM.
///
/// [baseUrl] pointe par défaut vers le serveur ; voir sa documentation pour
/// viser un backend local.
class ApiConfig {
  ApiConfig._();

  /// Adresse de l'API, choisie à la compilation. Par défaut : le serveur de
  /// test. En local : `flutter run --dart-define=API_BASE_URL=http://192.168.137.1:8000/api`
  /// (ou `http://10.0.2.2:8000/api` depuis un émulateur Android).
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://169.58.156.95:8081/api',
  );

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
