/// Page ouverte par une notification, touchée dans la barre système ou dans
/// la liste des notifications : une seule table pour les deux. Le type et
/// les identifiants viennent du backend (`NotificationService`) ; `null`
/// quand la notification n'a pas de page à elle.
///
/// - message → la conversation ;
/// - trajet terminé → la notation du chauffeur ;
/// - toute autre notification d'une réservation (confirmée, refusée,
///   annulée, trajet annulé, présence à bord, départ) → son billet, qui
///   montre où en est la réservation ;
/// - trajet sans réservation (trajet compatible trouvé) → sa fiche, pour
///   réserver.
String? notificationLocation(Map<String, dynamic> data) {
  String field(String key) => (data[key] ?? '').toString().trim();

  final conversationId = field('conversation_id');
  if (conversationId.isNotEmpty) {
    final name = field('sender_name').isEmpty ? 'Message' : field('sender_name');
    return Uri(
      path: '/chat/$conversationId',
      queryParameters: {'name': name, 'otherId': field('sender_id')},
    ).toString();
  }

  final tripId = field('trip_id');
  if (tripId.isEmpty) return null;
  if (field('type') == 'booking_completed') return '/rate/$tripId';
  if (field('booking_id').isNotEmpty) return '/trip/$tripId/tracking';
  return '/trip/$tripId';
}
