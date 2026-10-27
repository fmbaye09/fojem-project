import 'package:firebase_messaging/firebase_messaging.dart';
import 'user_repository.dart';

/// Mise en place minimale de FCM : permission + récupération du token,
/// sauvegardé sur le doc utilisateur. L'envoi effectif de notifications
/// (nouveau message, demande de réservation) est hors scope ici — il
/// nécessite une Cloud Function côté serveur, ajoutée avec les phases
/// Chat/Booking.
class NotificationService {
  final FirebaseMessaging? _injectedMessaging;
  FirebaseMessaging get _messaging => _injectedMessaging ?? FirebaseMessaging.instance;
  final UserRepository _userRepository;

  NotificationService({
    FirebaseMessaging? messaging,
    UserRepository? userRepository,
  })  : _injectedMessaging = messaging,
        _userRepository = userRepository ?? UserRepository();

  Future<void> initForUser(String userId) async {
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final token = await _messaging.getToken();
    if (token != null) {
      await _userRepository.updateFcmToken(userId, token);
    }

    _messaging.onTokenRefresh.listen((newToken) {
      _userRepository.updateFcmToken(userId, newToken);
    });
  }
}
