import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/conversation.dart';

/// Chat temps réel (Phase 6) : conversations rattachées à un trajet ou une
/// demande de passager, messages en sous-collection, streamés via
/// `snapshots()`. L'envoi de notification push à la réception d'un message
/// (FCM) nécessite une Cloud Function côté serveur — voir `functions/` —
/// non exécutable depuis ce repository client.
class ChatRepository {
  final FirebaseFirestore? _injectedFirestore;
  FirebaseFirestore get _firestore => _injectedFirestore ?? FirebaseFirestore.instance;

  ChatRepository({FirebaseFirestore? firestore})
      : _injectedFirestore = firestore;

  CollectionReference<Map<String, dynamic>> get _conversations =>
      _firestore.collection('conversations');

  Future<void> _ensureAuth() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChatRepository Chauffeur] Fallback auth échoué: $e');
      }
    }
  }

  /// Retourne la conversation existante entre ces deux participants pour ce
  /// trajet/demande, ou en crée une nouvelle.
  Future<Conversation> findOrCreate({
    required String userIdA,
    required String userIdB,
    String? relatedTripId,
    String? relatedRequestId,
  }) async {
    await _ensureAuth();
    final participants = [userIdA, userIdB]..sort();
    var query = _conversations.where('participants', isEqualTo: participants);
    if (relatedTripId != null) {
      query = query.where('relatedTripId', isEqualTo: relatedTripId);
    } else if (relatedRequestId != null) {
      query = query.where('relatedRequestId', isEqualTo: relatedRequestId);
    }
    final existing = await query.limit(1).get();

    if (existing.docs.isNotEmpty) {
      return Conversation.fromMap(existing.docs.first.id, existing.docs.first.data());
    }

    final conversation = Conversation(
      id: '',
      participantIds: participants,
      relatedTripId: relatedTripId,
      relatedRequestId: relatedRequestId,
      lastMessageText: '',
      lastMessageAt: DateTime.now(),
    );
    final ref = await _conversations.add(conversation.toMap());
    return Conversation.fromMap(ref.id, conversation.toMap());
  }

  Stream<List<Conversation>> watchForUser(String userId) {
    return _conversations
        .where('participants', arrayContains: userId)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => Conversation.fromMap(d.id, d.data()))
          .toList();
      list.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
      return list;
    });
  }

  Stream<List<ChatMessage>> watchMessages(String conversationId) {
    return _conversations
        .doc(conversationId)
        .collection('messages')
        .orderBy('timestamp')
        .snapshots()
        .map((snap) => snap.docs.map((d) => ChatMessage.fromMap(d.id, d.data())).toList());
  }

  /// Marque comme lus les messages reçus par [userId] dans la conversation.
  Future<void> markRead({required String conversationId, required String userId}) async {
    final unread = await _conversations
        .doc(conversationId)
        .collection('messages')
        .where('read', isEqualTo: false)
        .get();
    final batch = _firestore.batch();
    for (final doc in unread.docs) {
      if (doc.data()['senderId'] != userId) batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  Future<void> sendMessage({
    required String conversationId,
    required String senderId,
    required String text,
  }) async {
    final conversationRef = _conversations.doc(conversationId);
    final message = ChatMessage(
      id: '',
      senderId: senderId,
      text: text,
      timestamp: DateTime.now(),
      read: false,
    );
    await conversationRef.collection('messages').add(message.toMap());
    await conversationRef.update({
      'lastMessageText': text,
      'lastMessageAt': message.timestamp.toIso8601String(),
      'lastSenderId': senderId,
    });
  }
}
