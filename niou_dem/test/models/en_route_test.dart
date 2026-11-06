import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_passager/core/widgets/trip_card.dart';
import 'package:fojem_passager/models/trip.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

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

Map<String, dynamic> _tripJson(Map<String, dynamic> match) => {
      'id': 'trip-1',
      'status': 'in_progress',
      'origin_name': 'Dakar',
      'destination_name': 'Thiès',
      'scheduled_at': '2026-11-02T08:30:00Z',
      'price_per_seat': '3000.00',
      'seats_available': 2,
      'stops': [
        _stop('s0', 0, 'Dakar', '2026-11-02T08:30:00Z', 0),
        _stop('s1', 1, 'Rufisque', '2026-11-02T09:05:00Z', 1000),
        _stop('s2', 2, 'Thiès', '2026-11-02T10:10:00Z', 3000),
      ],
      'match': match,
    };

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('fr_FR');
  });

  final enRouteMatch = {
    'boarding_stop': _stop('s1', 1, 'Rufisque', '2026-11-02T09:05:00Z', 1000),
    'alighting_stop': _stop('s2', 2, 'Thiès', '2026-11-02T10:10:00Z', 3000),
    'boarding_distance_m': 900,
    'alighting_distance_m': null,
    'segment_price': '2000.00',
    'en_route': true,
    'boarding_eta': '2026-11-02T09:12:00Z',
  };

  test('a trip on the road says when it passes the boarding stop', () {
    final match = Trip.fromApi(_tripJson(enRouteMatch)).match!;
    expect(match.enRoute, isTrue);
    expect(match.boardingEta, DateTime.utc(2026, 11, 2, 9, 12).toLocal());

    final notEnRoute = Trip.fromApi(_tripJson({...enRouteMatch, 'en_route': false, 'boarding_eta': null})).match!;
    expect(notEnRoute.enRoute, isFalse);
    expect(notEnRoute.boardingEta, isNull);
  });

  testWidgets('the card shows an en-route badge', (tester) async {
    final trip = Trip.fromApi(_tripJson(enRouteMatch));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TripCard(trip: trip, layout: TripCardLayout.schedule, onTap: () {})),
    ));

    final eta = DateTime.utc(2026, 11, 2, 9, 12).toLocal();
    final hhmm = '${eta.hour.toString().padLeft(2, '0')}:${eta.minute.toString().padLeft(2, '0')}';
    expect(find.text('En route · passe à Rufisque vers $hhmm'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
