import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/geo/geo_location.dart';
import 'map_service.dart';

/// Implémentation gratuite basée sur OpenStreetMap : Nominatim pour le
/// géocodage, OSRM (serveur de démo public) pour le routing.
///
/// ATTENTION production : les instances publiques `nominatim.openstreetmap.org`
/// et `router.project-osrm.org` sont limitées en volume et interdisent un
/// usage intensif sans en être l'opérateur (voir leurs Usage Policy) — avant
/// un vrai lancement il faudra soit s'auto-héberger, soit passer sur un
/// service payant (cette classe reste isolée derrière [MapService] pour que
/// ce changement n'affecte aucun écran).
class OsmMapService implements MapService {
  static const _nominatimBase = 'https://nominatim.openstreetmap.org';
  static const _osrmBase = 'https://router.project-osrm.org';
  static const _userAgent = 'Fojem/1.0 (contact@fojem.sn)';
  static const _senegalViewbox = '-17.6,16.7,-11.3,12.2';

  @override
  Future<List<GeoLocation>> searchAddress(String query) async {
    if (query.trim().length < 2) return [];

    final uri = Uri.parse('$_nominatimBase/search').replace(queryParameters: {
      'q': query,
      'format': 'jsonv2',
      'limit': '8',
      'countrycodes': 'sn',
      'viewbox': _senegalViewbox,
      'bounded': '1',
    });

    final response = await http.get(uri, headers: {'User-Agent': _userAgent});
    if (response.statusCode != 200) return [];

    final results = jsonDecode(response.body) as List;
    return results.map((r) {
      final map = r as Map<String, dynamic>;
      return GeoLocation(
        lat: double.parse(map['lat'] as String),
        lng: double.parse(map['lon'] as String),
        address: map['display_name'] as String,
      );
    }).toList();
  }

  @override
  Future<GeoLocation> reverseGeocode(double lat, double lng) async {
    final uri = Uri.parse('$_nominatimBase/reverse').replace(queryParameters: {
      'lat': '$lat',
      'lon': '$lng',
      'format': 'jsonv2',
    });

    final response = await http.get(uri, headers: {'User-Agent': _userAgent});
    if (response.statusCode != 200) {
      return GeoLocation(lat: lat, lng: lng, address: '$lat, $lng');
    }

    final map = jsonDecode(response.body) as Map<String, dynamic>;
    return GeoLocation(
      lat: lat,
      lng: lng,
      address: map['display_name'] as String? ?? '$lat, $lng',
    );
  }

  @override
  Future<RouteResult?> getRoute(GeoLocation from, GeoLocation to) async {
    final uri = Uri.parse(
      '$_osrmBase/route/v1/driving/${from.lng},${from.lat};${to.lng},${to.lat}'
      '?overview=full&geometries=geojson',
    );

    final response = await http.get(uri, headers: {'User-Agent': _userAgent});
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final routes = data['routes'] as List?;
    if (routes == null || routes.isEmpty) return null;

    final route = routes.first as Map<String, dynamic>;
    final coords = (route['geometry']['coordinates'] as List).cast<List>();
    final polyline = coords
        .map((c) => GeoLocation(lat: (c[1] as num).toDouble(), lng: (c[0] as num).toDouble(), address: ''))
        .toList();

    return RouteResult(
      polyline: polyline,
      distanceKm: (route['distance'] as num).toDouble() / 1000,
      duration: Duration(seconds: (route['duration'] as num).round()),
    );
  }
}
