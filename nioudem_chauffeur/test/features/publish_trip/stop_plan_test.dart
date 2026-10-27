import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_chauffeur/core/geo/geo_location.dart';
import 'package:fojem_chauffeur/features/publish_trip/stop_plan.dart';
import 'package:fojem_chauffeur/services/map/map_service.dart';

void main() {
  const dakar = GeoLocation(lat: 14.68, lng: -17.438, address: 'Gare des Pompiers', locality: 'Dakar');
  const rufisque = GeoLocation(lat: 14.716, lng: -17.273, address: 'Péage', locality: 'Rufisque');
  const thies = GeoLocation(lat: 14.791, lng: -16.926, address: 'Gare routière', locality: 'Thiès');
  final departure = DateTime(2026, 11, 2, 8, 30);

  group('planStops', () {
    test('uses road legs for times and pro rata prices', () {
      final stops = planStops(
        points: [dakar, rufisque, thies],
        legs: const [
          RouteLeg(distanceKm: 25, duration: Duration(minutes: 30)),
          RouteLeg(distanceKm: 50, duration: Duration(minutes: 60)),
        ],
        departure: departure,
        fullPrice: 3000,
      );

      expect(stops.map((s) => s.scheduledAt), [
        departure,
        departure.add(const Duration(minutes: 30)),
        departure.add(const Duration(minutes: 90)),
      ]);
      // 25 km sur 75 km → 1 000 FCFA (arrondi à 50).
      expect(stops.map((s) => s.priceFromOrigin), [0, 1000, 3000]);
      expect(stops[1].priceEdited, isFalse);
    });

    test('keeps a driver-adjusted price', () {
      final stops = planStops(
        points: [dakar, rufisque, thies],
        legs: const [
          RouteLeg(distanceKm: 25, duration: Duration(minutes: 30)),
          RouteLeg(distanceKm: 50, duration: Duration(minutes: 60)),
        ],
        departure: departure,
        fullPrice: 3000,
        priceOverrides: {1: 1500},
      );

      expect(stops[1].priceFromOrigin, 1500);
      expect(stops[1].priceEdited, isTrue);
    });

    test('estimates times and prices when the route is unavailable', () {
      final stops = planStops(
        points: [dakar, rufisque, thies],
        legs: const [],
        departure: departure,
        fullPrice: 3000,
      );

      expect(stops.first.priceFromOrigin, 0);
      expect(stops.last.priceFromOrigin, 3000);
      expect(stops[1].priceFromOrigin, inExclusiveRange(0, 3000));
      expect(stops[1].priceFromOrigin % 50, 0);
      expect(stops[1].scheduledAt.isAfter(departure), isTrue);
      expect(stops[2].scheduledAt.isAfter(stops[1].scheduledAt), isTrue);
    });

    test('sends a short name and the precise address', () {
      final stop = planStops(
        points: [rufisque, thies],
        legs: const [],
        departure: departure,
        fullPrice: 2000,
      ).first;

      expect(stop.toApi()['name'], 'Rufisque');
      expect(stop.toApi()['address'], 'Péage');
    });
  });

  test('orderAlongRoute sorts stops from the departure', () {
    const pout = GeoLocation(lat: 14.77, lng: -17.06, address: 'Pout', locality: 'Pout');
    expect(orderAlongRoute(dakar, [pout, rufisque]), [rufisque, pout]);
  });
}
