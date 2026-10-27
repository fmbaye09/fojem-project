class ChatMessage {
  final String id;
  final String senderId;
  final String text;
  final DateTime timestamp;
  final bool read;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.timestamp,
    required this.read,
  });

  factory ChatMessage.fromMap(String id, Map<String, dynamic> map) {
    return ChatMessage(
      id: id,
      senderId: map['senderId'] as String? ?? '',
      text: map['text'] as String? ?? '',
      timestamp: DateTime.tryParse(map['timestamp'] as String? ?? '') ?? DateTime.now(),
      read: map['read'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'read': read,
    };
  }
}

class Conversation {
  final String id;
  final List<String> participantIds;
  final String? relatedTripId;
  final String? relatedRequestId;
  final String lastMessageText;
  final DateTime lastMessageAt;

  /// Auteur du dernier message (pour afficher "Vous : …" dans la liste) et
  /// nombre de messages reçus non lus.
  final String? lastSenderId;
  final int unreadCount;

  const Conversation({
    required this.id,
    required this.participantIds,
    this.relatedTripId,
    this.relatedRequestId,
    required this.lastMessageText,
    required this.lastMessageAt,
    this.lastSenderId,
    this.unreadCount = 0,
  });

  String otherParticipant(String currentUserId) =>
      participantIds.firstWhere((id) => id != currentUserId, orElse: () => '');

  factory Conversation.fromMap(String id, Map<String, dynamic> map) {
    return Conversation(
      id: id,
      participantIds: List<String>.from(map['participants'] as List? ?? []),
      relatedTripId: map['relatedTripId'] as String?,
      relatedRequestId: map['relatedRequestId'] as String?,
      lastMessageText: map['lastMessageText'] as String? ?? '',
      lastMessageAt: DateTime.tryParse(map['lastMessageAt'] as String? ?? '') ?? DateTime.now(),
      lastSenderId: map['lastSenderId'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'participants': participantIds,
      'relatedTripId': relatedTripId,
      'relatedRequestId': relatedRequestId,
      'lastMessageText': lastMessageText,
      'lastMessageAt': lastMessageAt.toIso8601String(),
      'lastSenderId': lastSenderId,
    };
  }
}
