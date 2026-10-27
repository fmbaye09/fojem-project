import '../core/network/api_client.dart';
import '../models/vehicle.dart';

/// Véhicules — contre l'API Laravel (`/api/vehicles`).
///
/// Le backend permet désormais à un chauffeur de déclarer **plusieurs
/// véhicules** (ex. il alterne entre sa propre voiture et celle d'un
/// proche), chacun **immuable** une fois créé (`plate_number, brand, model,
/// color, seat_count` ne changent jamais après création — voir
/// `fojem_backend/README.md`, section "Vehicules"). Il n'y a donc plus
/// d'upsert : `POST /vehicles` crée toujours un nouveau véhicule, et
/// `GET /vehicles` (et non plus `/vehicles/mine`) retourne la liste complète
/// des véhicules du chauffeur connecté. Ce repository n'utilise pas
/// Firestore.
///
/// Le backend n'a pas de notion de `VehicleType`/nombre de sièges par type
/// (seul `seat_count`, un entier libre, existe côté table `vehicles`) : on
/// reconstruit un `VehicleType` approximatif à partir de `seat_count` pour
/// ne pas casser le reste de l'app (plan de sièges, etc.), et on envoie le
/// `seat_count` correspondant au type choisi à l'écran à la création.
class VehicleRepository {
  final ApiClient _client;

  VehicleRepository({ApiClient? client}) : _client = client ?? ApiClient();
  Vehicle _fromApiJson(Map<String, dynamic> json) {
    final seatCount = int.tryParse('${json['seat_count'] ?? ''}') ??
        VehicleType.septPlaces.passengerSeatCount;
    return Vehicle(
      id: json['id'] as String? ?? '',
      driverId: json['driver_id'] as String? ?? '',
      type: _typeForSeatCount(seatCount),
      brand: json['brand'] as String? ?? '',
      model: json['model'] as String? ?? '',
      color: json['color'] as String? ?? '',
      plateNumber: json['plate_number'] as String? ?? '',
    );
  }

  VehicleType _typeForSeatCount(int seatCount) {
    return VehicleType.values.firstWhere(
      (t) => t.passengerSeatCount == seatCount,
      orElse: () => VehicleType.septPlaces,
    );
  }

  /// Liste des véhicules déclarés par le chauffeur connecté (peut être
  /// vide — c'est le cas normal avant sa toute première déclaration).
  Future<List<Vehicle>> fetchAll() async {
    final body = await _client.get('/vehicles');
    final list = body['vehicles'] as List<dynamic>? ?? const [];
    return list.map((e) => _fromApiJson(e as Map<String, dynamic>)).toList();
  }

  /// Récupère un véhicule précis du chauffeur connecté par id. Pas
  /// d'endpoint `GET /vehicles/{id}` côté backend : on passe par la liste
  /// complète et on filtre.
  Future<Vehicle?> fetch(String vehicleId) async {
    if (vehicleId.isEmpty) return null;
    final vehicles = await fetchAll();
    for (final v in vehicles) {
      if (v.id == vehicleId) return v;
    }
    return null;
  }

  /// Crée un **nouveau** véhicule pour le chauffeur connecté (plus
  /// d'upsert : chaque appel ajoute une ligne distincte, immuable une fois
  /// créée). [driverId] n'est conservé que pour compatibilité avec les
  /// écrans existants, il n'est plus envoyé à l'API (scopée au token
  /// courant côté serveur).
  Future<Vehicle> create({
    required String driverId,
    required VehicleType type,
    required String brand,
    required String model,
    required String color,
    required String plateNumber,
  }) async {
    final body = await _client.post('/vehicles', data: {
      'plate_number': plateNumber,
      'brand': brand,
      'model': model,
      'color': color,
      'seat_count': type.passengerSeatCount,
    });
    final json = body['vehicle'] as Map<String, dynamic>;
    return _fromApiJson(json);
  }
}
