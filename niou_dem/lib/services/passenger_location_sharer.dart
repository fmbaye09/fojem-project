import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../core/network/api_exception.dart';
import 'booking_repository.dart';

/// Partage de la position du passager avec son chauffeur, sur son choix.
///
/// Tourne tant que l'app est ouverte (même si le passager quitte l'écran du
/// billet) et s'arrête quand il le désactive, quand l'embarquement est
/// validé ou quand la réservation n'est plus active (refus du backend).
class PassengerLocationSharer extends ChangeNotifier {
  PassengerLocationSharer._();
  static final instance = PassengerLocationSharer._();

  static const interval = Duration(seconds: 20);

  final _repository = BookingRepository();
  Timer? _timer;
  String? _bookingId;
  DateTime? _lastSentAt;

  String? get bookingId => _bookingId;
  DateTime? get lastSentAt => _lastSentAt;
  bool isSharing(String bookingId) => _bookingId == bookingId;

  /// Demande la permission de localisation ; `false` si refusée.
  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always || permission == LocationPermission.whileInUse;
  }

  Future<void> start(String bookingId) async {
    if (_bookingId != null && _bookingId != bookingId) await stop();
    _bookingId = bookingId;
    notifyListeners();
    await _send();
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _send());
  }

  Future<void> stop() async {
    final id = _bookingId;
    _timer?.cancel();
    _timer = null;
    _bookingId = null;
    _lastSentAt = null;
    notifyListeners();
    if (id != null) {
      try {
        await _repository.stopSharingLocation(id);
      } catch (_) {
        // La position expire d'elle-même côté serveur après 3 minutes.
      }
    }
  }

  Future<void> _send() async {
    final id = _bookingId;
    if (id == null) return;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 10));
      await _repository.shareLocation(id, position.latitude, position.longitude);
      _lastSentAt = DateTime.now();
      notifyListeners();
    } on ApiException catch (e) {
      // Embarquement validé ou réservation terminée : le backend refuse (422/403).
      if (e.statusCode == 422 || e.statusCode == 403) {
        _timer?.cancel();
        _timer = null;
        _bookingId = null;
        notifyListeners();
      }
    } catch (_) {
      // Pas de position ou pas de réseau : réessayé au prochain tour.
    }
  }
}
