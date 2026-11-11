import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_passager/models/trip.dart';
import 'package:fojem_passager/services/map/place_search.dart';

void main() {
  test('accents, case and hyphens do not matter when matching a place', () {
    expect(PlaceSearch.normalize('Thiès'), 'thies');
    expect(PlaceSearch.normalize('  Saint-Louis '), 'saint louis');
    expect(PlaceSearch.normalize('Gare  routière'), 'gare routiere');
  });

  test('cities are suggested from the first letters typed', () {
    expect(PlaceSearch.matchingCities('thi').map((c) => c.title), contains('Thiès'));
    expect(PlaceSearch.matchingCities('SAINT').map((c) => c.title), contains('Saint-Louis'));
    expect(PlaceSearch.matchingCities(''), isEmpty);
    // Une ville choisie porte son nom comme libellé court.
    expect(PlaceSearch.matchingCities('mbo').first.location.shortLabel, 'Mbour');
  });

  test('the popular cities are offered before any search', () {
    final titles = PlaceSearch.cities().map((c) => c.title).toList();
    expect(titles.first, 'Dakar');
    expect(titles, containsAll(['Thiès', 'Touba', 'Saint-Louis']));
  });

  test('a trip reads its published seat count from the server', () {
    final trip = Trip.fromApi({
      'id': 't1',
      'status': 'open',
      'scheduled_at': '2026-11-12T08:00:00Z',
      'price_per_seat': '2000.00',
      'seats_available': 2,
      'seats_total': 4,
    });
    expect(trip.seatsTotal, 4);
    expect(trip.availableSeats, 2);
  });
}
