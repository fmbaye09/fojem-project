class AppNotification {
  final String id;
  final String userId;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> payload;
  final DateTime? readAt;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    required this.payload,
    this.readAt,
    required this.createdAt,
  });

  bool get isRead => readAt != null;

  factory AppNotification.fromApi(Map<String, dynamic> json) {
    final payload = (json['payload'] is Map<String, dynamic>)
        ? json['payload'] as Map<String, dynamic>
        : <String, dynamic>{};

    final title = (json['title'] as String?)?.trim();
    final body = (payload['body'] as String?) ??
        (payload['message'] as String?) ??
        '';

    return AppNotification(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'system',
      title: (title != null && title.isNotEmpty) ? title : _defaultTitleForType(json['type']?.toString()),
      body: body,
      payload: payload,
      readAt: json['read_at'] != null ? DateTime.tryParse(json['read_at'].toString()) : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  static String _defaultTitleForType(String? type) {
    switch (type) {
      case 'booking_new':
        return 'Nouvelle réservation';
      case 'booking_confirmed':
        return 'Réservation confirmée';
      case 'booking_rejected':
        return 'Réservation refusée';
      case 'booking_cancelled':
        return 'Réservation annulée';
      case 'booking_completed':
        return 'Trajet terminé';
      case 'document_status':
        return 'Statut des documents';
      case 'chat_message':
        return 'Nouveau message';
      default:
        return 'Notification';
    }
  }

  AppNotification copyWith({
    String? id,
    String? userId,
    String? type,
    String? title,
    String? body,
    Map<String, dynamic>? payload,
    DateTime? readAt,
    DateTime? createdAt,
  }) {
    return AppNotification(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      payload: payload ?? this.payload,
      readAt: readAt ?? this.readAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inSeconds < 60) return 'À l\'instant';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours}h';
    if (diff.inDays == 1) return 'Hier';
    if (diff.inDays < 7) return 'Il y a ${diff.inDays} jours';
    return '${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year}';
  }
}
