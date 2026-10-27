import 'package:dio/dio.dart';
import '../core/network/api_client.dart';

/// Profil de l'utilisateur connecté — contre l'API Laravel
/// (`PATCH /api/profile`, `POST /api/profile/photo`).
///
/// Volontairement, ces méthodes ne renvoient pas d'`AppUser` : la réponse
/// `{ "user": {...} }` de ces routes n'embarque pas forcément la relation
/// `driver`, et un `AppUser` reconstruit sans elle aurait un
/// `driverStatus == none` — ce qui renverrait l'utilisateur vers l'écran de
/// vérification via le routeur. Les écrans appellent donc
/// `AppProvider.refreshUser()` (`GET /auth/me`, profil complet) après succès.
class ProfileRepository {
  final ApiClient _client;

  ProfileRepository({ApiClient? client}) : _client = client ?? ApiClient();

  Future<void> updateFullName(String fullName) async {
    await _client.patch('/profile', data: {'full_name': fullName});
  }

  /// jpg/jpeg/png, 4 Mo max côté backend.
  Future<void> uploadPhoto({required List<int> bytes, required String filename}) async {
    final form = FormData.fromMap({
      'photo': MultipartFile.fromBytes(bytes, filename: filename),
    });
    await _client.postMultipart('/profile/photo', form);
  }
}
