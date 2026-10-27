import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_passager/core/geo/geo_location.dart';

void main() {
  group('haversineKm', () {
    test('distance from a point to itself is zero', () {
      expect(haversineKm(14.6928, -17.4467, 14.6928, -17.4467), closeTo(0, 0.001));
    });

    test('Dakar to Thiès is approximately 65-75 km in a straight line', () {
      final d = haversineKm(14.6928, -17.4467, 14.7910, -16.9359);
      expect(d, greaterThan(50));
      expect(d, lessThan(80));
    });

    test('is symmetric', () {
      final d1 = haversineKm(14.6928, -17.4467, 16.0179, -16.4896);
      final d2 = haversineKm(16.0179, -16.4896, 14.6928, -17.4467);
      expect(d1, closeTo(d2, 0.0001));
    });

    test('1 degree of latitude is approximately 111 km', () {
      final d = haversineKm(0, 0, 1, 0);
      expect(d, closeTo(111.2, 1.0));
    });
  });

  group('GeoLocation.distanceKm', () {
    test('matches the free-function haversine result', () {
      const a = GeoLocation(lat: 14.6928, lng: -17.4467, address: 'Dakar');
      const b = GeoLocation(lat: 14.7910, lng: -16.9359, address: 'Thiès');
      expect(a.distanceKm(b), closeTo(haversineKm(a.lat, a.lng, b.lat, b.lng), 0.0001));
    });
  });
}
