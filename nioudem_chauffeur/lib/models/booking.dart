import 'trip.dart';

enum BookingStatus { pending, confirmed, refused, cancelled, completed }

BookingStatus _statusFromApi(String? value) {
  switch (value) {
    case 'pending_driver':
      return BookingStatus.pending;
    case 'confirmed':
      return BookingStatus.confirmed;
    case 'rejected':
      return BookingStatus.refused;
    case 'cancelled_passenger':
    case 'cancelled_driver':
      return BookingStatus.cancelled;
    case 'completed':
    case 'no_show':
      return BookingStatus.completed;
    default:
      return BookingStatus.pending;
  }
}

class Booking {
  final String id;
  final String tripId;
  final String passengerId;
  final int seatCount;

  /// Sièges choisis par le passager sur le plan du véhicule ; vide pour les
  /// réservations faites sans plan.
  final List<String> seatNumbers;
  final double price;
  final BookingStatus status;
  final DateTime bookedAt;
  final String confirmationCode;
  final String passengerName;
  final String passengerPhone;
  final String? passengerPhotoUrl;
  final DateTime? startedAt;
  final bool hasHeavyLuggage;
  final List<String> luggagePhotoUrls;

  final Trip? trip;

  const Booking({
    required this.id,
    required this.tripId,
    required this.passengerId,
    this.seatCount = 1,
    this.seatNumbers = const [],
    required this.price,
    required this.status,
    required this.bookedAt,
    required this.confirmationCode,
    this.passengerName = '',
    this.passengerPhone = '',
    this.passengerPhotoUrl,
    this.hasHeavyLuggage = false,
    this.luggagePhotoUrls = const [],
    this.startedAt,
    this.trip,
  });

  int get seatsBooked => seatCount;
  double get totalPrice => price;
  bool get isBoarded => startedAt != null;

  String get statusLabel {
    switch (status) {
      case BookingStatus.pending:
        return 'En attente';
      case BookingStatus.confirmed:
        return isBoarded ? 'À bord' : 'Confirmé';
      case BookingStatus.refused:
        return 'Refusé';
      case BookingStatus.cancelled:
        return 'Annulé';
      case BookingStatus.completed:
        return 'Terminé';
    }
  }

  factory Booking.fromApiJson(Map<String, dynamic> json, {Trip? trip}) {
    final passenger = json['passenger'] as Map<String, dynamic>?;
    final name = (passenger?['full_name'] as String?) ??
        (passenger?['name'] as String?) ??
        '';
    final phone = (passenger?['phone_number'] as String?) ??
        (passenger?['phone'] as String?) ??
        '';
    final photo = passenger?['profile_photo_url'] as String?;

    final photosList = <String>[];
    if (json['luggage_photos'] is List) {
      for (final p in (json['luggage_photos'] as List)) {
        if (p is Map<String, dynamic> && p['photo_url'] is String) {
          photosList.add(p['photo_url'] as String);
        } else if (p is String) {
          photosList.add(p);
        }
      }
    }

    final hasHeavy = json['has_heavy_luggage'] == true ||
        json['has_heavy_luggage'] == 1 ||
        photosList.isNotEmpty;

    return Booking(
      id: json['id'] as String? ?? '',
      tripId: json['trip_id'] as String? ?? '',
      passengerId: json['passenger_id'] as String? ?? '',
      seatCount: json['seat_count'] as int? ?? 1,
      seatNumbers: [
        for (final seat in (json['seat_numbers'] as List? ?? const [])) '$seat',
      ],
      price: double.tryParse('${json['price_charged'] ?? 0}') ?? 0,
      status: _statusFromApi(json['status'] as String?),
      bookedAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      confirmationCode: json['departure_code'] as String? ?? '',
      passengerName: name,
      passengerPhone: phone,
      passengerPhotoUrl: photo,
      hasHeavyLuggage: hasHeavy,
      luggagePhotoUrls: photosList,
      startedAt: DateTime.tryParse(json['started_at'] as String? ?? ''),
      trip: trip,
    );
  }

  Booking copyWith({
    BookingStatus? status,
    Trip? trip,
    DateTime? startedAt,
    bool? hasHeavyLuggage,
    List<String>? luggagePhotoUrls,
  }) {
    return Booking(
      id: id,
      tripId: tripId,
      passengerId: passengerId,
      seatCount: seatCount,
      seatNumbers: seatNumbers,
      price: price,
      status: status ?? this.status,
      bookedAt: bookedAt,
      confirmationCode: confirmationCode,
      passengerName: passengerName,
      passengerPhone: passengerPhone,
      passengerPhotoUrl: passengerPhotoUrl,
      hasHeavyLuggage: hasHeavyLuggage ?? this.hasHeavyLuggage,
      luggagePhotoUrls: luggagePhotoUrls ?? this.luggagePhotoUrls,
      startedAt: startedAt ?? this.startedAt,
      trip: trip ?? this.trip,
    );
  }
}
