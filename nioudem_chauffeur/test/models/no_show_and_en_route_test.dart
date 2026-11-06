import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_chauffeur/core/widgets/en_route_switch.dart';
import 'package:fojem_chauffeur/models/booking.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('an absent passenger is no longer active and reads « Absent »', () {
    final booking = Booking.fromApiJson({'id': 'b1', 'trip_id': 't1', 'status': 'no_show'});
    expect(booking.status, BookingStatus.cancelled);
    expect(booking.isNoShow, isTrue);
    expect(booking.statusLabel, 'Absent');

    final cancelled = Booking.fromApiJson({'id': 'b2', 'trip_id': 't1', 'status': 'cancelled_passenger'});
    expect(cancelled.statusLabel, 'Annulé');
  });

  test('the reliability of a passenger is shown to the driver', () {
    Booking withReliability(Object? reliability) =>
        Booking.fromApiJson({'id': 'b1', 'trip_id': 't1', 'status': 'pending_driver', 'passenger_reliability': reliability});

    expect(withReliability(null).reliabilityLabel, 'Nouveau passager');
    expect(withReliability({'honored_pct': 100, 'no_show_count': 0}).reliabilityLabel, 'Fiable à 100 %');
    expect(withReliability({'honored_pct': 67, 'no_show_count': 1}).reliabilityLabel, 'Fiable à 67 % · 1 absence');
    expect(withReliability({'honored_pct': 50, 'no_show_count': 2}).reliabilityLabel, 'Fiable à 50 % · 2 absences');
    expect(withReliability({'honored_pct': 67, 'no_show_count': 1}).copyWith().reliability?.noShowCount, 1);
  });

  testWidgets('the en-route switch reports its new value', (tester) async {
    bool? changed;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EnRouteSwitch(value: false, onChanged: (v) => changed = v)),
    ));

    expect(find.text('Accepter des passagers en route'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    expect(changed, isTrue);
  });
}
