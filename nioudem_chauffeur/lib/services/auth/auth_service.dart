import '../../models/app_user.dart';

/// Résultat d'un register/login réussi : l'utilisateur, et le jeton Firebase
/// personnalisé (peut être `null`) qui permet de brancher Firebase Auth pour
/// le chat sans dupliquer la logique d'inscription/connexion.
class AuthResult {
  final AppUser user;
  final String token;
  final String? firebaseCustomToken;

  const AuthResult({
    required this.user,
    required this.token,
    required this.firebaseCustomToken,
  });
}

/// Abstraction de l'authentification email/mot de passe contre le backend
/// Laravel (Sanctum). Remplace l'ancien flow téléphone/OTP Firebase — le
/// backend ne connaît que l'email/mot de passe (voir
/// `fojem_backend/app/Http/Controllers/Api/AuthController.php`).
abstract class AuthService {
  Future<AuthResult> register({
    required String fullName,
    required String email,
    required String password,
    required String phoneNumber,
    required String gender,
  });

  /// [login] : adresse e-mail ou numéro de téléphone (format +221…).
  Future<AuthResult> login({required String login, required String password});

  /// Crée le profil `drivers` (statut `pending`) associé au compte courant.
  /// Appelé automatiquement juste après un register réussi — cette app est
  /// réservée aux chauffeurs.
  Future<AppUser> becomeDriver();

  /// Profil courant (+ driver, wallet) — utilisé au démarrage de l'app pour
  /// restaurer la session à partir du token stocké.
  Future<AppUser> me();

  Future<void> logout();
}
