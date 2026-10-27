import 'dart:async';
import 'package:flutter/material.dart';
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

  AppUser? get user => _user;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _user != null;

  Future<void> _restoreSession() async {
    final service = authService;
    if (service is ApiAuthService) {
      await service.restoreSession();
    } else {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _onAuthChanged(AppUser? user) {
    _user = user;
    _isLoading = false;
    notifyListeners();
    _autoSyncTimer?.cancel();
    if (user != null) {
      _pushService.initialize(user.id);
      _autoSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (_user != null) refreshUser();
      });
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
