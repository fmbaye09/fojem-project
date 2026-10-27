import '../../models/app_user.dart';

/// Abstraction de l'authentification email/mot de passe contre le backend
/// Laravel FOJËM (Sanctum). Remplace l'ancienne auth téléphone/OTP Firebase
/// — FOJËM n'utilise plus Firebase Auth pour la session principale, seulement
/// comme pont vers Firestore pour le chat (voir [ApiAuthService]).
abstract class AuthService {
  /// Émet l'utilisateur connecté (null si déconnecté) — recalculé à partir
  /// du token stocké au démarrage, puis à chaque login/logout.
  Stream<AppUser?> authStateChanges();

  AppUser? get currentUser;

  Future<AppUser> register({
    required String fullName,
    required String email,
    required String password,
    required String phoneNumber,
    required String gender,
  });

  Future<AppUser> login({
    String? email,
    String? phoneNumber,
    required String password,
    String clientType = 'passenger',
  });

  Future<void> logout();

  /// Recharge le profil courant depuis le serveur (GET /auth/me).
  Future<AppUser?> refreshCurrentUser();
}
