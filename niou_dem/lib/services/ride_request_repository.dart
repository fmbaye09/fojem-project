import '../core/geo/geo_location.dart';
import '../core/network/api_client.dart';
import '../models/ride_request.dart';
import '../models/trip.dart';
import 'driver_repository.dart';

class MatchedTripScore {
  final Trip trip;
  final double compatibilityScore;
  final int detourDistanceM;
  final int detourDurationS;

  const MatchedTripScore({
    required this.trip,
    required this.compatibilityScore,
    required this.detourDistanceM,
    required this.detourDurationS,
  });

  factory MatchedTripScore.fromApi(Map<String, dynamic> map) {
    final tripJson = map['trip'] as Map<String, dynamic>? ?? {};
    final trip = Trip.fromApi(tripJson);
    DriverCache.instance.put(trip.driver);
    return MatchedTripScore(
      trip: trip,
      compatibilityScore: double.tryParse('${map['compatibility_score'] ?? 0}') ?? 0,
      detourDistanceM: int.tryParse('${map['detour_distance_m'] ?? 0}') ?? 0,
      detourDurationS: int.tryParse('${map['detour_duration_s'] ?? 0}') ?? 0,
    );
  }
}

/// Demandes de trajet passager via l'API Laravel (`/api/ride-requests/*`).
class RideRequestRepository {
  final ApiClient _client;

  RideRequestRepository({ApiClient? client}) : _client = client ?? ApiClient.instance;

  Future<RideRequest> create({
    required String passengerId,
    required String passengerName,
    required GeoLocation origin,
    required GeoLocation destination,
    required DateTime desiredDateTime,
    bool womenOnly = false,
  }) async {
    final response = await _client.post('/ride-requests', data: {
      'origin_lat': origin.lat,
      'origin_lng': origin.lng,
      'destination_lat': destination.lat,
      'destination_lng': destination.lng,
      'requested_at': desiredDateTime.toUtc().toIso8601String(),
      if (origin.address.isNotEmpty) 'origin_name': origin.address,
      if (destination.address.isNotEmpty) 'destination_name': destination.address,
      if (womenOnly) 'women_only': true,
    });
    final json = response['ride_request'] as Map<String, dynamic>;
    return RideRequest.fromApi(
      json,
      origin: origin,
      destination: destination,
      passengerName: passengerName,
    );
  }

  Future<List<RideRequest>> fetchForPassenger(String passengerId) async {
    final response = await _client.get('/ride-requests/mine');
    final data = (response['data'] as List?) ?? [];
    return data.map((r) => RideRequest.fromApi(r as Map<String, dynamic>)).toList();
  }

  Future<List<MatchedTripScore>> fetchMatches(String requestId) async {
    final response = await _client.get('/ride-requests/$requestId/matches');
    final matchesRaw = (response['matches'] as List?) ?? [];
    return matchesRaw
        .whereType<Map<String, dynamic>>()
        .map(MatchedTripScore.fromApi)
        .toList();
  }

  Future<void> cancel(String requestId) async {
    await _client.post('/ride-requests/$requestId/cancel');
  }
}
