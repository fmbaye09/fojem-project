import '../core/geo/geo_location.dart';

/// Point de rendez-vous fixé par le chauffeur (départ, arrêt intermédiaire
/// ou arrivée). Les passagers montent et descendent uniquement à ces points :
/// c'est le passager qui s'y rend, le chauffeur ne fait pas de détour.
class TripStop {
  final String id;

  /// 0 = départ, dernier = arrivée.
  final int position;

  /// Libellé court affiché dans les listes (« Rufisque »).
  final String name;

  /// Adresse précise pour trouver le point (« Péage de Rufisque »).
  final String? address;
  final double lat;
  final double lng;
  final DateTime? scheduledAt;

  /// Prix par place depuis le départ : un tronçon i → j coûte
  /// `priceFromOrigin[j] - priceFromOrigin[i]`.
  final double priceFromOrigin;

  const TripStop({
    required this.id,
    required this.position,
    required this.name,
    this.address,
    required this.lat,
    required this.lng,
    this.scheduledAt,
    required this.priceFromOrigin,
  });

  GeoLocation get location => GeoLocation(lat: lat, lng: lng, address: address ?? name);

  /// Adresse si elle apporte une précision, sinon le nom.
  String get displayAddress => (address != null && address!.trim().isNotEmpty) ? address! : name;

  factory TripStop.fromJson(Map<String, dynamic> json) {
    return TripStop(
      id: json['id'] as String? ?? '',
      position: int.tryParse('${json['position'] ?? 0}') ?? 0,
      name: json['name'] as String? ?? '',
      address: json['address'] as String?,
      lat: double.tryParse('${json['lat'] ?? ''}') ?? 0,
      lng: double.tryParse('${json['lng'] ?? ''}') ?? 0,
      scheduledAt: DateTime.tryParse('${json['scheduled_at'] ?? ''}')?.toLocal(),
      priceFromOrigin: double.tryParse('${json['price_from_origin'] ?? 0}') ?? 0,
    );
  }

  static List<TripStop> listFromJson(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map<String, dynamic>) TripStop.fromJson(item),
    ]..sort((a, b) => a.position.compareTo(b.position));
  }
}
