import '../../core/network/api_client.dart';
import '../../core/network/token_storage.dart';
import '../../models/app_user.dart';
import 'auth_service.dart';

/// Implémentation `AuthService` contre l'API Laravel (`/api/auth/*`).
class ApiAuthService implements AuthService {
  final ApiClient _client;
  final TokenStorage _tokenStorage;

  ApiAuthService({ApiClient? client, TokenStorage? tokenStorage})
      : _client = client ?? ApiClient(),
        _tokenStorage = tokenStorage ?? TokenStorage();

  @override
  Future<AuthResult> register({
    required String fullName,
    required String email,
    required String password,
    required String phoneNumber,
    required String gender,
  }) async {
    final body = await _client.post('/auth/register', data: {
      'full_name': fullName,
      'email': email,
      'password': password,
      'phone_number': phoneNumber,
      'gender': gender,
      'client_type': 'driver',
      'is_driver': true,
    });
    return _handleAuthResponse(body);
  }

  @override
  Future<AuthResult> login({required String email, required String password}) async {
    final body = await _client.post('/auth/login', data: {
      'email': email,
      'password': password,
      'client_type': 'driver',
    });
    return _handleAuthResponse(body);
  }

  Future<AuthResult> _handleAuthResponse(Map<String, dynamic> body) async {
    final token = body['token'] as String;
    await _tokenStorage.saveToken(token);
    final user = AppUser.fromJson(body['user'] as Map<String, dynamic>);
    return AuthResult(
      user: user,
      token: token,
      firebaseCustomToken: body['firebase_custom_token'] as String?,
    );
  }

  @override
  Future<AppUser> becomeDriver() async {
    await _client.post('/auth/become-driver');
    // La réponse renvoie `driver` (pas `user`) — /auth/me est rappelé par
    // AppProvider juste après pour obtenir le profil utilisateur complet et
    // à jour avec ce nouveau statut chauffeur.
    return me();
  }

  String? _lastFirebaseCustomToken;
  String? get lastFirebaseCustomToken => _lastFirebaseCustomToken;

  @override
  Future<AppUser> me() async {
    final body = await _client.get('/auth/me');
    _lastFirebaseCustomToken = body['firebase_custom_token'] as String?;
    return AppUser.fromJson(body['user'] as Map<String, dynamic>);
  }

  @override
  Future<void> logout() async {
    try {
      await _client.post('/auth/logout');
    } finally {
      await _tokenStorage.clear();
    }
  }
}
