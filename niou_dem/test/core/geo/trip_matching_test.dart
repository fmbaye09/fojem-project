import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_passager/core/geo/geo_location.dart';
import 'package:fojem_passager/core/geo/trip_matching.dart';

const dakar = GeoLocation(lat: 14.6928, lng: -17.4467, address: 'Dakar');
const thies = GeoLocation(lat: 14.7910, lng: -16.9359, address: 'Thiès');
const mbour = GeoLocation(lat: 14.4198, lng: -16.9646, address: 'Mbour');
const saintLouis = GeoLocation(lat: 16.0179, lng: -16.4896, address: 'Saint-Louis');
const kaolack = GeoLocation(lat: 14.1652, lng: -16.0726, address: 'Kaolack');

void main() {
  group('matchTripPath — correspondance exacte', () {
    test('matches when desired origin/destination equal trip origin/destination', () {
      final result = matchTripPath(
        tripOrigin: dakar,
        tripWaypoints: const [],
        tripDestination: thies,
        desiredOrigin: dakar,
        desiredDestination: thies,
      );
      expect(result.matches, isTrue);
      expect(result.originDistanceKm, closeTo(0, 0.01));
      expect(result.destinationDistanceKm, closeTo(0, 0.01));
    });
  });

  group('matchTripPath — proximité (pas de correspondance exacte de ville)', () {
    test('matches a desired destination close to a waypoint, not just the endpoints', () {
      // Trajet Dakar -> Saint-Louis passant par Thiès. Une demande
      // Dakar -> Mbour (proche de Thiès, ~40km) ne doit PAS matcher à 5km,
      // mais une demande Dakar -> Thiès doit matcher sur le waypoint.
      final result = matchTripPath(
        tripOrigin: dakar,
        tripWaypoints: const [thies],
        tripDestination: saintLouis,
        desiredOrigin: dakar,
        desiredDestination: thies,
        thresholdKm: 5,
      );
      expect(result.matches, isTrue);
    });

    test('rejects a destination too far from every point of the trip', () {
      final result = matchTripPath(
        tripOrigin: dakar,
        tripWaypoints: const [thies],
        tripDestination: saintLouis,
        desiredOrigin: dakar,
        desiredDestination: mbour, // ~40km de Thiès, hors seuil
        thresholdKm: 5,
      );
      expect(result.matches, isFalse);
    });

    test('accepts a farther destination when the threshold is widened', () {
      final result = matchTripPath(
        tripOrigin: dakar,
        tripWaypoints: const [thies],
        tripDestination: saintLouis,
        desiredOrigin: dakar,
        desiredDestination: mbour,
        thresholdKm: 50,
      );
      expect(result.matches, isTrue);
    });
  });

  group('matchTripPath — sens du trajet', () {
    test('rejects a request in the opposite direction of travel', () {
      // Trajet Dakar -> Kaolack. Demande Kaolack -> Dakar : même villes,
      // mauvais sens — ne doit pas matcher malgré des points proches.
      final result = matchTripPath(
        tripOrigin: dakar,
        tripWaypoints: const [],
        tripDestination: kaolack,
        desiredOrigin: kaolack,
        desiredDestination: dakar,
        thresholdKm: 5,
      );
      expect(result.matches, isFalse);
    });

    test('matches origin and destination on the same waypoint only for a degenerate short hop', () {
      final result = matchTripPath(
        tripOrigin: dakar,
        tripWaypoints: const [thies, kaolack],
        tripDestination: saintLouis,
        desiredOrigin: thies,
        desiredDestination: kaolack,
        thresholdKm: 5,
      );
      expect(result.matches, isTrue);
      expect(result.originDistanceKm, closeTo(0, 0.01));
      expect(result.destinationDistanceKm, closeTo(0, 0.01));
    });
  });

  group('matchTripPath — score', () {
    test('a closer match scores lower (better) than a farther one', () {
      final closeMatch = matchTripPath(
        tripOrigin: dakar,
        tripWaypoints: const [],
        tripDestination: thies,
        desiredOrigin: dakar,
        desiredDestination: thies,
        thresholdKm: 50,
      );
      final farMatch = matchTripPath(
        tripOrigin: dakar,
        tripWaypoints: const [],
        tripDestination: thies,
        desiredOrigin: dakar,
        desiredDestination: mbour,
        thresholdKm: 50,
      );
      expect(closeMatch.score, lessThan(farMatch.score));
    });
  });
}
