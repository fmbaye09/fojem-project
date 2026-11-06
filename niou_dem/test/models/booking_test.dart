import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_passager/models/booking.dart';

void main() {
  test('a booking keeps who cancelled it and whether it was rated', () {
    final cancelled = Booking.fromApi({'id': 'b1', 'trip_id': 't1', 'status': 'cancelled_driver'});
    expect(cancelled.status, BookingStatus.cancelled);
    expect(cancelled.apiStatus, 'cancelled_driver');
    expect(cancelled.isReviewed, isFalse);

    final rated = Booking.fromApi({'id': 'b2', 'trip_id': 't1', 'status': 'completed', 'review_exists': true});
    expect(rated.isReviewed, isTrue);
    expect(rated.copyWith(trip: null).isReviewed, isTrue);
  });
}
