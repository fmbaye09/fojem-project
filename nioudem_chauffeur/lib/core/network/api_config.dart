/// Configuration centralisée de l'API backend Laravel (FOJEM Match).
///
/// Remplace Firestore comme source de vérité pour tout sauf le chat (qui
/// reste sur Firebase/Firestore — voir `lib/services/chat_repository.dart`).
class ApiConfig {
  ApiConfig._();

  /// URL de base de l'API en production. Pas de mode debug/local basculé
  /// automatiquement : ce repository n'a pas de flavor de build séparée,
  /// donc toute l'app pointe vers le backend de production.
  static const String baseUrl = 'http://169.58.156.95:8081/api';

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);

  /// Délai d'envoi des uploads multipart (photos/documents jusqu'à 8 Mo).
  static const Duration uploadTimeout = Duration(seconds: 90);
}
