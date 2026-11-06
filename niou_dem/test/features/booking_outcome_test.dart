import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_passager/models/booking.dart';

Booking _booking(String status) => Booking.fromApi({'id': 'b1', 'trip_id': 't1', 'status': status});

void main() {
  test('a trip the driver left without the passenger reads « Manqué »', () {
    final missed = _booking('missed');
    expect(missed.status, BookingStatus.cancelled);
    expect(missed.isMissed, isTrue);
    expect(missed.statusLabel, 'Manqué');

    expect(_booking('no_show').isMissed, isFalse);
    expect(_booking('cancelled_driver').statusLabel, 'Annulé');
  });
}
