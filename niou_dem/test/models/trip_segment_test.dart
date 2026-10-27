import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_passager/models/trip.dart';

Map<String, dynamic> _stop(String id, int position, String name, String time, num price) => {
      'id': id,
      'position': position,
      'name': name,
      'address': '$name, gare',
      'lat': 14.7,
      'lng': -17.2,
      'scheduled_at': time,
      'price_from_origin': '$price.00',
    };

Map<String, dynamic> _tripJson({Map<String, dynamic>? match}) => {
      'id': 'trip-1',
      'status': 'open',
      'origin_name': 'Dakar',
      'destination_name': 'Thiès',
      'scheduled_at': '2026-11-02T08:30:00Z',
      'price_per_seat': '3000.00',
      'seats_available': 3,
      'stops': [
        _stop('s0', 0, 'Dakar', '2026-11-02T08:30:00Z', 0),
        _stop('s1', 1, 'Rufisque', '2026-11-02T09:05:00Z', 1000),
        _stop('s2', 2, 'Thiès', '2026-11-02T10:10:00Z', 3000),
      ],
      if (match != null) 'match': match,
    };

void main() {
  test('reads stops and derives addresses and duration from them', () {
    final trip = Trip.fromApi(_tripJson());

    expect(trip.stops.map((s) => s.name), ['Dakar', 'Rufisque', 'Thiès']);
    expect(trip.departureAddress, 'Dakar, gare');
    expect(trip.arrivalAddress, 'Thiès, gare');
    expect(trip.estimatedDuration, const Duration(minutes: 100));
  });

  test('without a match the segment is the whole trip', () {
    final seg = Trip.fromApi(_tripJson()).segment();

    expect(seg.boarding?.name, 'Dakar');
    expect(seg.alighting?.name, 'Thiès');
    expect(seg.pricePerSeat, 3000);
  });

  test('a search match proposes the passenger segment and its price', () {
    final trip = Trip.fromApi(_tripJson(match: {
      'boarding_stop': _stop('s1', 1, 'Rufisque', '2026-11-02T09:05:00Z', 1000),
      'alighting_stop': _stop('s2', 2, 'Thiès', '2026-11-02T10:10:00Z', 3000),
      'boarding_distance_m': 969,
      'alighting_distance_m': 0,
      'segment_price': '2000.00',
    }));

    final seg = trip.segment();
    expect(seg.boarding?.name, 'Rufisque');
    expect(seg.pricePerSeat, 2000);
    expect(boardingTime(trip), DateTime.utc(2026, 11, 2, 9, 5).toLocal());
    expect(tripDetailLocation(trip), '/trip/trip-1?board=s1&alight=s2');
  });

  test('explicit stop ids override the match', () {
    final seg = Trip.fromApi(_tripJson()).segment(boardingStopId: 's0', alightingStopId: 's1');

    expect(seg.alighting?.name, 'Rufisque');
    expect(seg.pricePerSeat, 1000);
  });

  test('formatDistanceFromYou', () {
    expect(formatDistanceFromYou(80), 'sur place');
    expect(formatDistanceFromYou(420), 'à 400 m');
    expect(formatDistanceFromYou(1240), 'à 1,2 km');
    expect(formatDistanceFromYou(23400), 'à 23 km');
  });
}
