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
    required String seatId,
    required double price,
    bool hasHeavyLuggage = false,
    List<File> luggagePhotos = const [],
    double? pickupLat,
    double? pickupLng,
  }) async {
    final trip = await _tripRepository.fetch(tripId);
    final resolvedLat = pickupLat ?? trip?.origin.lat ?? 0;
    final resolvedLng = pickupLng ?? trip?.origin.lng ?? 0;

    dynamic requestData;
    if (hasHeavyLuggage && luggagePhotos.isNotEmpty) {
      final formDataMap = <String, dynamic>{
        'trip_id': tripId,
        'seat_count': 1,
        'pickup_lat': resolvedLat,
        'pickup_lng': resolvedLng,
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
        'seat_count': 1,
        'pickup_lat': resolvedLat,
        'pickup_lng': resolvedLng,
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

  Future<List<Booking>> fetchForPassenger(String? passengerId) async {
    try {
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
    } on ApiException {
      return [];
    }
  }

  Future<void> cancel(String bookingId) async {
    await _client.post('/bookings/$bookingId/cancel');
  }

  Future<Booking?> fetchActiveForTrip({
    required String tripId,
    required String passengerId,
  }) async {
    final bookings = await fetchForPassenger(passengerId);
    for (final b in bookings) {
      if (b.tripId == tripId &&
          (b.status == BookingStatus.pending || b.status == BookingStatus.confirmed)) {
        return b;
      }
    }
    return null;
  }
}
