import '../../core/geo/geo_location.dart';

class RouteResult {
  final List<GeoLocation> polyline;
  final double distanceKm;
  final Duration duration;

  const RouteResult({
    required this.polyline,
    required this.distanceKm,
    required this.duration,
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
}
