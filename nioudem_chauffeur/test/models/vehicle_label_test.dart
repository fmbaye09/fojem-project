import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_chauffeur/models/vehicle.dart';

Vehicle _vehicle(VehicleType type) => Vehicle(
      id: 'v1',
      driverId: 'd1',
      type: type,
      brand: 'Toyota',
      model: 'Hiace',
      color: 'Blanc',
      plateNumber: 'DK-1234-AB',
    );

void main() {
  test('the seat count is not repeated when the type already names it', () {
    expect(_vehicle(VehicleType.septPlaces).capacityLabel, '7 places');
    expect(_vehicle(VehicleType.van9).capacityLabel, 'Van 9 places');
    expect(_vehicle(VehicleType.septPlaces).summary, '7 places · DK-1234-AB');
  });

  test('other types show their seat count', () {
    expect(_vehicle(VehicleType.berline).capacityLabel, 'Berline · 4 places');
    expect(_vehicle(VehicleType.suv).summary, 'SUV · 6 places · DK-1234-AB');
  });
}
