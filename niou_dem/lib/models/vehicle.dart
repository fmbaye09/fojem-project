enum VehicleType { berline, septPlaces, suv, van9, minibus15 }

extension VehicleTypeX on VehicleType {
  String get label {
    switch (this) {
      case VehicleType.berline:
        return 'Berline';
      case VehicleType.septPlaces:
        return '7 places';
      case VehicleType.suv:
        return 'SUV';
      case VehicleType.van9:
        return 'Van 9 places';
      case VehicleType.minibus15:
        return 'Minibus 15 places';
    }
  }

  /// Nombre de places passagers (hors chauffeur), utilisé pour dimensionner
  /// le plan de sièges — voir `kVehicleSeatLayouts`.
  int get passengerSeatCount {
    switch (this) {
      case VehicleType.berline:
        return 4;
      case VehicleType.septPlaces:
        return 7;
      case VehicleType.suv:
        return 6;
      case VehicleType.van9:
        return 9;
      case VehicleType.minibus15:
        return 15;
    }
  }

  /// Type le plus proche d'un nombre de places brut (`vehicles.seat_count`
  /// côté backend, qui n'a pas d'enum de type de véhicule).
  static VehicleType nearestFor(int seatCount) {
    if (seatCount <= 4) return VehicleType.berline;
    if (seatCount <= 6) return VehicleType.suv;
    if (seatCount == 7) return VehicleType.septPlaces;
    if (seatCount <= 9) return VehicleType.van9;
    return VehicleType.minibus15;
  }
}

class Vehicle {
  final String id;
  final String driverId;
  final VehicleType type;
  final String brand;
  final String model;
  final String color;
  final String plateNumber;

  const Vehicle({
    required this.id,
    required this.driverId,
    required this.type,
    required this.brand,
    required this.model,
    required this.color,
    required this.plateNumber,
  });

  int get totalSeats => type.passengerSeatCount;
  String get typeLabel => type.label;

  /// Depuis la réponse API (`vehicles` : `id, driver_id, plate_number,
    factory Vehicle.fromApi(Map<String, dynamic> map) {
    final seatCount = int.tryParse('${map['seat_count'] ?? ''}') ?? 7;
    return Vehicle(
      id: map['id'] as String? ?? '',
      driverId: map['driver_id'] as String? ?? '',
      type: VehicleTypeX.nearestFor(seatCount),
      brand: map['brand'] as String? ?? '',
      model: map['model'] as String? ?? '',
      color: map['color'] as String? ?? '',
      plateNumber: map['plate_number'] as String? ?? '',
    );
  }
}
