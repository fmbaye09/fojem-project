import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persistance sécurisée du token Sanctum (Keychain iOS / Keystore Android)
/// — plus jamais uniquement en mémoire dans un provider volatile, pour que
/// la session survive un redémarrage de l'app.
class SecureTokenStorage {
  static const _tokenKey = 'fojem_api_token';
  static const _userIdKey = 'fojem_user_id';

  final FlutterSecureStorage _storage;

  SecureTokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<void> saveToken(String token) => _storage.write(key: _tokenKey, value: token);

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<void> saveUserId(String userId) => _storage.write(key: _userIdKey, value: userId);

  Future<String?> readUserId() => _storage.read(key: _userIdKey);

  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userIdKey);
  }
}
