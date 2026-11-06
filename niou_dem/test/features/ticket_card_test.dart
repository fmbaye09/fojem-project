import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_passager/features/booking/widgets/ticket_card.dart';
import 'package:fojem_passager/models/booking.dart';
import 'package:fojem_passager/models/trip.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

final _trip = Trip.fromApi({
  'id': 't1',
  'status': 'in_progress',
  'origin_name': 'Dakar',
  'destination_name': 'Thiès',
  'scheduled_at': '2026-11-10T08:30:00Z',
  'price_per_seat': '3000.00',
  'seats_available': 2,
});

Booking _booking({bool boarded = false}) => Booking.fromApi({
      'id': 'b1',
      'trip_id': 't1',
      'status': 'confirmed',
      'departure_code': '4821',
      if (boarded) 'started_at': '2026-11-10T08:33:00Z',
    }, trip: _trip);

Future<void> _pump(WidgetTester tester, Booking booking) => tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: TicketCard(booking: booking, trip: _trip))),
    ));

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('before boarding the QR code is shown, with nothing to fold', (tester) async {
    await _pump(tester, _booking());
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Afficher mon billet'), findsNothing);
  });

  testWidgets('once validated on board the ticket folds and can be reopened', (tester) async {
    await _pump(tester, _booking(boarded: true));
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('Le chauffeur a validé votre présence. Bon voyage !'), findsOneWidget);

    await tester.tap(find.text('Afficher mon billet'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);

    await tester.tap(find.text('Masquer mon billet'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
