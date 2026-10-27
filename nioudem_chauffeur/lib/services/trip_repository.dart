import '../core/geo/geo_location.dart';
import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../models/trip.dart';
import '../models/vehicle.dart';
import 'trip_display_cache.dart';

class TripRepository {
  final ApiClient _client;
  final TripDisplayCache _displayCache;

  TripRepository({ApiClient? client, TripDisplayCache? displayCache})
      : _client = client ?? ApiClient(),
        _displayCache = displayCache ?? TripDisplayCache();

  Future<Trip> create({
    required String driverId,
    required String vehicleId,
    required String departure,
    required String arrival,
    required String departureAddress,
    required String arrivalAddress,
    required GeoLocation origin,
    required GeoLocation destination,
    required List<GeoLocation> waypoints,
    required DateTime departureTime,
    required Duration estimatedDuration,
    required int seatsTotal,
    required double pricePerSeat,
    required VehicleType vehicleType,
    String? notes,
  }) async {
    final body = await _client.post('/trips', data: {
      'vehicle_id': vehicleId,
      'origin_lat': origin.lat,
      'origin_lng': origin.lng,
      'destination_lat': destination.lat,
      'destination_lng': destination.lng,
      'origin_name': departure,
      'destination_name': arrival,
      'departure_type': 'scheduled',
      'scheduled_at': departureTime.toUtc().toIso8601String(),
      'price_per_seat': pricePerSeat,
      'seats_available': seatsTotal,
      if (waypoints.isNotEmpty)
        'waypoints': waypoints
            .map((w) => {
                  'name': w.address,
                  'lat': w.lat,
                  'lng': w.lng,
                })
            .toList(),
    });

    final json = body['trip'] as Map<String, dynamic>;
    final id = json['id'] as String;

    await _displayCache.save(
      id,
      departure: departure,
      arrival: arrival,
      departureAddress: departureAddress,
      arrivalAddress: arrivalAddress,
      origin: origin,
      destination: destination,
      seatsTotal: seatsTotal,
      estimatedMinutes: estimatedDuration.inMinutes,
      vehicleType: vehicleType,
      notes: notes,
    );

    return Trip.fromApiJson(json, cached: await _displayCache.read(id));
  }

  Future<Trip?> fetch(String tripId, {bool withDriver = true}) async {
    try {
      final body = await _client.get('/trips/$tripId');
      final json = body['trip'] as Map<String, dynamic>;
      return Trip.fromApiJson(json, cached: await _displayCache.read(tripId));
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<Trip>> fetchForDriver(String driverId) async {
    final body = await _client.get('/trips/mine');
    final rows = (body['data'] as List?) ?? const [];
    final trips = <Trip>[];
    for (final row in rows) {
      final json = row as Map<String, dynamic>;
      final id = json['id'] as String;
      trips.add(Trip.fromApiJson(json, cached: await _displayCache.read(id)));
    }
    return trips;
  }

  Future<void> updateStatus(String tripId, TripStatus status) async {
    if (status == TripStatus.cancelled) {
      await _client.post('/trips/$tripId/cancel');
    } else if (status == TripStatus.inProgress) {
      await _client.post('/trips/$tripId/start');
    } else if (status == TripStatus.completed) {
      await _client.post('/trips/$tripId/complete');
    } else {
      throw const ApiException(
        'Cette transition de statut n\'est pas prise en charge.',
      );
    }
  }

  /// Envoie la position GPS actuelle du chauffeur pendant le trajet en cours.
  Future<void> updateLocation(
    String tripId, {
    required double lat,
    required double lng,
    double? heading,
  }) async {
    await _client.post('/trips/$tripId/location', data: {
      'lat': lat,
      'lng': lng,
      if (heading != null) 'heading': heading,
    });
  }
}
