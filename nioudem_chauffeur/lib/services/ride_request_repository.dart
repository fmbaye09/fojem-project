import '../core/network/api_client.dart';
import '../models/ride_request.dart';

/// Demandes de passagers ("Trouve-moi quelqu'un") côté app Chauffeur — lues
/// via `GET /trips/{id}/nearby-ride-requests`, qui fait le matching
/// géospatial (PostGIS `ST_DWithin`) côté serveur, remplaçant l'ancien
/// calcul Haversine local sur toutes les demandes ouvertes.
class RideRequestRepository {
  final ApiClient _client;

  RideRequestRepository({ApiClient? client}) : _client = client ?? ApiClient();

  /// Demandes ouvertes à proximité de l'origine du trajet [tripId]
  /// (rayon par défaut ~15km côté serveur).
  Future<List<RideRequest>> fetchNearTrip(String tripId, {int? radiusM}) async {
    final body = await _client.get(
      '/trips/$tripId/nearby-ride-requests',
      query: radiusM != null ? {'radius_m': radiusM} : null,
    );
    final rows = (body['ride_requests'] as List?) ?? const [];
    return rows.cast<Map<String, dynamic>>().map(RideRequest.fromApiJson).toList();
  }
}
