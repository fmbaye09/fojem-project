import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/secure_token_storage.dart';
import '../../models/app_user.dart';
import 'auth_service.dart';

/// Implémentation email/mot de passe contre le backend Laravel (Sanctum).
///
/// Après un register/login réussi, si la réponse contient un
/// `firebase_custom_token` non nul, on l'utilise pour ouvrir une session
/// Firebase Auth *en plus* de la session API — c'est le seul pont dont le
/// chat (resté sur Firestore) a besoin. Si le champ est absent (backend pas
/// encore configuré pour Firebase), on continue sans bloquer la connexion :
/// le reste de l'app fonctionne, seul le chat restera indisponible tant que
/// ce pont n'est pas branché côté serveur.
class ApiAuthService implements AuthService {
  final ApiClient _client;
  final SecureTokenStorage _tokenStorage;
  final FirebaseAuth? _injectedFirebaseAuth;
  FirebaseAuth get _firebaseAuth => _injectedFirebaseAuth ?? FirebaseAuth.instance;

  final _authStateController = StreamController<AppUser?>.broadcast();
  AppUser? _currentUser;

  ApiAuthService({
    ApiClient? client,
    SecureTokenStorage? tokenStorage,
    FirebaseAuth? firebaseAuth,
  })  : _client = client ?? ApiClient.instance,
        _tokenStorage = tokenStorage ?? SecureTokenStorage(),
        _injectedFirebaseAuth = firebaseAuth {
    _client.onUnauthorized = _handleUnauthorized;
  }

  @override
  Stream<AppUser?> authStateChanges() => _authStateController.stream;

  @override
  AppUser? get currentUser => _currentUser;

  /// Appelé au démarrage de l'app pour restaurer une session existante à
  /// partir du token stocké de façon sécurisée.
  ///
  /// Une erreur réseau est propagée (le token est conservé, l'appelant
  /// propose de réessayer) ; un 401 déconnecte via [_handleUnauthorized].
  Future<void> restoreSession() async {
    final token = await _tokenStorage.readToken();
    if (token == null) {
      _emit(null);
      return;
    }
    final user = await _fetchMe();
    _emit(user);
  }

  @override
  Future<AppUser> register({
    required String fullName,
    required String email,
    required String password,
    required String phoneNumber,
    required String gender,
  }) async {
    final response = await _client.post('/auth/register', data: {
      'full_name': fullName,
      'email': email,
      'password': password,
      'phone_number': phoneNumber,
      'gender': gender,
    });
    return _handleAuthResponse(response);
  }

  @override
  Future<AppUser> login({
    String? email,
    String? phoneNumber,
    required String password,
    String clientType = 'passenger',
  }) async {
    final response = await _client.post('/auth/login', data: {
      if (email != null && email.isNotEmpty) 'email': email,
      if (phoneNumber != null && phoneNumber.isNotEmpty) 'phone_number': phoneNumber,
      'password': password,
      'client_type': clientType,
    });
    return _handleAuthResponse(response);
  }

  Future<AppUser> _handleAuthResponse(Map<String, dynamic> response) async {
    final token = response['token'] as String?;
    final userJson = response['user'] as Map<String, dynamic>?;
    if (token == null || userJson == null) {
      throw StateError('Réponse d\'authentification invalide.');
    }

    await _tokenStorage.saveToken(token);
    await _tokenStorage.saveUserId(userJson['id'] as String? ?? '');

    await _bridgeFirebaseAuth(response['firebase_custom_token'] as String?);

    final user = AppUser.fromApi(userJson);
    _emit(user);
    return user;
  }

  /// Ouvre une session Firebase Auth avec le custom token émis par le
  /// backend, pour que les règles Firestore du chat (qui exigent
  /// `request.auth != null`) acceptent l'utilisateur. Ne lève jamais
  /// d'exception : une erreur ici ne doit pas empêcher la connexion au
  Future<void> _bridgeFirebaseAuth(String? customToken) async {
    if (customToken != null && customToken.isNotEmpty) {
      try {
        await _firebaseAuth.signInWithCustomToken(customToken);
        if (kDebugMode) {
          debugPrint('[ApiAuthService] Connecté à Firebase Auth via custom token (uid: ${_firebaseAuth.currentUser?.uid})');
        }
        return;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[ApiAuthService] Échec du pont Firebase via custom token: $e');
        }
      }
    }

    if (_firebaseAuth.currentUser == null) {
      try {
        await _firebaseAuth.signInAnonymously();
        if (kDebugMode) {
          debugPrint('[ApiAuthService] Connecté à Firebase Auth anonymement (fallback)');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[ApiAuthService] Échec signInAnonymously: $e');
        }
      }
    }
  }

  @override
  Future<void> logout() async {
    try {
      await _client.post('/auth/logout');
    } catch (_) {}
    await _tokenStorage.clear();
    try {
      await _firebaseAuth.signOut();
    } catch (_) {}
    _emit(null);
  }

  @override
  Future<AppUser?> refreshCurrentUser() async {
    try {
      return await _fetchMe();
    } catch (_) {
      return null;
    }
  }

  Future<AppUser?> _fetchMe() async {
    final response = await _client.get('/auth/me');
    final userJson = response['user'] as Map<String, dynamic>?;
    if (userJson == null) return null;

    final customToken = response['firebase_custom_token'] as String?;
    await _bridgeFirebaseAuth(customToken);

    final user = AppUser.fromApi(userJson);
    _currentUser = user;
    return user;
  }

  void _handleUnauthorized() {
    _tokenStorage.clear();
    _emit(null);
  }

  void _emit(AppUser? user) {
    _currentUser = user;
    _authStateController.add(user);
  }

  void dispose() {
    _authStateController.close();
  }
}
