import 'dart:math' as math;

/// Point géographique avec adresse lisible — utilisé pour `origin`,
/// `destination` et `waypoints` des trajets et des demandes (Phase 1/4).
class GeoLocation {
  final double lat;
  final double lng;
  final String address;

  /// Ville / quartier du point (« Rufisque »), quand le géocodage le fournit :
  /// sert de libellé court, l'adresse complète restant affichée en détail.
  final String? locality;

  const GeoLocation({required this.lat, required this.lng, required this.address, this.locality});

  /// Libellé court : la localité si connue, sinon le premier élément de
  /// l'adresse (« Gare routière, Thiès, … » → « Gare routière »).
  String get shortLabel {
    if (locality != null && locality!.trim().isNotEmpty) return locality!.trim();
    final first = address.split(',').first.trim();
    return first.isEmpty ? address : first;
  }

  factory GeoLocation.fromMap(Map<String, dynamic> map) {
    return GeoLocation(
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      address: map['address'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {'lat': lat, 'lng': lng, 'address': address};

  double distanceKm(GeoLocation other) => haversineKm(lat, lng, other.lat, other.lng);
}

/// Distance orthodromique (grand cercle) entre deux points, en kilomètres.
/// Fonction pure — c'est la brique la plus critique du matching (Phase 4),
/// testée indépendamment de tout état Firestore/UI.
double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusKm = 6371.0;
  final dLat = _degToRad(lat2 - lat1);
  final dLng = _degToRad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_degToRad(lat1)) *
          math.cos(_degToRad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusKm * c;
}

double _degToRad(double deg) => deg * math.pi / 180.0;
