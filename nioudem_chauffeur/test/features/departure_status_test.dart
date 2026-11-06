import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_chauffeur/core/widgets/countdown.dart';
import 'package:fojem_chauffeur/features/trips/departure_status.dart';
import 'package:fojem_chauffeur/models/booking.dart';
import 'package:fojem_chauffeur/models/trip.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

final _departure = DateTime.utc(2026, 11, 10, 8, 30);

Map<String, dynamic> _stop(String id, int position, String name, DateTime at, {DateTime? waitUntil}) => {
      'id': id,
      'position': position,
      'name': name,
      'lat': 14.7,
      'lng': -17.4,
      'scheduled_at': at.toIso8601String(),
      'price_from_origin': '0.00',
      if (waitUntil != null) 'reached_at': waitUntil.subtract(const Duration(minutes: 5)).toIso8601String(),
      if (waitUntil != null) 'wait_until': waitUntil.toIso8601String(),
    };

Trip _trip({String status = 'open', DateTime? waitUntil}) => Trip.fromApiJson({
      'id': 't1',
      'status': status,
      'origin_name': 'Dakar',
      'destination_name': 'Thiès',
      'scheduled_at': _departure.toIso8601String(),
      'price_per_seat': '3000.00',
      'seats_available': 2,
      'stops': [
        _stop('s0', 0, 'Dakar', _departure, waitUntil: waitUntil),
        _stop('s1', 1, 'Thiès', _departure.add(const Duration(hours: 1))),
      ],
    });

Booking _passenger(String id, {bool boarded = false}) => Booking.fromApiJson({
      'id': id,
      'trip_id': 't1',
      'status': 'confirmed',
      'boarding_stop': _stop('s0', 0, 'Dakar', _departure),
      if (boarded) 'started_at': _departure.toIso8601String(),
    });

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('fr_FR');
  });

  test('before departure the driver sees a countdown, then the delay', () {
    final trip = _trip();
    final passengers = [_passenger('b1')];

    expect(departureStatus(trip, passengers, _departure.subtract(const Duration(days: 2))), isNull);

    final hour = departureStatus(trip, passengers, _departure.subtract(const Duration(minutes: 45)))!;
    expect(hour.title, 'Départ dans 45 min');
    expect(hour.detail, contains('Gardez cet écran ouvert'));

    final soon = departureStatus(trip, passengers, _departure.subtract(const Duration(minutes: 4, seconds: 20)))!;
    expect(soon.title, 'Départ dans 4:20');
    expect(soon.tone, TimeTone.soon);

    final late = departureStatus(trip, passengers, _departure.add(const Duration(minutes: 7)))!;
    expect(late.title, contains('il y a 7 min'));
    expect(late.detail, contains('Vos passagers vous attendent à Dakar'));
    expect(late.tone, TimeTone.late);
  });

  test('at the meeting point the driver counts down the wait for missing passengers', () {
    final waitUntil = _departure.add(const Duration(minutes: 5));
    final trip = _trip(waitUntil: waitUntil);
    final passengers = [_passenger('b1'), _passenger('b2'), _passenger('b3', boarded: true)];

    final waiting = departureStatus(trip, passengers, waitUntil.subtract(const Duration(minutes: 2, seconds: 5)))!;
    expect(waiting.title, 'Attente à Dakar · encore 2:05');
    expect(waiting.detail, startsWith('2 passagers pas encore à bord'));
    expect(waiting.tone, TimeTone.urgent);

    final over = departureStatus(trip, passengers, waitUntil.add(const Duration(seconds: 1)))!;
    expect(over.title, 'Délai d’attente écoulé à Dakar');
    expect(over.detail, contains('déclarez-les absents'));

    // Tout le monde à bord : plus de décompte, retour à l'heure de départ.
    final allAboard = departureStatus(trip, [_passenger('b3', boarded: true)], waitUntil.subtract(const Duration(minutes: 1)))!;
    expect(allAboard.title, isNot(startsWith('Attente')));
  });

  testWidgets('the card shows the status with its colour', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: TimeStatusCard(
          status: (icon: Icons.schedule_rounded, title: 'Départ dans 4:20', detail: 'À 08:30 · Dakar.', tone: TimeTone.soon),
        ),
      ),
    ));
    expect(find.text('Départ dans 4:20'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
