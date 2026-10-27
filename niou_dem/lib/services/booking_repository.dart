import 'dart:io';
import 'package:dio/dio.dart';
import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../models/booking.dart';
import '../models/trip.dart';
import 'trip_repository.dart';

/// Réservations via l'API Laravel (`/api/bookings/*`).
class BookingRepository {
  final ApiClient _client;
  final TripRepository _tripRepository;

  BookingRepository({ApiClient? client, TripRepository? tripRepository})
      : _client = client ?? ApiClient.instance,
        _tripRepository = tripRepository ?? TripRepository();

  /// Crée une demande de réservation (`POST /bookings`, statut initial
  /// `pending_driver`). Supporte les bagages lourds, photos jointes et point de ramassage précis.
  Future<Booking> requestBooking({
    required String tripId,
    required String passengerId,
    required String passengerName,
    required String passengerPhone,
    required List<String> seatIds,
    bool hasHeavyLuggage = false,
    List<File> luggagePhotos = const [],
    // Points de rendez-vous du chauffeur où le passager monte et descend ;
    // sans eux, le backend réserve le trajet complet.
    String? boardingStopId,
    String? alightingStopId,
  }) async {
    final trip = await _tripRepository.fetch(tripId);
    final stops = <String, dynamic>{
      if (boardingStopId != null) 'boarding_stop_id': boardingStopId,
      if (alightingStopId != null) 'alighting_stop_id': alightingStopId,
    };

    dynamic requestData;
    if (hasHeavyLuggage && luggagePhotos.isNotEmpty) {
      final formDataMap = <String, dynamic>{
        'trip_id': tripId,
        'seat_numbers[]': seatIds,
        ...stops,
        'has_heavy_luggage': 1,
      };

      final filesList = <MultipartFile>[];
      for (final file in luggagePhotos) {
        final filename = file.path.split(Platform.pathSeparator).last;
        filesList.add(await MultipartFile.fromFile(file.path, filename: filename));
      }
      formDataMap['luggage_photos[]'] = filesList;
      requestData = FormData.fromMap(formDataMap);
    } else {
      requestData = {
        'trip_id': tripId,
        'seat_numbers': seatIds,
        ...stops,
        'has_heavy_luggage': hasHeavyLuggage ? 1 : 0,
      };
    }

    final response = await _client.post('/bookings', data: requestData);
    final bookingJson = response['booking'] as Map<String, dynamic>;
    return Booking.fromApi(bookingJson, trip: trip);
  }

  Future<Booking?> fetch(String bookingId) async {
    try {
      final response = await _client.get('/bookings/$bookingId');
      final bookingJson = response['booking'] as Map<String, dynamic>?;
      if (bookingJson == null) return null;
      final trip = await _tripRepository.fetch(bookingJson['trip_id'] as String? ?? '');
      return Booking.fromApi(bookingJson, trip: trip);
    } on ApiException {
      return null;
    }
  }

  /// Réservations du passager connecté. Lève une [ApiException] en cas
  /// d'erreur réseau/serveur, pour que l'écran puisse afficher une erreur
  /// au lieu d'une liste vide trompeuse.
  Future<List<Booking>> fetchForPassenger(String? passengerId) async {
    final response = await _client.get('/bookings/mine');
    final data = (response['data'] as List?) ?? [];
    final result = <Booking>[];
    for (final item in data) {
      final map = item as Map<String, dynamic>;
      Trip? trip;
      if (map['trip'] is Map<String, dynamic>) {
        trip = Trip.fromApi(map['trip'] as Map<String, dynamic>);
      } else {
        try {
          trip = await _tripRepository.fetch(map['trip_id'] as String? ?? '');
        } catch (_) {}
      }
      result.add(Booking.fromApi(map, trip: trip));
    }
    result.sort((a, b) => b.bookedAt.compareTo(a.bookedAt));
    return result;
  }

  Future<void> cancel(String bookingId) async {
    await _client.post('/bookings/$bookingId/cancel');
  }

  Future<Booking?> fetchActiveForTrip({
    required String tripId,
    required String passengerId,
  }) async {
    // Complément d'affichage (bouton « déjà réservé ») : une erreur réseau
    // ne doit pas empêcher l'écran du trajet de s'afficher.
    final List<Booking> bookings;
    try {
      bookings = await fetchForPassenger(passengerId);
    } on ApiException {
      return null;
    }
    for (final b in bookings) {
      if (b.tripId == tripId &&
          (b.status == BookingStatus.pending || b.status == BookingStatus.confirmed)) {
        return b;
      }
    }
    return null;
  }
}
