import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_chauffeur/models/trip.dart';

Map<String, dynamic> _trip(Map<String, dynamic> extra) => {
      'id': 't1',
      'status': 'open',
      'scheduled_at': '2026-11-12T08:00:00Z',
      'price_per_seat': '2000.00',
      'seats_available': 2,
      ...extra,
    };

void main() {
  test('the published seat count comes from the server, not from the phone', () {
    final trip = Trip.fromApiJson(_trip({'seats_total': 4}), cached: {'seatsTotal': 7});
    expect(trip.seatsTotal, 4);
    expect(trip.availableSeats, 2);
  });

  test('older trips without a total fall back to the local cache, then to the free seats', () {
    expect(Trip.fromApiJson(_trip({}), cached: {'seatsTotal': 7}).seatsTotal, 7);
    expect(Trip.fromApiJson(_trip({})).seatsTotal, 2);
  });
}
