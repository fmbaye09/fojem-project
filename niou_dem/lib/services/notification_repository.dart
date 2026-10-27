import '../core/network/api_client.dart';
import '../models/app_notification.dart';

class NotificationRepository {
  final ApiClient _client;

  NotificationRepository({ApiClient? client})
      : _client = client ?? ApiClient.instance;

  Future<List<AppNotification>> fetchNotifications({
    bool unreadOnly = false,
    int perPage = 30,
  }) async {
    try {
      final response = await _client.get('/notifications', query: {
        if (unreadOnly) 'unread_only': true,
        'per_page': perPage,
      });

      final dynamic rawData = response['data'];
      if (rawData is List) {
        return rawData
            .whereType<Map<String, dynamic>>()
            .map((json) => AppNotification.fromApi(json))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<int> getUnreadCount() async {
    try {
      final response = await _client.get('/notifications/unread-count');
      return (response['unread_count'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<bool> markAsRead(String id) async {
    try {
      await _client.post('/notifications/$id/read');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> markAllAsRead() async {
    try {
      await _client.post('/notifications/mark-all-read');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> registerFcmToken(String token) async {
    try {
      await _client.post('/fcm-token', data: {'fcm_token': token});
    } catch (_) {}
  }

  Future<void> sendChatNotification({
    required String recipientId,
    required String message,
    String? conversationId,
  }) async {
    try {
      await _client.post('/notifications/chat-message', data: {
        'recipient_id': recipientId,
        'message': message,
        if (conversationId != null) 'conversation_id': conversationId,
      });
    } catch (_) {}
  }
}
