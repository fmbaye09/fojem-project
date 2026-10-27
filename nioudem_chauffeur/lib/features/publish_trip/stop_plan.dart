import '../../core/geo/geo_location.dart';
import '../../services/map/map_service.dart';

/// Un point de rendez-vous en cours de publication, avec l'heure et le prix
/// calculés depuis l'itinéraire.
class PlannedStop {
  final GeoLocation location;
  final DateTime scheduledAt;

  /// Prix par place depuis le départ (0 au départ, prix complet à l'arrivée).
  final double priceFromOrigin;

  /// Le chauffeur a saisi ce prix lui-même (sinon : prorata de la distance).
  final bool priceEdited;

  const PlannedStop({
    required this.location,
    required this.scheduledAt,
    required this.priceFromOrigin,
    this.priceEdited = false,
  });

  /// Corps attendu par `POST /trips` pour ce point.
  Map<String, dynamic> toApi() => {
        'name': location.shortLabel,
        'address': location.address,
        'lat': location.lat,
        'lng': location.lng,
        'scheduled_at': scheduledAt.toUtc().toIso8601String(),
        'price_from_origin': priceFromOrigin,
      };
}

/// Mêmes hypothèses que le backend (`TripStopPlanner`) quand l'itinéraire
/// routier est indisponible : distance à vol d'oiseau × 1,25, à 60 km/h.
const _roadFactor = 1.25;
const _fallbackSpeedKmh = 60.0;
const _priceRounding = 50.0;

/// Heures et prix de chaque point, à partir des tronçons de l'itinéraire
/// ([legs], un par paire de points) ou d'une estimation s'ils manquent.
/// [priceOverrides] : prix saisis par le chauffeur, par index de point.
List<PlannedStop> planStops({
  required List<GeoLocation> points,
  required List<RouteLeg> legs,
  required DateTime departure,
  required double fullPrice,
  Map<int, double> priceOverrides = const {},
}) {
  final useLegs = legs.length == points.length - 1;
  final cumulativeKm = <double>[0];
  final cumulativeTime = <Duration>[Duration.zero];
  for (var i = 1; i < points.length; i++) {
    final km = useLegs
        ? legs[i - 1].distanceKm
        : points[i - 1].distanceKm(points[i]) * _roadFactor;
    final duration = useLegs
        ? legs[i - 1].duration
        : Duration(minutes: (km / _fallbackSpeedKmh * 60).ceil());
    cumulativeKm.add(cumulativeKm.last + km);
    cumulativeTime.add(cumulativeTime.last + duration);
  }
  final totalKm = cumulativeKm.last <= 0 ? 1.0 : cumulativeKm.last;
  final last = points.length - 1;

  return [
    for (var i = 0; i < points.length; i++)
      PlannedStop(
        location: points[i],
        scheduledAt: departure.add(cumulativeTime[i]),
        priceFromOrigin: i == 0
            ? 0
            : i == last
                ? fullPrice
                : priceOverrides[i] ??
                    (fullPrice * cumulativeKm[i] / totalKm / _priceRounding).round() * _priceRounding,
        priceEdited: i != 0 && i != last && priceOverrides.containsKey(i),
      ),
  ];
}

/// Ordonne les arrêts intermédiaires du départ vers l'arrivée (trajets
/// interurbains quasi linéaires) : le chauffeur peut les ajouter dans
/// n'importe quel ordre.
List<GeoLocation> orderAlongRoute(GeoLocation origin, List<GeoLocation> intermediate) {
  return [...intermediate]..sort((a, b) => origin.distanceKm(a).compareTo(origin.distanceKm(b)));
}
