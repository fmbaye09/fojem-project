import '../core/geo/geo_location.dart';
import '../core/geo/senegal_city_coordinates.dart';

enum RideRequestStatus { open, matched, closed }

RideRequestStatus _statusFromApi(String? value) {
  switch (value) {
    case 'matched':
      return RideRequestStatus.matched;
    case 'cancelled':
    case 'expired':
      return RideRequestStatus.closed;
    default:
      return RideRequestStatus.open;
  }
}

String _cityFromCoords(double lat, double lng) {
  if (lat == 0 && lng == 0) return 'Dakar';
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

class RideRequest {
  final String id;
  final String passengerId;
  final String passengerName;
  final GeoLocation origin;
  final GeoLocation destination;
  final DateTime desiredDateTime;
  final RideRequestStatus status;
  final int seatsNeeded;
  final double? compatibilityScore;
  final int? detourDistanceM;

  const RideRequest({
    required this.id,
    required this.passengerId,
    required this.passengerName,
    required this.origin,
    required this.destination,
    required this.desiredDateTime,
    required this.status,
    this.seatsNeeded = 1,
    this.compatibilityScore,
    this.detourDistanceM,
  });

  factory RideRequest.fromApiJson(Map<String, dynamic> json) {
    final passenger = json['passenger'] as Map<String, dynamic>?;
    final originLat = double.tryParse('${json['origin_lat'] ?? ''}') ?? 0.0;
    final originLng = double.tryParse('${json['origin_lng'] ?? ''}') ?? 0.0;
    final destLat = double.tryParse('${json['destination_lat'] ?? ''}') ?? 0.0;
    final destLng = double.tryParse('${json['destination_lng'] ?? ''}') ?? 0.0;

    final originName = json['origin_name'] as String?;
    final destName = json['destination_name'] as String?;

    final originLabel = (originName != null && originName.isNotEmpty)
        ? originName
        : _cityFromCoords(originLat, originLng);
    final destLabel = (destName != null && destName.isNotEmpty)
        ? destName
        : _cityFromCoords(destLat, destLng);

    return RideRequest(
      id: json['id'] as String? ?? '',
      passengerId: json['passenger_id'] as String? ?? '',
      passengerName: (passenger?['full_name'] as String?)?.isNotEmpty == true
          ? passenger!['full_name'] as String
          : 'Passager',
      origin: GeoLocation(
        lat: originLat,
        lng: originLng,
        address: originLabel,
      ),
      destination: GeoLocation(
        lat: destLat,
        lng: destLng,
        address: destLabel,
      ),
      desiredDateTime: DateTime.tryParse(json['requested_at'] as String? ?? '') ?? DateTime.now(),
      status: _statusFromApi(json['status'] as String?),
      seatsNeeded: int.tryParse('${json['seats_needed'] ?? ''}') ?? 1,
      compatibilityScore: double.tryParse('${json['compatibility_score'] ?? ''}'),
      detourDistanceM: int.tryParse('${json['detour_distance_m'] ?? ''}'),
    );
  }
}
