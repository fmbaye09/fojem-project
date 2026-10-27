import '../../core/geo/geo_location.dart';

/// Un tronçon de l'itinéraire, entre deux points consécutifs.
class RouteLeg {
  final double distanceKm;
  final Duration duration;

  const RouteLeg({required this.distanceKm, required this.duration});
}

class RouteResult {
  final List<GeoLocation> polyline;
  final double distanceKm;
  final Duration duration;

  /// Un tronçon par paire de points consécutifs (vide pour [MapService.getRoute]
  /// qui ne relie que deux points : l'itinéraire entier est alors le seul tronçon).
  final List<RouteLeg> legs;

  const RouteResult({
    required this.polyline,
    required this.distanceKm,
    required this.duration,
    this.legs = const [],
  });
}

/// Abstraction du fournisseur cartographique (Phase 5). Implémentation
/// actuelle : [OsmMapService] (OpenStreetMap/Nominatim/OSRM, gratuit). Un
/// futur `GoogleMapService` pourrait implémenter la même interface sans
/// toucher aux écrans qui l'utilisent.
abstract class MapService {
  /// Recherche d'adresse (autocomplete) — retourne des candidats géolocalisés.
  Future<List<GeoLocation>> searchAddress(String query);

  /// Adresse lisible la plus proche d'un point (tap sur la carte).
  Future<GeoLocation> reverseGeocode(double lat, double lng);

  /// Itinéraire routier entre deux points (pour affichage + distance réelle,
  /// utilisée pour la suggestion de prix en Phase 2).
  Future<RouteResult?> getRoute(GeoLocation from, GeoLocation to);

  /// Itinéraire routier passant par tous les [points] dans l'ordre, avec la
  /// distance et la durée de chaque tronçon (heures et prix des arrêts).
  Future<RouteResult?> getRouteThrough(List<GeoLocation> points);
}
