import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/geo/geo_location.dart';
import '../../core/geo/senegal_city_coordinates.dart';
import '../../core/network/api_client.dart';
import 'map_service.dart';
import 'osm_map_service.dart';

/// Nature d'un lieu proposé, pour son icône et son sous-titre.
enum PlaceKind { city, busStation, toll, roundabout, fuelStation, address, recent }

/// Lieu proposé dans la recherche d'adresse.
class PlaceSuggestion {
  final GeoLocation location;
  final String title;
  final String? subtitle;
  final PlaceKind kind;

  const PlaceSuggestion({required this.location, required this.title, this.subtitle, required this.kind});
}

/// Recherche d'un départ, d'une arrivée ou d'un arrêt : les villes du
/// Sénégal, puis les lieux de rendez-vous connus de FOJËM (gares routières,
/// péages, ronds-points, stations), puis les adresses OpenStreetMap, moins
/// fiables pour ces lieux mais complètes pour le reste.
class PlaceSearch {
  final ApiClient? _client;
  final MapService _mapService;

  PlaceSearch({ApiClient? client, MapService? mapService})
      : _client = client,
        _mapService = mapService ?? OsmMapService();

  /// Villes principales, proposées avant toute saisie.
  static const popularCities = ['Dakar', 'Thiès', 'Mbour', 'Touba', 'Saint-Louis', 'Kaolack', 'Ziguinchor'];

  static List<PlaceSuggestion> cities([Iterable<String> names = popularCities]) => [
        for (final name in names)
          if (senegalCityCoordinates[name] != null)
            PlaceSuggestion(
              location: GeoLocation(
                lat: senegalCityCoordinates[name]!.lat,
                lng: senegalCityCoordinates[name]!.lng,
                address: name,
                locality: name,
              ),
              title: name,
              subtitle: 'Ville',
              kind: PlaceKind.city,
            ),
      ];

  /// Minuscules sans accents ni tirets : « Thiès » et « thies » se valent.
  static String normalize(String text) {
    const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ-\'’';
    const to = 'aaaaaaceeeeiiiinooooouuuuyy   ';
    final buffer = StringBuffer();
    for (final char in text.toLowerCase().split('')) {
      final i = from.indexOf(char);
      buffer.write(i >= 0 ? to[i] : char);
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Villes dont le nom commence par la saisie.
  static List<PlaceSuggestion> matchingCities(String query) {
    final q = normalize(query);
    if (q.isEmpty) return const [];
    return cities(senegalCityCoordinates.keys.where((name) => normalize(name).startsWith(q)));
  }

  Future<List<PlaceSuggestion>> search(String query, {GeoLocation? near}) async {
    final text = query.trim();
    if (text.length < 2) return const [];

    final results = await Future.wait([
      _knownPlaces(text, near),
      _addresses(text),
    ]);
    final merged = <PlaceSuggestion>[...matchingCities(text).take(3)];
    for (final suggestion in [...results[0], ...results[1]]) {
      final duplicate = merged.any((other) =>
          normalize(other.title) == normalize(suggestion.title) ||
          other.location.distanceKm(suggestion.location) < 0.15);
      if (!duplicate) merged.add(suggestion);
    }
    return merged.take(12).toList();
  }

  Future<List<PlaceSuggestion>> _knownPlaces(String query, GeoLocation? near) async {
    try {
      final response = await (_client ?? ApiClient.instance).get('/places/search', query: {
        'q': query,
        if (near != null) ...{'lat': near.lat, 'lng': near.lng},
      }).timeout(const Duration(seconds: 8));
      final places = (response['places'] as List? ?? const []).cast<Map<String, dynamic>>();
      return [
        for (final place in places)
          () {
            final kind = _kindOf(place['kind'] as String?);
            final name = (place['name'] as String? ?? '').trim();
            final address = (place['address'] as String?)?.trim();
            final where = address != null && address.contains(',') ? address.split(',').last.trim() : null;
            return PlaceSuggestion(
              location: GeoLocation(
                lat: (place['lat'] as num).toDouble(),
                lng: (place['lng'] as num).toDouble(),
                address: address == null || address.isEmpty ? name : address,
                locality: name,
              ),
              title: name,
              subtitle: [_kindLabel(kind), if (where != null && where.isNotEmpty) where].join(' · '),
              kind: kind,
            );
          }(),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<List<PlaceSuggestion>> _addresses(String query) async {
    try {
      final found = await _mapService.searchAddress(query).timeout(const Duration(seconds: 8));
      return [
        for (final location in found.take(6))
          PlaceSuggestion(
            location: location,
            title: location.address.split(',').first.trim(),
            subtitle: location.address.contains(',')
                ? location.address.substring(location.address.indexOf(',') + 1).trim()
                : location.locality,
            kind: PlaceKind.address,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static PlaceKind _kindOf(String? kind) {
    switch (kind) {
      case 'gare_routiere':
        return PlaceKind.busStation;
      case 'peage':
        return PlaceKind.toll;
      case 'rond_point':
        return PlaceKind.roundabout;
      case 'station':
        return PlaceKind.fuelStation;
      default:
        return PlaceKind.address;
    }
  }

  static String _kindLabel(PlaceKind kind) {
    switch (kind) {
      case PlaceKind.busStation:
        return 'Gare routière';
      case PlaceKind.toll:
        return 'Péage';
      case PlaceKind.roundabout:
        return 'Rond-point';
      case PlaceKind.fuelStation:
        return 'Station-service';
      case PlaceKind.city:
        return 'Ville';
      case PlaceKind.address:
      case PlaceKind.recent:
        return 'Adresse';
    }
  }
}

/// Derniers lieux choisis, proposés en premier à la prochaine recherche.
class RecentPlaces {
  static const _key = 'recent_places_v1';
  static const _max = 6;

  static Future<List<PlaceSuggestion>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key) ?? const [];
      return [
        for (final entry in raw)
          () {
            final map = jsonDecode(entry) as Map<String, dynamic>;
            final location = GeoLocation(
              lat: (map['lat'] as num).toDouble(),
              lng: (map['lng'] as num).toDouble(),
              address: map['address'] as String? ?? '',
              locality: map['locality'] as String?,
            );
            return PlaceSuggestion(
              location: location,
              title: map['title'] as String? ?? location.shortLabel,
              subtitle: location.address == map['title'] ? null : location.address,
              kind: PlaceKind.recent,
            );
          }(),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> add(GeoLocation location, {String? title}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final label = title ?? location.shortLabel;
      final entry = jsonEncode({
        'lat': location.lat,
        'lng': location.lng,
        'address': location.address,
        'locality': location.locality,
        'title': label,
      });
      final kept = (prefs.getStringList(_key) ?? const []).where((other) {
        try {
          final map = jsonDecode(other) as Map<String, dynamic>;
          final far = haversineKm(location.lat, location.lng, (map['lat'] as num).toDouble(), (map['lng'] as num).toDouble()) > 0.15;
          return far && map['title'] != label;
        } catch (_) {
          return false;
        }
      });
      await prefs.setStringList(_key, [entry, ...kept].take(_max).toList());
    } catch (_) {}
  }
}
