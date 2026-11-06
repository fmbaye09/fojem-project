/// Point de rendez-vous proposé par un passager quand aucun arrêt du trajet
/// ne lui convient. L'accepter ajoute l'arrêt au trajet, au prix d'un détour.
class ProposedStop {
  /// `boarding` (il monte ici) ou `alighting` (il descend ici).
  final String role;
  final String name;
  final String? address;
  final double lat;
  final double lng;

  /// Minutes de route en plus pour le chauffeur (estimées par le backend).
  final int detourMinutes;

  /// Heure de passage estimée à ce point.
  final DateTime? scheduledAt;
  final double priceFromOrigin;

  /// Arrêt créé quand le chauffeur a accepté ; null tant qu'il n'a pas répondu.
  final String? insertedStopId;

  const ProposedStop({
    required this.role,
    required this.name,
    this.address,
    required this.lat,
    required this.lng,
    required this.detourMinutes,
    this.scheduledAt,
    required this.priceFromOrigin,
    this.insertedStopId,
  });

  bool get isBoarding => role == 'boarding';
  bool get isAdded => insertedStopId != null;

  /// Adresse si elle apporte une précision, sinon le nom.
  String get displayAddress => (address != null && address!.trim().isNotEmpty) ? address! : name;

  static ProposedStop? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final lat = double.tryParse('${raw['lat']}');
    final lng = double.tryParse('${raw['lng']}');
    if (lat == null || lng == null) return null;
    return ProposedStop(
      role: raw['role'] == 'alighting' ? 'alighting' : 'boarding',
      name: raw['name'] as String? ?? 'Arrêt proposé',
      address: raw['address'] as String?,
      lat: lat,
      lng: lng,
      detourMinutes: int.tryParse('${raw['detour_minutes'] ?? 0}') ?? 0,
      scheduledAt: DateTime.tryParse('${raw['scheduled_at'] ?? ''}')?.toLocal(),
      priceFromOrigin: double.tryParse('${raw['price_from_origin'] ?? 0}') ?? 0,
      insertedStopId: raw['inserted_stop_id'] as String?,
    );
  }
}
