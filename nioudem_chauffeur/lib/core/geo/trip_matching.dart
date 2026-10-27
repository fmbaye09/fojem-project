import 'geo_location.dart';

/// Seuil par défaut (km) en-deçà duquel un point du trajet du chauffeur est
/// considéré "proche" du départ/arrivée souhaité par le passager (Phase 4).
const double kDefaultMatchThresholdKm = 5.0;

/// Résultat d'une tentative de correspondance entre un trajet chauffeur et
/// une recherche/demande passager.
class MatchResult {
  final bool matches;

  /// Distance (km) entre le départ souhaité et le point du trajet le plus
  /// proche.
  final double originDistanceKm;

  /// Distance (km) entre l'arrivée souhaitée et le point du trajet le plus
  /// proche (recherché uniquement à partir du point de départ apparié, pour
  /// respecter le sens du trajet).
  final double destinationDistanceKm;

  const MatchResult({
    required this.matches,
    required this.originDistanceKm,
    required this.destinationDistanceKm,
  });

  /// Score de pertinence géographique — plus bas est meilleur. Utilisé pour
  /// trier les résultats (Phase 4 : tri par distance, puis heure/prix/note).
  double get score => originDistanceKm + destinationDistanceKm;

  static const none = MatchResult(matches: false, originDistanceKm: double.infinity, destinationDistanceKm: double.infinity);
}

/// Détermine si un trajet dont le chemin est `origin -> waypoints -> destination`
/// correspond à un départ/arrivée souhaités, à `thresholdKm` près, **dans le
/// bon ordre** (le point d'arrivée apparié doit se trouver après le point de
/// départ apparié le long du trajet — un trajet Dakar→Thiès ne doit pas
/// matcher une demande Thiès→Dakar juste parce que les deux villes sont sur
/// le chemin).
///
/// Fonction pure, sans dépendance Firestore/UI : c'est la logique la plus
/// critique de l'app (Phase 4), testée indépendamment dans
/// `test/core/geo/trip_matching_test.dart`.
MatchResult matchTripPath({
  required GeoLocation tripOrigin,
  required List<GeoLocation> tripWaypoints,
  required GeoLocation tripDestination,
  required GeoLocation desiredOrigin,
  required GeoLocation desiredDestination,
  double thresholdKm = kDefaultMatchThresholdKm,
}) {
  final path = [tripOrigin, ...tripWaypoints, tripDestination];

  var bestOriginIdx = -1;
  var bestOriginDist = double.infinity;
  for (var i = 0; i < path.length; i++) {
    final d = desiredOrigin.distanceKm(path[i]);
    if (d < bestOriginDist) {
      bestOriginDist = d;
      bestOriginIdx = i;
    }
  }

  if (bestOriginIdx == -1 || bestOriginDist > thresholdKm) {
    return MatchResult.none;
  }

  var bestDestIdx = -1;
  var bestDestDist = double.infinity;
  for (var i = bestOriginIdx; i < path.length; i++) {
    final d = desiredDestination.distanceKm(path[i]);
    if (d < bestDestDist) {
      bestDestDist = d;
      bestDestIdx = i;
    }
  }

  // bestDestIdx est cherché à partir de bestOriginIdx : il est donc toujours
  // >= bestOriginIdx par construction, ce qui garantit le bon sens du trajet.
  if (bestDestIdx == -1 || bestDestDist > thresholdKm) {
    return MatchResult.none;
  }

  return MatchResult(
    matches: true,
    originDistanceKm: bestOriginDist,
    destinationDistanceKm: bestDestDist,
  );
}
