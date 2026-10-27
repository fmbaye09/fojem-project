import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../models/app_user.dart';

/// Profils utilisateurs via l'API Laravel.
///
/// `GET /api/users/{id}` renvoie un profil public minimal (`id, full_name,
/// profile_photo_url, gender` — ni email, ni téléphone, ni autre champ
/// sensible), utilisé pour résoudre nom/avatar d'un tiers (ex. l'en-tête du
/// chat) quand cette info n'est pas déjà connue localement. Pour
/// l'utilisateur courant, [fetchMe]/`GET /auth/me` reste la source (profil
/// complet, y compris les champs chauffeur).
class UserRepository {
  final ApiClient _client;

  UserRepository({ApiClient? client}) : _client = client ?? ApiClient.instance;

  Future<AppUser?> fetch(String userId) async {
    if (userId.isEmpty) return null;
    try {
      final response = await _client.get('/users/$userId');
      final userJson = response['user'] as Map<String, dynamic>?;
      if (userJson == null) return null;
      return AppUser.fromApi(userJson);
    } on ApiException {
      return null;
    }
  }

  Future<AppUser?> fetchMe() async {
    try {
      final response = await _client.get('/auth/me');
      final userJson = response['user'] as Map<String, dynamic>?;
      if (userJson == null) return null;
      return AppUser.fromApi(userJson);
    } on ApiException {
      return null;
    }
  }
}
