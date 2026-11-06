import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_chauffeur/features/trips/widgets/passenger_tile.dart';
import 'package:fojem_chauffeur/models/booking.dart';
import 'package:google_fonts/google_fonts.dart';

Booking _booking({String status = 'confirmed', bool boarded = false}) => Booking.fromApiJson({
      'id': 'b1',
      'trip_id': 't1',
      'status': status,
      'passenger': {'full_name': 'Awa Ndiaye', 'phone_number': '+221770000000'},
      if (boarded) 'started_at': '2026-11-10T08:33:00Z',
    });

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<List<Booking>> pump(
    WidgetTester tester,
    Booking booking, {
    bool tripActive = true,
    DateTime? waitUntil,
  }) async {
    final declared = <Booking>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PassengerTile(
          booking: booking,
          tripId: 't1',
          waitUntil: waitUntil,
          onMarkAbsent: tripActive ? (b) async => declared.add(b) : null,
        ),
      ),
    ));
    return declared;
  }

  testWidgets('a confirmed passenger not yet on board can be declared absent', (tester) async {
    final declared = await pump(tester, _booking());
    await tester.tap(find.text('Absent'));
    await tester.pump();
    expect(declared.single.id, 'b1');
  });

  testWidgets('no « Absent » for a passenger on board, not accepted, or on a finished trip', (tester) async {
    await pump(tester, _booking(boarded: true));
    expect(find.textContaining('Absent'), findsNothing);

    await pump(tester, _booking(status: 'pending_driver'));
    expect(find.textContaining('Absent'), findsNothing);

    await pump(tester, _booking(), tripActive: false);
    expect(find.textContaining('Absent'), findsNothing);
  });

  testWidgets('during the wait the button counts down and stays disabled', (tester) async {
    final declared = await pump(tester, _booking(), waitUntil: DateTime.now().add(const Duration(minutes: 2)));
    expect(find.textContaining('Absent · '), findsOneWidget);

    await tester.tap(find.textContaining('Absent · '));
    await tester.pump();
    expect(declared, isEmpty);
  });
}
