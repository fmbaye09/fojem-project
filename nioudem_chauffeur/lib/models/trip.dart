import '../core/geo/geo_location.dart';
import '../core/geo/senegal_city_coordinates.dart';
import 'vehicle.dart';

enum TripStatus { upcoming, inProgress, completed, cancelled }

TripStatus _statusFromApi(String? value) {
  switch (value) {
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
  });

  String get durationLabel {
    final hours = estimatedDuration.inHours;
    final minutes = estimatedDuration.inMinutes.remainder(60);
    if (hours == 0 && minutes == 0) return '';
    if (hours == 0) return '${minutes}min';
    if (minutes == 0) return '${hours}h';
    return '${hours}h${minutes.toString().padLeft(2, '0')}';
  }

  bool get isFull => availableSeats == 0;

  List<GeoLocation> get path => [origin, ...waypointLocations, destination];

  static String _cityFromCoords(double lat, double lng) {
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

  factory Trip.fromApiJson(Map<String, dynamic> json, {Map<String, dynamic>? cached}) {
    final id = json['id'] as String? ?? '';

    final originLat = double.tryParse('${json['origin_lat'] ?? ''}') ??
        (cached?['originLat'] as num?)?.toDouble() ??
        0.0;
    final originLng = double.tryParse('${json['origin_lng'] ?? ''}') ??
        (cached?['originLng'] as num?)?.toDouble() ??
        0.0;
    final destLat = double.tryParse('${json['destination_lat'] ?? ''}') ??
        (cached?['destinationLat'] as num?)?.toDouble() ??
        0.0;
    final destLng = double.tryParse('${json['destination_lng'] ?? ''}') ??
        (cached?['destinationLng'] as num?)?.toDouble() ??
        0.0;

    final currentLat = double.tryParse('${json['current_lat'] ?? ''}');
    final currentLng = double.tryParse('${json['current_lng'] ?? ''}');
    final currentHeading = double.tryParse('${json['current_heading'] ?? ''}');
    final locationUpdatedAt = DateTime.tryParse('${json['location_updated_at'] ?? ''}');

    final originName = json['origin_name'] as String?;
    final destName = json['destination_name'] as String?;

    String departure = (originName != null && originName.isNotEmpty)
        ? originName
        : (cached?['departure'] as String? ?? '');
    if (departure.isEmpty && originLat != 0) {
      departure = _cityFromCoords(originLat, originLng);
    }
    if (departure.isEmpty) departure = 'Dakar';

    String arrival = (destName != null && destName.isNotEmpty)
        ? destName
        : (cached?['arrival'] as String? ?? '');
    if (arrival.isEmpty && destLat != 0) {
      arrival = _cityFromCoords(destLat, destLng);
    }
    if (arrival.isEmpty) arrival = 'Thiès';

    final origin = GeoLocation(
      lat: originLat != 0 ? originLat : coordinatesForCity(departure).lat,
      lng: originLng != 0 ? originLng : coordinatesForCity(departure).lng,
      address: cached?['departureAddress'] as String? ?? departure,
    );
    final destination = GeoLocation(
      lat: destLat != 0 ? destLat : coordinatesForCity(arrival).lat,
      lng: destLng != 0 ? destLng : coordinatesForCity(arrival).lng,
      address: cached?['arrivalAddress'] as String? ?? arrival,
    );

    final waypoints = <GeoLocation>[];
    if (json['waypoints'] is List) {
      for (final wp in (json['waypoints'] as List)) {
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

    final seatsAvailable = int.tryParse('${json['seats_available'] ?? 0}') ?? 0;
    final cachedSeatsTotal = cached?['seatsTotal'] as int?;

    return Trip(
      id: id,
      driverId: json['driver_id'] as String? ?? '',
      vehicleId: json['vehicle_id'] as String? ?? '',
      departure: departure,
      arrival: arrival,
      departureAddress: cached?['departureAddress'] as String? ?? departure,
      arrivalAddress: cached?['arrivalAddress'] as String? ?? arrival,
      origin: origin,
      destination: destination,
      waypointLocations: waypoints,
      departureTime: DateTime.tryParse(json['scheduled_at'] as String? ?? '') ?? DateTime.now(),
      estimatedDuration: cached?['estimatedMinutes'] != null
          ? Duration(minutes: cached!['estimatedMinutes'] as int)
          : Duration.zero,
      seatsTotal: cachedSeatsTotal ?? seatsAvailable,
      availableSeats: seatsAvailable,
      pricePerSeat: double.tryParse('${json['price_per_seat'] ?? 0}') ?? 0,
      status: _statusFromApi(json['status'] as String?),
      vehicleType: VehicleType.values.firstWhere(
        (t) => t.name == cached?['vehicleType'],
        orElse: () => VehicleType.septPlaces,
      ),
      notes: cached?['notes'] as String?,
      currentLat: currentLat,
      currentLng: currentLng,
      currentHeading: currentHeading,
      locationUpdatedAt: locationUpdatedAt,
    );
  }

  Trip copyWith({
    int? availableSeats,
    TripStatus? status,
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
    );
  }
}
