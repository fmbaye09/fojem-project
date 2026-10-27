import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../features/publish_trip/stop_plan.dart';
import '../models/trip.dart';
import '../models/vehicle.dart';
import 'trip_display_cache.dart';

class TripRepository {
  final ApiClient _client;
  final TripDisplayCache _displayCache;

  TripRepository({ApiClient? client, TripDisplayCache? displayCache})
      : _client = client ?? ApiClient(),
        _displayCache = displayCache ?? TripDisplayCache();

  /// Publie un trajet et ses points de rendez-vous ([stops] : départ en
  /// premier, arrivée en dernier, avec heures et prix calculés).
  Future<Trip> create({
    required String vehicleId,
    required List<PlannedStop> stops,
    required int seatsTotal,
    required VehicleType vehicleType,
    String? notes,
  }) async {
    final first = stops.first;
    final last = stops.last;
    final body = await _client.post('/trips', data: {
      'vehicle_id': vehicleId,
      'departure_type': 'scheduled',
      'scheduled_at': first.scheduledAt.toUtc().toIso8601String(),
      'price_per_seat': last.priceFromOrigin,
      'seats_available': seatsTotal,
      'stops': [for (final s in stops) s.toApi()],
    });

    final json = body['trip'] as Map<String, dynamic>;
    final id = json['id'] as String;

    // Données que le backend ne stocke pas encore (places totales, type de
    // véhicule, notes) : conservées localement pour l'affichage.
    await _displayCache.save(
      id,
      departure: first.location.shortLabel,
      arrival: last.location.shortLabel,
      departureAddress: first.location.address,
      arrivalAddress: last.location.address,
      origin: first.location,
      destination: last.location,
      seatsTotal: seatsTotal,
      estimatedMinutes: last.scheduledAt.difference(first.scheduledAt).inMinutes,
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
