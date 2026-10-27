import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'notification_repository.dart';

/// Service FCM pour les notifications push et in-app.
class NotificationService {
  final FirebaseMessaging? _injectedMessaging;
  final NotificationRepository _repository;
  FirebaseMessaging get _messaging => _injectedMessaging ?? FirebaseMessaging.instance;

  NotificationService({
    FirebaseMessaging? messaging,
    NotificationRepository? repository,
  })  : _injectedMessaging = messaging,
        _repository = repository ?? NotificationRepository();

  Future<void> initForUser(String userId) async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        final token = await _messaging.getToken();
        if (token != null) {
          if (kDebugMode) {
            debugPrint('[NotificationService] Token FCM obtenu : $token');
          }
          await _repository.registerFcmToken(token);
        }

        // Écouter le renouvellement éventuel du token
        _messaging.onTokenRefresh.listen((newToken) {
          _repository.registerFcmToken(newToken);
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[NotificationService] Échec init FCM : $e');
    }
  }
}
