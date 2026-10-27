import '../core/network/api_client.dart';
import '../models/booking.dart';

/// Réservations — contre l'API Laravel (`/api/bookings/*` +
/// `/api/trips/{id}/bookings`).
///
/// Le backend expose désormais les réservations reçues par un chauffeur,
/// par trajet (`GET /trips/{id}/bookings?status=`, réservé au chauffeur
/// propriétaire du trajet — 403 sinon) ou globalement, tous trajets
/// confondus (`GET /bookings/received?status=`, nécessite un profil
/// `drivers`). Voir `fojem_backend/README.md`, section "Bookings".
class BookingRepository {
  final ApiClient _client;

  BookingRepository({ApiClient? client}) : _client = client ?? ApiClient();

  Future<List<Booking>> fetchForTrip(String tripId, {String? status}) async {
    final body = await _client.get(
      '/trips/$tripId/bookings',
      query: status != null ? {'status': status} : null,
    );
    return _parseList(body);
  }

  Future<List<Booking>> fetchForDriver(String driverId, {String? status}) async {
    final body = await _client.get(
      '/bookings/received',
      query: status != null ? {'status': status} : null,
    );
    return _parseList(body);
  }

  Future<Booking> fetchOne(String bookingId) async {
    final body = await _client.get('/bookings/$bookingId');
    return Booking.fromApiJson(body['booking'] as Map<String, dynamic>);
  }

  List<Booking> _parseList(Map<String, dynamic> body) {
    final rows = (body['data'] as List?) ?? const [];
    return rows
        .map((row) => Booking.fromApiJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<Booking> accept(String bookingId) async {
    final body = await _client.post('/bookings/$bookingId/accept');
    return Booking.fromApiJson(body['booking'] as Map<String, dynamic>);
  }

  Future<Booking> refuse(String bookingId) async {
    final body = await _client.post('/bookings/$bookingId/reject');
    return Booking.fromApiJson(body['booking'] as Map<String, dynamic>);
  }

  Future<Booking> cancel(String bookingId) async {
    final body = await _client.post('/bookings/$bookingId/cancel');
    return Booking.fromApiJson(body['booking'] as Map<String, dynamic>);
  }

  Future<Booking> complete(String bookingId) async {
    final body = await _client.post('/bookings/$bookingId/complete');
    return Booking.fromApiJson(body['booking'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> boardPassenger({
    required String tripId,
    required String code,
  }) async {
    return await _client.post(
      '/trips/$tripId/board-passenger',
      data: {'code': code},
    );
  }

  Future<Booking> boardBooking(String bookingId) async {
    final body = await _client.post('/bookings/$bookingId/board');
    return Booking.fromApiJson(body['booking'] as Map<String, dynamic>);
  }
}
