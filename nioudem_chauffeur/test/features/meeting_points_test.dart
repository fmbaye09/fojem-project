import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_chauffeur/features/publish_trip/screens/publish_trip_screen.dart';
import 'package:fojem_chauffeur/features/requests/widgets/proposed_stop_notice.dart';
import 'package:fojem_chauffeur/models/booking.dart';
import 'package:fojem_chauffeur/services/meeting_point_repository.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('suggested stops', () {
    final frequent = MeetingPointSuggestion.fromJson({
      'name': 'Rufisque',
      'address': 'Péage de Rufisque',
      'kind': 'frequent',
      'lat': 14.716,
      'lng': -17.273,
      'km_from_start': 18,
      'trips_count': 3,
      'passengers_count': 1,
    });
    final station = MeetingPointSuggestion.fromJson({
      'name': 'Ciel oil',
      'address': 'Ciel oil, Thiaroye',
      'kind': 'station',
      'lat': 14.75,
      'lng': -17.38,
      'km_from_start': 13,
    });

    test('say why each place is suggested', () {
      expect(frequent.detail, 'Déjà utilisé par 3 trajets · 1 passager');
      expect(station.detail, 'Station-service · Thiaroye');
    });

    test('become a stop named after the place', () {
      final location = frequent.toGeoLocation();
      expect(location.shortLabel, 'Rufisque');
      expect(location.address, 'Péage de Rufisque');
      expect(station.toGeoLocation().shortLabel, 'Ciel oil');
    });

    testWidgets('are added with one tap, unless the trip is full of stops', (tester) async {
      final added = <MeetingPointSuggestion>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SuggestedStops(suggestions: [station, frequent], onAdd: added.add)),
      ));
      expect(find.text('Station-service · Thiaroye · km 13'), findsOneWidget);
      await tester.tap(find.text('Ajouter').last);
      expect(added.single.name, 'Rufisque');

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SuggestedStops(suggestions: [station])),
      ));
      expect(find.text('Vous avez atteint le nombre maximum d’arrêts.'), findsOneWidget);
      await tester.tap(find.text('Ajouter'));
      expect(added, hasLength(1));
    });
  });

  group('stop proposed by a passenger', () {
    Booking booking({String? insertedStopId}) => Booking.fromApiJson({
          'id': 'b1',
          'trip_id': 't1',
          'status': 'pending_driver',
          'passenger': {'full_name': 'Awa Ndiaye'},
          'boarding_stop': null,
          'alighting_stop': {'id': 's3', 'position': 2, 'name': 'Thiès', 'lat': 14.791, 'lng': -16.926},
          'proposed_stop': {
            'role': 'boarding',
            'name': 'Mbao',
            'address': 'Station Mbao',
            'lat': 14.713,
            'lng': -17.3555,
            'detour_minutes': 6,
            'scheduled_at': '2026-11-10T08:45:00Z',
            'price_from_origin': '1000.00',
            'inserted_stop_id': insertedStopId,
          },
        });

    test('is waiting for the driver until it is added to the trip', () {
      expect(booking().proposesNewStop, isTrue);
      expect(booking().boardingName, 'Mbao');
      expect(booking().proposedStop!.detourMinutes, 6);
      expect(booking(insertedStopId: 's9').proposesNewStop, isFalse);
    });

    testWidgets('shows the detour before the driver accepts', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ProposedStopNotice(proposal: booking().proposedStop!)),
      ));
      expect(find.text('Nouvel arrêt proposé : Mbao'), findsOneWidget);
      expect(find.textContaining('Environ 6 min de détour pour vous'), findsOneWidget);
      expect(find.text('Voir sur la carte'), findsOneWidget);
    });
  });
}
