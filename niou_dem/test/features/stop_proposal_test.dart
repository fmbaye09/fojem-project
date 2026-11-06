import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_passager/features/booking/widgets/propose_stop_card.dart';
import 'package:fojem_passager/features/booking/widgets/ticket_card.dart';
import 'package:fojem_passager/models/booking.dart';
import 'package:fojem_passager/models/proposed_stop.dart';
import 'package:fojem_passager/models/trip.dart';
import 'package:google_fonts/google_fonts.dart';

final _trip = Trip.fromApi({
  'id': 't1',
  'status': 'open',
  'origin_name': 'Dakar',
  'destination_name': 'Thiès',
  'scheduled_at': '2026-11-10T08:30:00Z',
  'price_per_seat': '3000.00',
  'seats_available': 3,
  'stops': [
    {'id': 's0', 'position': 0, 'name': 'Dakar', 'lat': 14.68, 'lng': -17.438, 'scheduled_at': '2026-11-10T08:30:00Z', 'price_from_origin': '0.00'},
    {'id': 's1', 'position': 1, 'name': 'Rufisque', 'lat': 14.716, 'lng': -17.273, 'scheduled_at': '2026-11-10T09:00:00Z', 'price_from_origin': '1500.00'},
    {'id': 's2', 'position': 2, 'name': 'Thiès', 'lat': 14.791, 'lng': -16.926, 'scheduled_at': '2026-11-10T10:00:00Z', 'price_from_origin': '3000.00'},
  ],
});

ProposedStop _mbao({String role = 'boarding'}) => ProposedStop.fromJson({
      'role': role,
      'name': 'Mbao',
      'address': 'Station Mbao',
      'lat': 14.713,
      'lng': -17.3555,
      'after_stop_id': 's0',
      'detour_minutes': 6,
      'scheduled_at': '2026-11-10T08:45:00Z',
      'price_from_origin': '700.00',
    })!;

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('a proposal survives the trip through the booking screens', () {
    final back = ProposedStop.fromQuery(_mbao().toQuery())!;
    expect(back.name, 'Mbao');
    expect(back.afterStopId, 's0');
    expect(back.detourMinutes, 6);
    expect(back.priceFromOrigin, 700);
    expect(ProposedStop.fromQuery('pas du base64'), isNull);
  });

  test('a proposed boarding point replaces the boarding stop and sets the price', () {
    final segment = _trip.segment(proposal: _mbao());
    expect(segment.boarding!.name, 'Mbao');
    expect(segment.alighting!.name, 'Thiès');
    expect(segment.pricePerSeat, 2300);
    // Le backend reçoit le point proposé, pas un faux identifiant d'arrêt.
    expect(segment.boardingStopId, isNull);
    expect(segment.query, 'alight=s2');
  });

  test('the other end stays on the right side of the proposed point', () {
    // Descendre à Mbao, entre Dakar et Rufisque, en montant à Rufisque : impossible.
    final segment = _trip.segment(boardingStopId: 's1', proposal: _mbao(role: 'alighting'));
    expect(segment.boarding!.name, 'Dakar');
    expect(segment.alighting!.name, 'Mbao');
    expect(segment.pricePerSeat, 700);
  });

  test('a pending booking shows the proposed point as its meeting point', () {
    final booking = Booking.fromApi({
      'id': 'b1',
      'trip_id': 't1',
      'status': 'pending_driver',
      'boarding_stop': null,
      'alighting_stop': {'id': 's2', 'position': 2, 'name': 'Thiès', 'lat': 14.791, 'lng': -16.926},
      'proposed_stop': _mbao().toJson(),
    }, trip: _trip);
    expect(booking.proposesNewStop, isTrue);
    expect(booking.boardingStop!.name, 'Mbao');
    expect(booking.boardingStop!.displayAddress, 'Station Mbao');
  });

  testWidgets('the pending ticket says the driver must accept the new stop', (tester) async {
    final booking = Booking.fromApi({
      'id': 'b1',
      'trip_id': 't1',
      'status': 'pending_driver',
      'proposed_stop': _mbao().toJson(),
    }, trip: _trip);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: TicketCard(booking: booking, trip: _trip))),
    ));
    expect(find.textContaining('Vous avez proposé de monter à Mbao'), findsOneWidget);
  });

  testWidgets('the trip detail offers to propose a point, then shows its cost', (tester) async {
    var proposed = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProposeStopCard(proposal: null, onPropose: () => proposed++, onClear: () {}),
      ),
    ));
    await tester.tap(find.text('Aucun arrêt ne vous convient ?'));
    expect(proposed, 1);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ProposeStopCard(proposal: _mbao(), onPropose: () {}, onClear: () {})),
    ));
    expect(find.text('Vous montez à Mbao'), findsOneWidget);
    expect(find.textContaining('environ 6 min de détour pour le chauffeur, qui doit accepter ce nouvel arrêt'), findsOneWidget);
  });
}
