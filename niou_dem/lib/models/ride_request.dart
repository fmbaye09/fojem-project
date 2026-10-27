import '../core/geo/geo_location.dart';
import '../core/geo/senegal_city_coordinates.dart';

enum RideRequestStatus { open, matched, closed }

RideRequestStatus _statusFromApi(String? status) {
  switch (status) {
    case 'searching':
      return RideRequestStatus.open;
    case 'matched':
      return RideRequestStatus.matched;
    default:
      return RideRequestStatus.closed;
  }
}

String _cityFromCoords(double? lat, double? lng) {
  if (lat == null || lng == null || (lat == 0 && lng == 0)) return 'Dakar';
  String closest = 'Dakar';
  double minDist = double.infinity;
  for (final entry in senegalCityCoordinates.entries) {
    final dLat = entry.value.lat - lat;
    final dLng = entry.value.lng - lng;
    final dist = dLat * dLat + dLng * dLng;
    if (dist < minDist) {
      minDist = dist;
      closest = entry.key;
    }
  }
  return closest;
}

/// Demande de trajet publiée par un passager quand aucune offre existante ne
/// lui convient.
class RideRequest {
  final String id;
  final String passengerId;
  final String passengerName;
  final GeoLocation origin;
  final GeoLocation destination;

  final DateTime desiredDateTime;
  final RideRequestStatus status;
  final DateTime createdAt;

  const RideRequest({
    required this.id,
    required this.passengerId,
    required this.passengerName,
    required this.origin,
    required this.destination,
    required this.desiredDateTime,
    required this.status,
    required this.createdAt,
  });

  factory RideRequest.fromApi(
    Map<String, dynamic> map, {
    GeoLocation? origin,
    GeoLocation? destination,
    String passengerName = '',
  }) {
    final originLat = double.tryParse('${map['origin_lat'] ?? ''}');
    final originLng = double.tryParse('${map['origin_lng'] ?? ''}');
    final destLat = double.tryParse('${map['destination_lat'] ?? ''}');
    final destLng = double.tryParse('${map['destination_lng'] ?? ''}');

    final originName = map['origin_name'] as String?;
    final destName = map['destination_name'] as String?;

    final departureCity = (originName != null && originName.isNotEmpty)
        ? originName
        : _cityFromCoords(originLat, originLng);
    final arrivalCity = (destName != null && destName.isNotEmpty)
        ? destName
        : _cityFromCoords(destLat, destLng);

    final resolvedOrigin = origin ??
        GeoLocation(
          lat: originLat ?? 0,
          lng: originLng ?? 0,
          address: departureCity,
        );
    final resolvedDestination = destination ??
        GeoLocation(
          lat: destLat ?? 0,
          lng: destLng ?? 0,
          address: arrivalCity,
        );

    final createdAt = DateTime.tryParse(map['requested_at'] as String? ?? map['created_at'] as String? ?? '') ??
        DateTime.now();
    return RideRequest(
      id: map['id'] as String? ?? '',
      passengerId: map['passenger_id'] as String? ?? '',
      passengerName: passengerName,
      origin: resolvedOrigin,
      destination: resolvedDestination,
      desiredDateTime: createdAt,
      status: _statusFromApi(map['status'] as String?),
      createdAt: createdAt,
    );
  }
}
