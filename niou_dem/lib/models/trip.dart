import '../core/geo/geo_location.dart';
import '../core/geo/senegal_city_coordinates.dart';
import 'driver.dart';
import 'trip_stop.dart';
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

  /// Points de rendez-vous, départ en premier, arrivée en dernier.
  final List<TripStop> stops;

  /// Renseigné pour un résultat de recherche : arrêts proposés au passager.
  final TripMatch? match;

  /// Progression en direct (trajet en cours), renvoyée par le détail.
  final TripLive? live;

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
    this.stops = const [],
    this.match,
    this.live,
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

  List<GeoLocation> get path => stops.length >= 2
      ? [for (final s in stops) s.location]
      : [origin, ...waypointLocations, destination];

  TripStop? stopById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final s in stops) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Tronçon du passager : arrêts demandés, sinon ceux proposés par la
  /// recherche, sinon le trajet complet.
  TripSegment segment({String? boardingStopId, String? alightingStopId}) {
    final boarding = stopById(boardingStopId) ??
        match?.boardingStop ??
        (stops.isNotEmpty ? stops.first : null);
    final alighting = stopById(alightingStopId) ??
        match?.alightingStop ??
        (stops.isNotEmpty ? stops.last : null);
    return TripSegment(
      boarding: boarding,
      alighting: alighting,
      pricePerSeat: boarding != null && alighting != null
          ? alighting.priceFromOrigin - boarding.priceFromOrigin
          : pricePerSeat,
    );
  }

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

    // Durée : heures des arrêts publiées par le chauffeur (calculées sur la
    // route) ; à défaut, estimation à vol d'oiseau.
    final stops = TripStop.listFromJson(map['stops']);
    final firstTime = stops.isNotEmpty ? stops.first.scheduledAt : null;
    final lastTime = stops.length >= 2 ? stops.last.scheduledAt : null;
    final distanceKm = origin.distanceKm(destination);
    final estimatedDuration = (firstTime != null && lastTime != null && lastTime.isAfter(firstTime))
        ? lastTime.difference(firstTime)
        : Duration(minutes: (distanceKm * 1.25 / 60 * 60).round().clamp(5, 24 * 60));

    final seatsAvailable = int.tryParse('${map['seats_available'] ?? ''}') ?? 0;

    return Trip(
      id: map['id'] as String? ?? '',
      driverId: driver?.id ?? (driverProfileJson?['user_id'] as String? ?? ''),
      vehicleId: vehicleJson?['id'] as String? ?? map['vehicle_id'] as String? ?? '',
      departure: departureCity,
      arrival: arrivalCity,
      departureAddress: stops.isNotEmpty ? stops.first.displayAddress : departureCity,
      arrivalAddress: stops.length >= 2 ? stops.last.displayAddress : arrivalCity,
      origin: origin,
      destination: destination,
      waypointLocations: stops.length > 2
          ? [for (final s in stops.sublist(1, stops.length - 1)) s.location]
          : waypoints,
      departureTime: (DateTime.tryParse(map['scheduled_at'] as String? ?? '') ?? DateTime.now()).toLocal(),
      stops: stops,
      match: map['match'] is Map<String, dynamic>
          ? TripMatch.fromJson(map['match'] as Map<String, dynamic>)
          : null,
      live: map['live'] is Map<String, dynamic>
          ? TripLive.fromJson(map['live'] as Map<String, dynamic>)
          : null,
      estimatedDuration: estimatedDuration,
      seatsTotal: vehicle?.totalSeats ?? seatsAvailable,
      availableSeats: seatsAvailable,
      // Renvoyé par `GET /trips/{id}` : sièges déjà pris (demandes en
      // attente comprises), à griser sur le plan du véhicule.
      occupiedSeatIds: [
        for (final seat in (map['occupied_seats'] as List? ?? const [])) '$seat',
      ],
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
      stops: stops,
      match: match,
      live: live,
    );
  }
}

/// Progression d'un trajet en cours, calculée par le serveur
/// (`GET /trips/{id}` → `live`).
class TripLive {
  /// Position GPS du chauffeur reçue il y a moins de 3 min.
  final bool locationFresh;

  /// Dernier arrêt atteint par le chauffeur (0 = départ).
  final int? lastPassedStopPosition;
  final String? nextStopId;

  /// `live` (d'après la position GPS) ou `schedule` (horaire publié, faute
  /// de position récente).
  final String? etaSource;
  final int? delayMinutes;

  /// Heure d'arrivée estimée à chaque arrêt restant, par id d'arrêt.
  final Map<String, DateTime> etas;

  const TripLive({
    required this.locationFresh,
    this.lastPassedStopPosition,
    this.nextStopId,
    this.etaSource,
    this.delayMinutes,
    this.etas = const {},
  });

  bool get isLiveEstimate => etaSource == 'live';

  factory TripLive.fromJson(Map<String, dynamic> json) {
    final etas = <String, DateTime>{};
    for (final e in (json['etas'] as List? ?? const [])) {
      if (e is Map<String, dynamic>) {
        final at = DateTime.tryParse('${e['eta']}');
        if (at != null) etas['${e['stop_id']}'] = at.toLocal();
      }
    }
    return TripLive(
      locationFresh: json['location_fresh'] == true,
      lastPassedStopPosition: int.tryParse('${json['last_passed_stop_position'] ?? ''}'),
      nextStopId: json['next_stop_id'] as String?,
      etaSource: json['eta_source'] as String?,
      delayMinutes: int.tryParse('${json['delay_minutes'] ?? ''}'),
      etas: etas,
    );
  }
}

/// Arrêts proposés au passager par la recherche, et à quelle distance ils
/// sont de son point de départ et de sa destination.
class TripMatch {
  final TripStop? boardingStop;
  final TripStop? alightingStop;
  final int boardingDistanceM;
  final int alightingDistanceM;
  final double segmentPrice;

  const TripMatch({
    required this.boardingStop,
    required this.alightingStop,
    required this.boardingDistanceM,
    required this.alightingDistanceM,
    required this.segmentPrice,
  });

  factory TripMatch.fromJson(Map<String, dynamic> json) {
    TripStop? stop(Object? raw) => raw is Map<String, dynamic> ? TripStop.fromJson(raw) : null;
    return TripMatch(
      boardingStop: stop(json['boarding_stop']),
      alightingStop: stop(json['alighting_stop']),
      boardingDistanceM: int.tryParse('${json['boarding_distance_m'] ?? 0}') ?? 0,
      alightingDistanceM: int.tryParse('${json['alighting_distance_m'] ?? 0}') ?? 0,
      segmentPrice: double.tryParse('${json['segment_price'] ?? 0}') ?? 0,
    );
  }
}

/// Le tronçon que le passager réserve : où il monte, où il descend, et le
/// prix par place correspondant.
class TripSegment {
  final TripStop? boarding;
  final TripStop? alighting;
  final double pricePerSeat;

  const TripSegment({required this.boarding, required this.alighting, required this.pricePerSeat});
}

/// Heure à laquelle le passager monte (arrêt proposé par la recherche),
/// sinon l'heure de départ du trajet.
DateTime boardingTime(Trip trip) => trip.match?.boardingStop?.scheduledAt ?? trip.departureTime;

/// Route du détail d'un trajet, avec le tronçon proposé par la recherche
/// pour que le passager réserve directement entre ses deux arrêts.
String tripDetailLocation(Trip trip) {
  final board = trip.match?.boardingStop?.id;
  final alight = trip.match?.alightingStop?.id;
  if (board == null || alight == null) return '/trip/${trip.id}';
  return '/trip/${trip.id}?board=$board&alight=$alight';
}

/// « à 1,2 km », « à 300 m », « sur place ».
String formatDistanceFromYou(int meters) {
  if (meters < 150) return 'sur place';
  if (meters < 1000) return 'à ${(meters / 50).round() * 50} m';
  final km = meters / 1000;
  return 'à ${km < 10 ? km.toStringAsFixed(1).replaceAll('.', ',') : km.round()} km';
}
