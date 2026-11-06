import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_passager/services/notification_routes.dart';

/// Données telles que le backend les envoie (`NotificationService::create`,
/// valeurs en texte dans FCM).
Map<String, dynamic> _booking(String type) => {
      'type': type,
      'booking_id': 'b1',
      'trip_id': 't1',
      'trip_label': 'Dakar → Thiès',
      'notification_id': 'n1',
    };

void main() {
  test('every booking notification opens its ticket', () {
    for (final type in ['booking_confirmed', 'booking_rejected', 'booking_cancelled', 'trip_cancelled']) {
      expect(notificationLocation(_booking(type)), '/trip/t1/tracking', reason: type);
    }
    // Présence validée à bord, trajet démarré : notifications « system ».
    expect(notificationLocation(_booking('system')), '/trip/t1/tracking');
  });

  test('a finished trip opens the rating', () {
    expect(notificationLocation(_booking('booking_completed')), '/rate/t1');
  });

  test('a compatible trip without booking opens the trip to book it', () {
    expect(
      notificationLocation({'type': 'system', 'trip_id': 't2', 'ride_request_id': 'r1', 'compatibility_score': '80'}),
      '/trip/t2',
    );
  });

  test('a chat message opens the conversation with its sender', () {
    final location = notificationLocation({
      'type': 'chat_message',
      'conversation_id': 'c1',
      'sender_id': 'u2',
      'sender_name': 'Awa Ndiaye',
      'message': 'Je suis au péage',
    })!;
    final uri = Uri.parse(location);
    expect(uri.path, '/chat/c1');
    expect(uri.queryParameters['name'], 'Awa Ndiaye');
    expect(uri.queryParameters['otherId'], 'u2');
  });

  test('a notification without a page opens nothing', () {
    expect(notificationLocation({'type': 'system', 'title': 'Bienvenue'}), isNull);
    expect(notificationLocation({'type': 'system', 'trip_id': ''}), isNull);
  });
}
