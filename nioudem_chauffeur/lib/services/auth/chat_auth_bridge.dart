import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Pont Firebase Auth pour le chat : le chat reste entièrement sur
/// Firestore, mais Firestore exige une session Firebase Auth valide pour
/// appliquer ses règles de sécurité (`signedIn()`). Le backend Laravel émet
/// un `firebase_custom_token` à chaque register/login réussi — on l'échange
/// ici contre une session Firebase.
///
/// Best-effort : si le token est absent (pas encore déployé côté backend)
/// ou si l'échange échoue, on continue sans bloquer le reste de l'app — seul
/// le chat sera indisponible tant que la session Firebase n'est pas établie.
class ChatAuthBridge {
  final FirebaseAuth _auth;

  ChatAuthBridge({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  Future<void> signInWithCustomToken(String? token) async {
    if (token != null && token.isNotEmpty) {
      try {
        await _auth.signInWithCustomToken(token);
        if (kDebugMode) {
          debugPrint('[ChatAuthBridge] Connecté à Firebase Auth via custom token (uid: ${_auth.currentUser?.uid})');
        }
        return;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[ChatAuthBridge] Échec de la connexion Firebase (chat) : $e');
        }
      }
    }

    if (_auth.currentUser == null) {
      try {
        await _auth.signInAnonymously();
        if (kDebugMode) {
          debugPrint('[ChatAuthBridge] Connecté à Firebase Auth anonymement (fallback)');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[ChatAuthBridge] Échec signInAnonymously : $e');
        }
      }
    }
  }

  /// Comme [signInWithCustomToken], mais seulement sans session Firebase :
  /// le SDK renouvelle lui-même une session ouverte. Appelé à chaque
  /// rafraîchissement du profil, qui ne doit pas rouvrir une session à
  /// chaque fois (un aller-retour vers Google toutes les 12 à 30 s).
  Future<void> ensureSignedIn(String? token) async {
    if (_auth.currentUser != null) return;
    await signInWithCustomToken(token);
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // Pas de session Firebase active — rien à faire.
    }
  }
}
