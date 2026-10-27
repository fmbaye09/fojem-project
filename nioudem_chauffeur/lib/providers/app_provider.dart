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
import '../services/trip_location_tracker.dart';

/// État d'authentification de l'app — remplace l'ancien flux Firebase
/// (authStateChanges + doc Firestore) par une session basée sur un token
/// Sanctum stocké de façon sécurisée (`flutter_secure_storage`) et restaurée
/// au démarrage via `GET /auth/me`.
class AppProvider extends ChangeNotifier {
  final AuthService authService;
  final TokenStorage _tokenStorage;
  final ChatAuthBridge _chatAuthBridge;
  final PushNotificationService _pushService;

  AppUser? _user;
  bool _isLoading = true;
  bool _sessionUnavailable = false;
  String? _lastError;

  AppProvider({
    AuthService? authService,
    TokenStorage? tokenStorage,
    ChatAuthBridge? chatAuthBridge,
    PushNotificationService? pushService,
  })  : _tokenStorage = tokenStorage ?? TokenStorage(),
        _chatAuthBridge = chatAuthBridge ?? ChatAuthBridge(),
        _pushService = pushService ?? PushNotificationService(),
        authService = authService ?? ApiAuthService() {
    ApiClient.onUnauthorized = _handleUnauthorized;
    _restoreSession();
  }

  AppUser? get user => _user;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _user != null;
  String? get lastError => _lastError;

  /// Un token est stocké mais le serveur n'a pas pu être joint au démarrage
  /// (pas de réseau, serveur arrêté). La session n'est pas perdue : l'écran
  /// d'accueil propose de réessayer via [retrySession].
  bool get sessionUnavailable => _sessionUnavailable;

  Future<void> _restoreSession() async {
    final token = await _tokenStorage.readToken();
    if (token == null || token.isEmpty) {
      _isLoading = false;
      notifyListeners();
      return;
    }
    try {
      final user = await authService.me();
      await _onSignedIn(user, _lastCustomToken());
      _sessionUnavailable = false;
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        // Token invalide/expiré : on repart sur un état déconnecté propre.
        await _tokenStorage.clear();
        _user = null;
        _sessionUnavailable = false;
      } else {
        // Réseau ou serveur indisponible : on garde le token pour réessayer.
        _sessionUnavailable = true;
        _lastError = e.message;
      }
    } catch (_) {
      _sessionUnavailable = true;
      _lastError = 'Impossible de restaurer votre session.';
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Relance la restauration de session après un échec réseau au démarrage.
  Future<void> retrySession() async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();
    await _restoreSession();
  }

  String? _lastCustomToken() {
    final service = authService;
    return service is ApiAuthService ? service.lastFirebaseCustomToken : null;
  }

  Future<void> _onSignedIn(AppUser user, String? firebaseCustomToken) async {
    _user = user;
    await _chatAuthBridge.signInWithCustomToken(firebaseCustomToken);
    unawaited(_pushService.initialize(user.id));
    _startAutoSync();
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
    _autoSyncTimer?.cancel();
    _pushService.reset();
    TripLocationTracker.instance.stop();
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
      // Le compte existe déjà et le token est enregistré : si cette étape
      // échoue, on connecte quand même l'utilisateur plutôt que de le
      // laisser dans un état à moitié créé.
      AppUser user;
      try {
        user = await authService.becomeDriver();
      } catch (_) {
        user = result.user;
      }
      await _onSignedIn(user, result.firebaseCustomToken);
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _lastError = e.message;
      notifyListeners();
      return false;
    } catch (_) {
      _lastError = 'Inscription impossible. Réessayez.';
      notifyListeners();
      return false;
    }
  }

  /// [login] : adresse e-mail ou numéro de téléphone.
  Future<bool> login({required String login, required String password}) async {
    _lastError = null;
    try {
      final result = await authService.login(login: login, password: password);
      await _onSignedIn(result.user, result.firebaseCustomToken);
      _sessionUnavailable = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _lastError = e.message;
      notifyListeners();
      return false;
    } catch (_) {
      _lastError = 'Connexion impossible. Réessayez.';
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
      await _chatAuthBridge.signInWithCustomToken(_lastCustomToken());
      notifyListeners();
    } catch (_) {
      // Silencieux : on garde l'état précédent plutôt que de vider l'écran
      // sur un simple hoquet réseau.
    }
  }

  Future<void> signOut() async {
    _autoSyncTimer?.cancel();
    _pushService.reset();
    TripLocationTracker.instance.stop();
    try {
      await authService.logout();
    } catch (_) {
      // Même si l'appel réseau échoue, on nettoie l'état local — l'usager
      // ne doit jamais rester bloqué connecté côté UI par une erreur serveur.
    }
    await _chatAuthBridge.signOut();
    _user = null;
    _sessionUnavailable = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    super.dispose();
  }
}
