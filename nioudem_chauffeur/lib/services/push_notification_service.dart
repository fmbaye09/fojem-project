import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../core/events/data_refresh.dart';
import 'notification_repository.dart';

/// Handler de messages FCM en arrière-plan (doit être une fonction top-level).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) {
    debugPrint('[FCM Background] ${message.messageId}: ${message.notification?.title}');
  }
}

/// Service complet de notifications push et système pour l'application chauffeur :
/// - Demande de permission système (Android 13+ et iOS)
/// - Enregistrement du token FCM sur le backend
/// - Réception et affichage des notifications en foreground via flutter_local_notifications
/// - Poller de synchronisation in-app pour garantir que chaque réservation, message
///   ou validation de document déclenche une notification système dans la barre d'état
/// - Gestion du tap sur notification (redirection automatique)
class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._();
  factory PushNotificationService() => _instance;
  PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final NotificationRepository _repository = NotificationRepository();

  bool _initialized = false;
  bool _initialMessageHandled = false;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _pollerTimer;
  final Set<String> _notifiedIds = {};

  /// Canal Android pour les notifications FOJEM Chauffeur
  static const _androidChannel = AndroidNotificationChannel(
    'fojem_chauffeur_notifications',
    'Notifications FOJEM Chauffeur',
    description: 'Notifications de réservation, messagerie et statut chauffeur',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  /// Callback appelé quand l'utilisateur tape sur une notification.
  void Function(Map<String, dynamic> data)? onNotificationTap;

  /// Initialise le service pour l'utilisateur connecté.
  Future<void> initialize(String userId) async {
    if (_initialized) return;
    _initialized = true;

    // 1. Configurer flutter_local_notifications et demander permissions
    await _setupLocalNotifications();

    // 2. Permission FCM
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: false,
        provisional: false,
      );

      if (kDebugMode) {
        debugPrint('[Push Chauffeur] Status permission: ${settings.authorizationStatus}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Push Chauffeur] Erreur permission: $e');
    }

    // 3. Récupérer et enregistrer le token FCM
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        if (kDebugMode) debugPrint('[Push Chauffeur] Token FCM: $token');
        await _repository.registerFcmToken(token);
      }

      _subscriptions.add(_messaging.onTokenRefresh.listen((newToken) {
        if (kDebugMode) debugPrint('[Push Chauffeur] Token FCM renouvelé');
        _repository.registerFcmToken(newToken);
      }));
    } catch (e) {
      if (kDebugMode) debugPrint('[Push Chauffeur] Erreur token FCM: $e');
    }

    // 4. Écouter les messages en foreground
    _subscriptions.add(FirebaseMessaging.onMessage.listen(_handleForegroundMessage));

    // 5. Écouter les taps sur notifications
    _subscriptions.add(FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap));

    // 6. Vérifier si l'app a été lancée par un tap sur notif — une seule fois
    // par lancement, sinon une reconnexion rejouerait cette notification.
    final initialMessage =
        _initialMessageHandled ? null : await _messaging.getInitialMessage();
    _initialMessageHandled = true;
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }

    // 7. Démarrer le poller in-app pour garantir l'affichage des notifications système
    _startNotificationPoller();
  }

  Future<void> _setupLocalNotifications() async {
    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(_androidChannel);
    try {
      await androidPlugin?.requestNotificationsPermission();
    } catch (_) {}

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: (response) {
        DataRefresh.instance.notify();
        if (response.payload != null && response.payload!.isNotEmpty) {
          try {
            final data = jsonDecode(response.payload!) as Map<String, dynamic>;
            onNotificationTap?.call(data);
          } catch (_) {}
        }
      },
    );
  }

  /// Affiche une notification système dans la barre d'état Android.
  Future<void> showSystemNotification({
    required int id,
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) async {
    try {
      await _localNotifications.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannel.id,
            _androidChannel.name,
            channelDescription: _androidChannel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            playSound: true,
            enableVibration: true,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: payload != null ? jsonEncode(payload) : null,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Push Chauffeur] Erreur affichage notification locale: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    // Une réservation, un message… a changé : les écrans ouverts se mettent à jour.
    DataRefresh.instance.notify();
    final notification = message.notification;
    if (notification == null) return;

    if (kDebugMode) {
      debugPrint('[Push Chauffeur] Foreground FCM: ${notification.title} — ${notification.body}');
    }

    showSystemNotification(
      id: notification.hashCode,
      title: notification.title ?? 'FOJEM Chauffeur',
      body: notification.body ?? '',
      payload: message.data,
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    DataRefresh.instance.notify();
    if (kDebugMode) {
      debugPrint('[Push Chauffeur] Tap notif FCM: ${message.data}');
    }
    onNotificationTap?.call(message.data);
  }

  void _startNotificationPoller() {
    _pollerTimer?.cancel();
    _checkNewNotifications(firstRun: true);
    _pollerTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkNewNotifications(firstRun: false);
    });
  }

  Future<void> _checkNewNotifications({required bool firstRun}) async {
    try {
      final list = await _repository.fetchNotifications(unreadOnly: true, perPage: 15);
      if (firstRun) {
        for (final notif in list) {
          _notifiedIds.add(notif.id);
        }
        return;
      }

      for (final notif in list) {
        if (!_notifiedIds.contains(notif.id)) {
          DataRefresh.instance.notify();
          _notifiedIds.add(notif.id);
          final payload = Map<String, dynamic>.from(notif.payload);
          payload['type'] = notif.type;
          payload['notification_id'] = notif.id;
          payload['title'] = notif.title;
          payload['body'] = notif.body;
          await showSystemNotification(
            id: notif.id.hashCode,
            title: notif.title,
            body: notif.body,
            payload: payload,
          );
        }
      }
    } catch (_) {}
  }

  void reset() {
    _pollerTimer?.cancel();
    _pollerTimer = null;
    _notifiedIds.clear();
    _initialized = false;
    // Désabonne les flux FCM pour qu'un nouveau login ne les double pas.
    // `onNotificationTap` est conservé : il est posé une seule fois au
    // lancement de l'app et doit survivre à une déconnexion/reconnexion.
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }
}
