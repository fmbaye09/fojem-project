import 'dart:async';
import 'package:flutter/material.dart';
import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../core/network/token_storage.dart';
import '../models/app_user.dart';
import '../services/auth/api_auth_service.dart';
import '../services/auth/auth_service.dart';
import '../services/auth/chat_auth_bridge.dart';
import '../services/push_notification_service.dart';

/// État d'authentification de l'app — remplace l'ancien flux Firebase
/// (authStateChanges + doc Firestore) par une session basée sur un token
/// Sanctum stocké de façon sécurisée (`flutter_secure_storage`) et restaurée
/// au démarrage via `GET /auth/me`.
class AppProvider extends ChangeNotifier {
  final AuthService authService;
  final ApiClient apiClient;
  final TokenStorage _tokenStorage;
  final ChatAuthBridge _chatAuthBridge;
  final PushNotificationService _pushService;

  AppUser? _user;
  bool _isLoading = true;
  String? _lastError;

  AppProvider({
    AuthService? authService,
    ApiClient? apiClient,
    TokenStorage? tokenStorage,
    ChatAuthBridge? chatAuthBridge,
    PushNotificationService? pushService,
  })  : apiClient = apiClient ?? ApiClient(),
        _tokenStorage = tokenStorage ?? TokenStorage(),
        _chatAuthBridge = chatAuthBridge ?? ChatAuthBridge(),
        _pushService = pushService ?? PushNotificationService(),
        authService = authService ?? ApiAuthService() {
    this.apiClient.onUnauthorized = _handleUnauthorized;
    _restoreSession();
  }

  AppUser? get user => _user;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _user != null;
  String? get lastError => _lastError;

  Future<void> _restoreSession() async {
    final token = await _tokenStorage.readToken();
    if (token == null || token.isEmpty) {
      _isLoading = false;
      notifyListeners();
      return;
    }
    try {
      final user = await authService.me();
      _user = user;
      if (authService is ApiAuthService) {
        final customToken = (authService as ApiAuthService).lastFirebaseCustomToken;
        await _chatAuthBridge.signInWithCustomToken(customToken);
      } else {
        await _chatAuthBridge.signInWithCustomToken(null);
      }
      unawaited(_pushService.initialize(user.id));
      _startAutoSync();
    } catch (_) {
      // Token invalide/expiré : on repart sur un état déconnecté propre.
      await _tokenStorage.clear();
      _user = null;
    }
    _isLoading = false;
    notifyListeners();
  }

  Timer? _autoSyncTimer;

  void _startAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_user != null) refreshUser();
    });
  }

  void _handleUnauthorized() {
    if (_user == null) return;
    _user = null;
    _tokenStorage.clear();
    _chatAuthBridge.signOut();
    notifyListeners();
  }

  Future<bool> register({
    required String fullName,
    required String email,
    required String password,
    required String phoneNumber,
    required String gender,
  }) async {
    _lastError = null;
    try {
      final result = await authService.register(
        fullName: fullName,
        email: email,
        password: password,
        phoneNumber: phoneNumber,
        gender: gender,
      );
      // Cette app est réservée aux chauffeurs : chaque nouveau compte
      // devient automatiquement chauffeur (statut `pending` côté backend).
      final withDriver = await authService.becomeDriver();
      _user = withDriver;
      await _chatAuthBridge.signInWithCustomToken(result.firebaseCustomToken);
      unawaited(_pushService.initialize(withDriver.id));
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _lastError = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> login({required String email, required String password}) async {
    _lastError = null;
    try {
      final result = await authService.login(email: email, password: password);
      _user = result.user;
      await _chatAuthBridge.signInWithCustomToken(result.firebaseCustomToken);
      unawaited(_pushService.initialize(result.user.id));
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _lastError = e.message;
      notifyListeners();
      return false;
    }
  }

  /// Recharge le profil courant (ex. après une modification, ou pour
  /// rafraîchir `driverStatus` si l'utilisateur revient sur l'app après une
  /// revue admin de ses documents).
  Future<void> refreshUser() async {
    if (_user == null) return;
    try {
      _user = await authService.me();
      if (authService is ApiAuthService) {
        final customToken = (authService as ApiAuthService).lastFirebaseCustomToken;
        await _chatAuthBridge.signInWithCustomToken(customToken);
      }
      notifyListeners();
    } catch (_) {
      // Silencieux : on garde l'état précédent plutôt que de vider l'écran
      // sur un simple hoquet réseau.
    }
  }

  Future<void> signOut() async {
    _autoSyncTimer?.cancel();
    _pushService.reset();
    try {
      await authService.logout();
    } catch (_) {
      // Même si l'appel réseau échoue, on nettoie l'état local — l'usager
      // ne doit jamais rester bloqué connecté côté UI par une erreur serveur.
    }
    await _chatAuthBridge.signOut();
    _user = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    super.dispose();
  }
}
