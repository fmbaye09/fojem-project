import 'dart:convert';

import 'trip.dart';
import 'trip_stop.dart';

/// Point de rendez-vous que le passager propose quand aucun arrêt du trajet
/// ne lui convient. Le backend l'a évalué (détour, heure, prix) ; le chauffeur
/// décide de l'ajouter à son trajet ou non.
class ProposedStop {
  /// Identifiant des arrêts « fictifs » qui le représentent avant son ajout.
  static const stopId = 'proposed';

  /// `boarding` (le passager monte ici) ou `alighting` (il descend ici).
  final String role;
  final String name;
  final String? address;
  final double lat;
  final double lng;

  /// Arrêts du trajet entre lesquels il se place.
  final String? afterStopId;

  /// Minutes de route en plus pour le chauffeur.
  final int detourMinutes;
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
    this.afterStopId,
    required this.detourMinutes,
    this.scheduledAt,
    required this.priceFromOrigin,
    this.insertedStopId,
  });

  bool get isBoarding => role == 'boarding';
  bool get isAdded => insertedStopId != null;

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
      afterStopId: raw['after_stop_id'] as String?,
      detourMinutes: int.tryParse('${raw['detour_minutes'] ?? 0}') ?? 0,
      scheduledAt: DateTime.tryParse('${raw['scheduled_at'] ?? ''}')?.toLocal(),
      priceFromOrigin: double.tryParse('${raw['price_from_origin'] ?? 0}') ?? 0,
      insertedStopId: raw['inserted_stop_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'role': role,
        'name': name,
        'address': address,
        'lat': lat,
        'lng': lng,
        'after_stop_id': afterStopId,
        'detour_minutes': detourMinutes,
        'scheduled_at': scheduledAt?.toUtc().toIso8601String(),
        'price_from_origin': priceFromOrigin,
      };

  /// Ce que `POST /bookings` attend : le backend réévalue le reste.
  Map<String, dynamic> toApi() => {
        'role': role,
        'name': name,
        if (address != null) 'address': address,
        'lat': lat,
        'lng': lng,
      };

  /// Passé d'écran en écran dans l'URL (choix des places, confirmation).
  String toQuery() => base64Url.encode(utf8.encode(jsonEncode(toJson())));

  static ProposedStop? fromQuery(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return fromJson(jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(value)))));
    } catch (_) {
      return null;
    }
  }

  /// Le point sous la forme d'un arrêt, pour l'afficher comme les autres. Sa
  /// position le range juste après l'arrêt qu'il suit : une montée doit
  /// précéder la descente, une descente suivre la montée.
  TripStop asTripStop([Trip? trip]) {
    final after = trip?.stopById(afterStopId)?.position ?? -1;
    return TripStop(
      id: stopId,
      position: isBoarding ? after : after + 1,
      name: name,
      address: address,
      lat: lat,
      lng: lng,
      scheduledAt: scheduledAt,
      priceFromOrigin: priceFromOrigin,
    );
  }
}
