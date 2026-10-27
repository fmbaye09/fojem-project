import 'dart:async';
import 'package:flutter/material.dart';
import '../core/network/api_exception.dart';
import '../models/app_user.dart';
import '../services/auth/api_auth_service.dart';
import '../services/auth/auth_service.dart';
import '../services/push_notification_service.dart';

/// Session de l'app, branchée sur le backend Laravel via [ApiAuthService].
///
/// Le token Sanctum est persisté par [ApiAuthService]/`SecureTokenStorage` —
/// ce provider ne fait que refléter l'état d'auth courant pour l'UI et
/// exposer les actions register/login/logout.
class AppProvider extends ChangeNotifier {
  final AuthService authService;
  final PushNotificationService _pushService;

  AppUser? _user;
  bool _isLoading = true;
  StreamSubscription<AppUser?>? _authSub;

  AppProvider({
    AuthService? authService,
    PushNotificationService? pushService,
  })  : authService = authService ?? ApiAuthService(),
        _pushService = pushService ?? PushNotificationService() {
    _authSub = this.authService.authStateChanges().listen(_onAuthChanged);
    _restoreSession();
  }

  Timer? _autoSyncTimer;

  bool _sessionUnavailable = false;
  String? _sessionError;

  AppUser? get user => _user;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _user != null;

  /// Un token est stocké mais le serveur n'a pas pu être joint au démarrage.
  /// La session n'est pas perdue : l'accueil propose [retrySession].
  bool get sessionUnavailable => _sessionUnavailable;
  String? get sessionError => _sessionError;

  Future<void> _restoreSession() async {
    final service = authService;
    if (service is ApiAuthService) {
      try {
        await service.restoreSession();
      } on ApiException catch (e) {
        // 401 : déjà traité par ApiAuthService (déconnexion propre).
        if (e.statusCode != 401) _markSessionUnavailable(e.message);
      } catch (_) {
        _markSessionUnavailable(null);
      }
    } else {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _markSessionUnavailable(String? message) {
    _sessionUnavailable = true;
    _sessionError = message;
    _isLoading = false;
    notifyListeners();
  }

  /// Relance la restauration de session après un échec réseau au démarrage.
  Future<void> retrySession() async {
    _sessionUnavailable = false;
    _sessionError = null;
    _isLoading = true;
    notifyListeners();
    await _restoreSession();
  }

  void _onAuthChanged(AppUser? user) {
    _user = user;
    _isLoading = false;
    _sessionUnavailable = false;
    notifyListeners();
    _autoSyncTimer?.cancel();
    if (user != null) {
      _pushService.initialize(user.id);
      _autoSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (_user != null) refreshUser();
      });
    } else {
      // Déconnexion (y compris sur 401) : on arrête le poller de
      // notifications, qui sinon tournerait en boucle sur des 401.
      _pushService.reset();
    }
  }

  Future<void> register({
    required String fullName,
    required String email,
    required String password,
    required String phoneNumber,
    required String gender,
  }) async {
    await authService.register(
      fullName: fullName,
      email: email,
      password: password,
      phoneNumber: phoneNumber,
      gender: gender,
    );
  }

  Future<void> login({
    String? email,
    String? phoneNumber,
    required String password,
  }) async {
    await authService.login(
      email: email,
      phoneNumber: phoneNumber,
      password: password,
      clientType: 'passenger',
    );
  }

  Future<void> refreshUser() async {
    final user = await authService.refreshCurrentUser();
    if (user != null) {
      _user = user;
      notifyListeners();
    }
  }

  void updateUser(AppUser user) {
    _user = user;
    notifyListeners();
  }

  Future<void> signOut() async {
    _pushService.reset();
    await authService.logout();
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}
