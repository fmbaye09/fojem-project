import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_passager/core/widgets/countdown.dart';
import 'package:fojem_passager/features/booking/meeting_status.dart';
import 'package:fojem_passager/models/booking.dart';
import 'package:fojem_passager/models/trip.dart';
import 'package:intl/date_symbol_data_local.dart';

final _departure = DateTime.utc(2026, 11, 10, 8, 30);

Map<String, dynamic> _stop(String id, int position, String name, DateTime at, {DateTime? waitUntil, DateTime? leftAt}) => {
      'id': id,
      'position': position,
      'name': name,
      'lat': 14.7,
      'lng': -17.4,
      'scheduled_at': at.toIso8601String(),
      'price_from_origin': '0.00',
      if (waitUntil != null) 'reached_at': waitUntil.subtract(const Duration(minutes: 5)).toIso8601String(),
      if (waitUntil != null) 'wait_until': waitUntil.toIso8601String(),
      if (leftAt != null) 'left_at': leftAt.toIso8601String(),
    };

({Trip trip, Booking booking}) _ticket({
  String tripStatus = 'open',
  String bookingStatus = 'confirmed',
  DateTime? waitUntil,
  DateTime? leftAt,
  bool boarded = false,
}) {
  final dakar = _stop('s0', 0, 'Dakar', _departure, waitUntil: waitUntil, leftAt: leftAt);
  final trip = Trip.fromApi({
    'id': 't1',
    'status': tripStatus,
    'origin_name': 'Dakar',
    'destination_name': 'Thiès',
    'scheduled_at': _departure.toIso8601String(),
    'price_per_seat': '3000.00',
    'seats_available': 2,
    'stops': [dakar, _stop('s1', 1, 'Thiès', _departure.add(const Duration(hours: 1)))],
  });
  final booking = Booking.fromApi({
    'id': 'b1',
    'trip_id': 't1',
    'status': bookingStatus,
    // Le billet garde l'arrêt tel qu'il était à la réservation : c'est
    // l'arrêt du trajet, plus frais, qui dit si le chauffeur est arrivé.
    'boarding_stop': _stop('s0', 0, 'Dakar', _departure),
    if (boarded) 'started_at': _departure.toIso8601String(),
  }, trip: trip);
  return (trip: trip, booking: booking);
}

TimeStatus? _at(({Trip trip, Booking booking}) t, DateTime now) => meetingStatus(t.trip, t.booking, now);

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  test('countdowns read in days, hours, minutes then seconds', () {
    expect(formatCountdown(const Duration(days: 2, hours: 3)), '2 j');
    expect(formatCountdown(const Duration(hours: 1, minutes: 5)), '1 h 05');
    expect(formatCountdown(const Duration(minutes: 12, seconds: 40)), '12 min');
    expect(formatCountdown(const Duration(minutes: 4, seconds: 5)), '4:05');
    expect(formatCountdown(const Duration(seconds: -30)), '0:00');
  });

  test('before departure the ticket counts down to the meeting', () {
    final t = _ticket();
    final local = _departure.toLocal();
    final hhmm = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';

    final early = _at(t, _departure.subtract(const Duration(hours: 2)))!;
    expect(early.title, 'Rendez-vous dans 2 h 00');
    expect(early.tone, TimeTone.calm);
    expect(early.detail, contains('À $hhmm · Dakar'));

    final soon = _at(t, _departure.subtract(const Duration(minutes: 9, seconds: 30)))!;
    expect(soon.title, 'Rendez-vous dans 9:30');
    expect(soon.tone, TimeTone.soon);
    expect(soon.detail, contains('n’attend que 5 min'));

    final past = _at(t, _departure.add(const Duration(minutes: 2)))!;
    expect(past.title, 'Le chauffeur n’est pas encore arrivé');
  });

  test('once the driver is there, the ticket counts down his wait', () {
    final waitUntil = _departure.add(const Duration(minutes: 5));
    final t = _ticket(waitUntil: waitUntil);

    final waiting = _at(t, waitUntil.subtract(const Duration(minutes: 3, seconds: 12)))!;
    expect(waiting.title, 'Le chauffeur vous attend · encore 3:12');
    expect(waiting.tone, TimeTone.urgent);
    expect(waiting.detail, contains('déclarer absent'));

    final over = _at(t, waitUntil.add(const Duration(seconds: 1)))!;
    expect(over.title, 'Délai d’attente dépassé');
    expect(over.tone, TimeTone.late);

    // Même trajet démarré, le décompte continue.
    final started = _ticket(tripStatus: 'in_progress', waitUntil: waitUntil);
    expect(_at(started, waitUntil.subtract(const Duration(minutes: 1)))!.title, 'Le chauffeur vous attend · encore 1:00');
  });

  test('once the driver has left, the ticket says so instead of counting down', () {
    final waitUntil = _departure.add(const Duration(minutes: 5));
    String hhmm(DateTime d) {
      final l = d.toLocal();
      return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
    }

    // Parti à 08:32, avant la fin de l'attente : le passager peut lui écrire.
    final leftEarly = _departure.add(const Duration(minutes: 2));
    final early = _at(_ticket(tripStatus: 'in_progress', waitUntil: waitUntil, leftAt: leftEarly), leftEarly.add(const Duration(seconds: 20)))!;
    expect(early.title, 'Le chauffeur est reparti de Dakar');
    expect(early.tone, TimeTone.late);
    expect(early.detail, contains('Il est parti à ${hhmm(leftEarly)}, avant la fin de l’attente (${hhmm(waitUntil)})'));
    expect(early.detail, contains('« manqué », sans pénalité'));

    // Parti après l'attente.
    final leftLate = waitUntil.add(const Duration(minutes: 1));
    final late = _at(_ticket(tripStatus: 'in_progress', waitUntil: waitUntil, leftAt: leftLate), leftLate)!;
    expect(late.detail, 'Il vous a attendu jusqu’à ${hhmm(waitUntil)}, puis a repris la route.');

    // À bord, rien de tout ça.
    final boarded = _at(_ticket(tripStatus: 'in_progress', waitUntil: waitUntil, leftAt: leftEarly, boarded: true), leftEarly);
    expect(boarded?.title ?? '', isNot(startsWith('Le chauffeur est reparti')));
  });

  test('no wait countdown for a passenger on board or not yet accepted', () {
    final waitUntil = _departure.add(const Duration(minutes: 5));
    final now = waitUntil.subtract(const Duration(minutes: 2));

    expect(_at(_ticket(waitUntil: waitUntil, bookingStatus: 'pending_driver'), now)!.title,
        isNot(startsWith('Le chauffeur vous attend')));
    expect(_at(_ticket(tripStatus: 'in_progress', waitUntil: waitUntil, boarded: true), now)?.title ?? '',
        isNot(startsWith('Le chauffeur vous attend')));
    expect(_at(_ticket(tripStatus: 'completed'), now), isNull);
  });
}
