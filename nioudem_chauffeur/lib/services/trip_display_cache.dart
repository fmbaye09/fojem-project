import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/geo/geo_location.dart';
import '../models/vehicle.dart';

/// Cache local (par appareil) des champs d'affichage d'un trajet que l'API
/// Laravel ne renvoie toujours pas — noms de ville, notes passagers, nombre
/// total de sièges (voir le commentaire en tête de `models/trip.dart`).
/// Rempli à la publication (`TripRepository.create`), lu à chaque
/// récupération de trajet.
///
/// Les coordonnées (`originLat/Lng`, `destinationLat/Lng`) stockées ici ne
/// sont plus qu'un simple cache de confort : `GET /trips/mine`/`GET
/// /trips/{id}` renvoient désormais `origin_lat/origin_lng/
/// destination_lat/destination_lng` directement (voir `Trip.fromApiJson`,
/// qui les priorise sur ces valeurs mises en cache). Elles ne sont donc
/// plus consultées en pratique pour les lat/lng, seulement conservées pour
/// compatibilité descendante si l'API venait à ne pas les fournir.
///
/// Ce n'est pas une source de vérité : si l'app est réinstallée ou le
/// trajet consulté depuis un autre appareil, les champs qui en dépendent
/// encore (ville, notes, nombre de sièges) sont simplement absents (pas de
/// donnée inventée pour compenser).
class TripDisplayCache {
  static const _prefsKey = 'fojem_trip_display_cache_v1';

  Future<void> save(
    String tripId, {
    required String departure,
    required String arrival,
    required String departureAddress,
    required String arrivalAddress,
    required GeoLocation origin,
    required GeoLocation destination,
    required int seatsTotal,
    required int estimatedMinutes,
    required VehicleType vehicleType,
    String? notes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final store = _readStore(prefs);
    store[tripId] = {
      'departure': departure,
      'arrival': arrival,
      'departureAddress': departureAddress,
      'arrivalAddress': arrivalAddress,
      'originLat': origin.lat,
      'originLng': origin.lng,
      'destinationLat': destination.lat,
      'destinationLng': destination.lng,
      'seatsTotal': seatsTotal,
      'estimatedMinutes': estimatedMinutes,
      'vehicleType': vehicleType.name,
      'notes': notes,
    };
    await prefs.setString(_prefsKey, jsonEncode(store));
  }

  Future<Map<String, dynamic>?> read(String tripId) async {
    final prefs = await SharedPreferences.getInstance();
    return _readStore(prefs)[tripId] as Map<String, dynamic>?;
  }

  Map<String, dynamic> _readStore(SharedPreferences prefs) {
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }
}
