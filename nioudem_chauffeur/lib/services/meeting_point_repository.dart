import 'package:flutter/material.dart';
import '../core/geo/geo_location.dart';
import '../core/network/api_client.dart';

/// Lieu à proposer comme arrêt au chauffeur qui publie : un arrêt que
/// d'autres trajets utilisent déjà, ou un lieu connu (gare routière, péage…).
class MeetingPointSuggestion {
  final String name;
  final String? address;

  /// `frequent`, `gare_routiere`, `station`, `peage` ou `rond_point`.
  final String kind;
  final double lat;
  final double lng;
  final int kmFromStart;
  final int tripsCount;
  final int passengersCount;

  const MeetingPointSuggestion({
    required this.name,
    this.address,
    required this.kind,
    required this.lat,
    required this.lng,
    required this.kmFromStart,
    this.tripsCount = 0,
    this.passengersCount = 0,
  });

  factory MeetingPointSuggestion.fromJson(Map<String, dynamic> json) => MeetingPointSuggestion(
        name: json['name'] as String? ?? '',
        address: json['address'] as String?,
        kind: json['kind'] as String? ?? '',
        lat: double.tryParse('${json['lat']}') ?? 0,
        lng: double.tryParse('${json['lng']}') ?? 0,
        kmFromStart: int.tryParse('${json['km_from_start'] ?? 0}') ?? 0,
        tripsCount: int.tryParse('${json['trips_count'] ?? 0}') ?? 0,
        passengersCount: int.tryParse('${json['passengers_count'] ?? 0}') ?? 0,
      );

  bool get isFrequent => kind == 'frequent';

  /// Le point de rendez-vous qu'il devient : son nom sert de libellé court.
  GeoLocation toGeoLocation() => GeoLocation(lat: lat, lng: lng, address: address ?? name, locality: name);

  IconData get icon => switch (kind) {
        'frequent' => Icons.groups_rounded,
        'gare_routiere' => Icons.directions_bus_rounded,
        'station' => Icons.local_gas_station_rounded,
        'peage' => Icons.toll_rounded,
        'rond_point' => Icons.roundabout_right_rounded,
        _ => Icons.place_rounded,
      };

  /// « Déjà utilisé par 3 trajets · 5 passagers », « Station-service · Thiaroye ».
  String get detail {
    if (isFrequent) {
      final trips = 'Déjà utilisé par $tripsCount trajet${tripsCount > 1 ? 's' : ''}';
      return passengersCount > 0 ? '$trips · $passengersCount passager${passengersCount > 1 ? 's' : ''}' : trips;
    }
    final label = switch (kind) {
      'gare_routiere' => 'Gare routière',
      'station' => 'Station-service',
      'peage' => 'Péage',
      'rond_point' => 'Rond-point',
      _ => 'Lieu connu',
    };
    final place = address != null && address!.startsWith('$name, ') ? address!.substring(name.length + 2) : null;
    return place != null ? '$label · $place' : label;
  }
}

class MeetingPointRepository {
  final ApiClient _client;

  MeetingPointRepository({ApiClient? client}) : _client = client ?? ApiClient();

  /// Arrêts à suggérer sur la route qui passe par [points] (départ, arrêts
  /// déjà choisis, arrivée), dans l'ordre de la route.
  Future<List<MeetingPointSuggestion>> suggestions(List<GeoLocation> points) async {
    final body = await _client.get('/meeting-points/suggestions', query: {
      'points': points.map((p) => '${p.lat.toStringAsFixed(6)},${p.lng.toStringAsFixed(6)}').join(';'),
    });
    return [
      for (final item in (body['suggestions'] as List? ?? const []))
        if (item is Map<String, dynamic>) MeetingPointSuggestion.fromJson(item),
    ];
  }
}
