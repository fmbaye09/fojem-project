import '../core/geo/geo_location.dart';
import '../core/geo/senegal_city_coordinates.dart';
import 'driver.dart';
import 'vehicle.dart';

enum TripStatus { upcoming, inProgress, completed, cancelled }

TripStatus _statusFromApi(String? status) {
  switch (status) {
    case 'open':
    case 'full':
      return TripStatus.upcoming;
    case 'in_progress':
      return TripStatus.inProgress;
    case 'completed':
      return TripStatus.completed;
    case 'cancelled':
      return TripStatus.cancelled;
    default:
      return TripStatus.upcoming;
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

class Trip {
  final String id;
  final String driverId;
  final String vehicleId;
  final String departure;
  final String arrival;
  final String departureAddress;
  final String arrivalAddress;
  final GeoLocation origin;
  final GeoLocation destination;
  final List<GeoLocation> waypointLocations;
  final DateTime departureTime;
  final Duration estimatedDuration;
  final int seatsTotal;
  final int availableSeats;
  final double pricePerSeat;
  final TripStatus status;
  final VehicleType vehicleType;
  final String? notes;
  final double? currentLat;
  final double? currentLng;
  final double? currentHeading;
  final DateTime? locationUpdatedAt;

  final List<String> occupiedSeatIds;
  final Driver? driver;

  const Trip({
    required this.id,
    required this.driverId,
    required this.vehicleId,
    required this.departure,
    required this.arrival,
    required this.departureAddress,
    required this.arrivalAddress,
    required this.origin,
    required this.destination,
    this.waypointLocations = const [],
    required this.departureTime,
    required this.estimatedDuration,
    required this.seatsTotal,
    required this.availableSeats,
    required this.pricePerSeat,
    required this.status,
    required this.vehicleType,
    this.notes,
    this.currentLat,
    this.currentLng,
    this.currentHeading,
    this.locationUpdatedAt,
    this.occupiedSeatIds = const [],
    this.driver,
  });

  String get durationLabel {
    final hours = estimatedDuration.inHours;
    final minutes = estimatedDuration.inMinutes.remainder(60);
    if (hours == 0) return '${minutes}min';
    if (minutes == 0) return '${hours}h';
    return '${hours}h${minutes.toString().padLeft(2, '0')}';
  }

  bool get isFull => availableSeats == 0;

  List<GeoLocation> get path => [origin, ...waypointLocations, destination];

  factory Trip.fromApi(Map<String, dynamic> map) {
    final originLat = double.tryParse('${map['origin_lat'] ?? ''}');
    final originLng = double.tryParse('${map['origin_lng'] ?? ''}');
    final destLat = double.tryParse('${map['destination_lat'] ?? ''}');
    final destLng = double.tryParse('${map['destination_lng'] ?? ''}');

    final currentLat = double.tryParse('${map['current_lat'] ?? ''}');
    final currentLng = double.tryParse('${map['current_lng'] ?? ''}');
    final currentHeading = double.tryParse('${map['current_heading'] ?? ''}');
    final locationUpdatedAt = DateTime.tryParse('${map['location_updated_at'] ?? ''}');

    final originName = map['origin_name'] as String?;
    final destName = map['destination_name'] as String?;

    final departureCity = (originName != null && originName.isNotEmpty)
        ? originName
        : _cityFromCoords(originLat, originLng);
    final arrivalCity = (destName != null && destName.isNotEmpty)
        ? destName
        : _cityFromCoords(destLat, destLng);

    final origin = GeoLocation(
      lat: (originLat != null && originLat != 0) ? originLat : coordinatesForCity(departureCity).lat,
      lng: (originLng != null && originLng != 0) ? originLng : coordinatesForCity(departureCity).lng,
      address: departureCity,
    );
    final destination = GeoLocation(
      lat: (destLat != null && destLat != 0) ? destLat : coordinatesForCity(arrivalCity).lat,
      lng: (destLng != null && destLng != 0) ? destLng : coordinatesForCity(arrivalCity).lng,
      address: arrivalCity,
    );

    final waypoints = <GeoLocation>[];
    if (map['waypoints'] is List) {
      for (final wp in (map['waypoints'] as List)) {
        if (wp is Map<String, dynamic>) {
          final wLat = double.tryParse('${wp['lat'] ?? ''}');
          final wLng = double.tryParse('${wp['lng'] ?? ''}');
          final wName = wp['name'] as String? ?? '';
          if (wLat != null && wLng != null) {
            waypoints.add(GeoLocation(lat: wLat, lng: wLng, address: wName));
          }
        }
      }
    }

    final vehicleJson = map['vehicle'] as Map<String, dynamic>?;
    final driverProfileJson = map['driver_profile'] as Map<String, dynamic>?;

    final vehicle = vehicleJson != null ? Vehicle.fromApi(vehicleJson) : null;
    final driver = driverProfileJson != null
        ? Driver.fromApi(driverProfileJson, vehicle: vehicle)
        : null;

    final distanceKm = origin.distanceKm(destination);
    final estimatedDuration = Duration(minutes: (distanceKm / 40 * 60).round().clamp(5, 24 * 60));

    final seatsAvailable = int.tryParse('${map['seats_available'] ?? ''}') ?? 0;

    return Trip(
      id: map['id'] as String? ?? '',
      driverId: driver?.id ?? (driverProfileJson?['user_id'] as String? ?? ''),
      vehicleId: vehicleJson?['id'] as String? ?? map['vehicle_id'] as String? ?? '',
      departure: departureCity,
      arrival: arrivalCity,
      departureAddress: departureCity,
      arrivalAddress: arrivalCity,
      origin: origin,
      destination: destination,
      waypointLocations: waypoints,
      departureTime: DateTime.tryParse(map['scheduled_at'] as String? ?? '') ?? DateTime.now(),
      estimatedDuration: estimatedDuration,
      seatsTotal: vehicle?.totalSeats ?? seatsAvailable,
      availableSeats: seatsAvailable,
      pricePerSeat: double.tryParse('${map['price_per_seat'] ?? ''}') ?? 0,
      status: _statusFromApi(map['status'] as String?),
      vehicleType: vehicle?.type ?? VehicleType.septPlaces,
      notes: null,
      currentLat: currentLat,
      currentLng: currentLng,
      currentHeading: currentHeading,
      locationUpdatedAt: locationUpdatedAt,
      driver: driver,
    );
  }

  Trip copyWith({
    int? availableSeats,
    TripStatus? status,
    List<String>? occupiedSeatIds,
    Driver? driver,
    double? currentLat,
    double? currentLng,
    double? currentHeading,
    DateTime? locationUpdatedAt,
  }) {
    return Trip(
      id: id,
      driverId: driverId,
      vehicleId: vehicleId,
      departure: departure,
      arrival: arrival,
      departureAddress: departureAddress,
      arrivalAddress: arrivalAddress,
      origin: origin,
      destination: destination,
      waypointLocations: waypointLocations,
      departureTime: departureTime,
      estimatedDuration: estimatedDuration,
      seatsTotal: seatsTotal,
      availableSeats: availableSeats ?? this.availableSeats,
      pricePerSeat: pricePerSeat,
      status: status ?? this.status,
      vehicleType: vehicleType,
      notes: notes,
      currentLat: currentLat ?? this.currentLat,
      currentLng: currentLng ?? this.currentLng,
      currentHeading: currentHeading ?? this.currentHeading,
      locationUpdatedAt: locationUpdatedAt ?? this.locationUpdatedAt,
      occupiedSeatIds: occupiedSeatIds ?? this.occupiedSeatIds,
      driver: driver ?? this.driver,
    );
  }
}
