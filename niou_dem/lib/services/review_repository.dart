import '../core/network/api_client.dart';
import 'booking_repository.dart';

/// Avis via l'API Laravel (`POST /reviews`).
///
/// Le backend note un **booking** `completed` (avec 4 sous-notes :
/// ponctualité, conduite, communication, sécurité), pas un trajet avec une
/// note unique. L'écran (`RatingScreen`) ne collecte qu'une note globale sur
/// 5 — on l'applique aux 4 critères pour rester fidèle à l'UI existante
/// plutôt que de réécrire l'écran de notation. [tripId] sert à retrouver la
/// réservation correspondante du passager courant (le backend n'a pas
/// d'endpoint `POST /trips/{id}/review`, seulement `POST /reviews` avec un
/// `booking_id`).
class ReviewRepository {
  final ApiClient _client;
  final BookingRepository _bookingRepository;

  ReviewRepository({ApiClient? client, BookingRepository? bookingRepository})
      : _client = client ?? ApiClient.instance,
        _bookingRepository = bookingRepository ?? BookingRepository();

  Future<void> submitReview({
    required String tripId,
    required String driverId,
    required String authorId,
    required String authorName,
    required double rating,
    required String comment,
  }) async {
    final bookings = await _bookingRepository.fetchForPassenger(authorId);
    final matching = bookings.where((b) => b.tripId == tripId);
    final booking = matching.isEmpty ? null : matching.first;
    if (booking == null) {
      throw StateError('Aucune réservation terminée trouvée pour ce trajet.');
    }

    final rounded = rating.round().clamp(1, 5);
    await _client.post('/reviews', data: {
      'booking_id': booking.id,
      'punctuality_rating': rounded,
      'driving_rating': rounded,
      'communication_rating': rounded,
      'safety_rating': rounded,
      if (comment.isNotEmpty) 'comment': comment,
    });
  }
}
