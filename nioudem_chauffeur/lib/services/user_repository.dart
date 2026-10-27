import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../models/app_user.dart';

/// Profils publics tiers — contre l'API Laravel (`GET /api/users/{id}`).
///
/// Le backend expose désormais un profil public minimal pour un utilisateur
/// autre que soi (`id, full_name, profile_photo_url, gender` — ni email, ni
/// téléphone, ni autre champ sensible ; voir `fojem_backend/README.md`,
/// section "Profils publics"). `AppUser.fromJson` sait déjà lire cette
/// forme réduite (les champs chauffeur restent simplement absents/par
/// défaut). Les écrans appelants (chat) traitaient déjà cet appel comme
/// optionnel (`.catchError((_) => null)` / `try/catch`) et retombent sur le
/// nom déjà connu par le contexte en cas d'échec — ce comportement est
/// conservé tel quel, seul le backend de [fetch] change.
class UserRepository {
  final ApiClient _client;

  UserRepository({ApiClient? client}) : _client = client ?? ApiClient();

  Future<AppUser?> fetch(String userId) async {
    if (userId.isEmpty) return null;
    try {
      final body = await _client.get('/users/$userId');
      final json = body['user'] as Map<String, dynamic>?;
      if (json == null) return null;
      return AppUser.fromJson(json);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Enregistre le token FCM auprès du backend Laravel.
  Future<void> updateFcmToken(String userId, String token) async {
    try {
      await _client.post('/fcm-token', data: {'fcm_token': token});
    } catch (_) {}
  }
}
