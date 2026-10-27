import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stockage sécurisé (Keychain iOS / Keystore Android) du token Sanctum —
/// remplace l'ancien état volatile en mémoire (Provider) qui perdait la
/// session à chaque redémarrage de l'app.
class TokenStorage {
  static const _tokenKey = 'fojem_auth_token';

  final FlutterSecureStorage _storage;

  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<void> saveToken(String token) => _storage.write(key: _tokenKey, value: token);

  Future<void> clear() => _storage.delete(key: _tokenKey);
}
