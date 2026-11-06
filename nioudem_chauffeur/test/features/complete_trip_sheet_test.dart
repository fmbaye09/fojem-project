import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_chauffeur/features/trips/widgets/complete_trip_sheet.dart';
import 'package:fojem_chauffeur/models/booking.dart';
import 'package:google_fonts/google_fonts.dart';

Booking _booking(String id, String name, {String status = 'confirmed'}) => Booking.fromApiJson({
      'id': id,
      'trip_id': 't1',
      'status': status,
      'passenger': {'full_name': name},
      'boarding_stop': {'id': 's1', 'position': 1, 'name': 'Rufisque', 'lat': 14.716, 'lng': -17.273},
    });

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('the driver says who travelled before ending the trip', (tester) async {
    List<String>? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showCompleteTripSheet(context, [
              _booking('b1', 'Awa Ndiaye'),
              _booking('b2', 'Moussa Diop'),
            ]),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    expect(find.text('Devait monter à Rufisque'), findsNWidgets(2));

    // Tant que chacun n'a pas de réponse, le trajet ne se termine pas.
    // Le titre et le bouton portent le même texte : le bouton vient en dernier.
    final finish = find.text('Terminer le trajet').last;
    await tester.tap(find.text('A voyagé').first);
    await tester.pump();
    await tester.tap(finish, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(result, isNull);

    await tester.tap(find.text('Pas venu').last);
    await tester.pump();
    await tester.tap(finish);
    await tester.pumpAndSettle();
    expect(result, ['b2']);
  });

  test('a booking missed by the driver reads « Manqué »', () {
    final missed = _booking('b3', 'Fatou Sow', status: 'missed');
    expect(missed.status, BookingStatus.cancelled);
    expect(missed.isMissed, isTrue);
    expect(missed.statusLabel, 'Manqué');
    expect(_booking('b4', 'Ibou', status: 'no_show').statusLabel, 'Absent');
  });
}
