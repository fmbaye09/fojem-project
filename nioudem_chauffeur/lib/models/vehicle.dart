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

  factory Vehicle.fromMap(String id, Map<String, dynamic> map) {
    return Vehicle(
      id: id,
      driverId: map['driverId'] as String? ?? '',
      type: VehicleType.values.firstWhere(
        (t) => t.name == map['type'],
        orElse: () => VehicleType.septPlaces,
      ),
      brand: map['brand'] as String? ?? '',
      model: map['model'] as String? ?? '',
      color: map['color'] as String? ?? '',
      plateNumber: map['plateNumber'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'driverId': driverId,
      'type': type.name,
      'brand': brand,
      'model': model,
      'color': color,
      'plateNumber': plateNumber,
    };
  }
}
