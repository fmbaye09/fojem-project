import '../../models/app_user.dart';

/// Code de connexion envoyé : canal utilisé et délai avant de pouvoir en
/// redemander un.
class CodeSent {
  final String channel; // whatsapp | sms
  final int resendIn; // secondes

  /// Le code lui-même, renvoyé seulement par un serveur de développement
  /// (aucun envoi WhatsApp ni SMS en local).
  final String? devCode;

  const CodeSent({required this.channel, required this.resendIn, this.devCode});
}

/// Résultat d'un code vérifié : le client est connecté ([user]), ou c'est
/// un nouveau client qui doit encore donner son nom ([signupToken]).
class CodeCheck {
  final AppUser? user;
  final String? signupToken;

  const CodeCheck.signedIn(AppUser this.user) : signupToken = null;
  const CodeCheck.newCustomer(String this.signupToken) : user = null;

  bool get isNewCustomer => signupToken != null;
}

/// Authentification des clients contre le backend Laravel FOJËM (Sanctum) :
/// numéro de téléphone + code reçu par WhatsApp ou SMS, sans mot de passe.
/// Firebase Auth ne sert que de pont vers Firestore pour le chat (voir
/// [ApiAuthService]).
abstract class AuthService {
  /// Émet l'utilisateur connecté (null si déconnecté) — recalculé à partir
  /// du token stocké au démarrage, puis à chaque connexion/déconnexion.
  Stream<AppUser?> authStateChanges();

  AppUser? get currentUser;

  /// Envoie un code à 6 chiffres au numéro (+221…), par WhatsApp ou SMS.
  Future<CodeSent> sendCode({required String phoneNumber, String channel = 'whatsapp'});

  /// Vérifie le code : connecte un client existant, ou renvoie le jeton qui
  /// permet à un nouveau client de créer son compte.
  Future<CodeCheck> verifyCode({required String phoneNumber, required String code});

  /// Crée le compte d'un nouveau client dont le numéro vient d'être vérifié.
  Future<AppUser> registerWithCode({
    required String signupToken,
    required String firstName,
    required String lastName,
  });

  Future<void> logout();

  /// Recharge le profil courant depuis le serveur (GET /auth/me).
  Future<AppUser?> refreshCurrentUser();
}
