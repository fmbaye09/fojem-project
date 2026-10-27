import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'trip_repository.dart';

/// Envoie la position du chauffeur au backend pendant un trajet en cours,
/// indépendamment de l'écran affiché.
///
/// Sur Android, le flux de position tourne dans un service de premier plan
/// (notification « Trajet en cours ») : il continue quand le chauffeur
/// change d'écran ou éteint son téléphone, tant que l'app n'est pas tuée.
class TripLocationTracker {
  TripLocationTracker._();
  static final TripLocationTracker instance = TripLocationTracker._();

  /// Intervalle minimal entre deux envois au backend.
  static const _minSendInterval = Duration(seconds: 8);

  final TripRepository _repository = TripRepository();
  StreamSubscription<Position>? _subscription;
  String? _tripId;
  DateTime? _lastAttemptAt;

  /// Dernier envoi réussi (affiché sur l'écran du trajet).
  final ValueNotifier<DateTime?> lastSentAt = ValueNotifier(null);

  /// La localisation est refusée ou désactivée : le suivi est impossible.
  final ValueNotifier<bool> permissionDenied = ValueNotifier(false);

  String? get activeTripId => _tripId;

  /// Démarre le suivi de [tripId]. Sans effet si ce trajet est déjà suivi.
  Future<void> start(String tripId) async {
    if (_tripId == tripId && _subscription != null) return;
    stop();

    if (!await _ensurePermission()) return;

    _tripId = tripId;
    _subscription = Geolocator.getPositionStream(locationSettings: _settings()).listen(
      _onPosition,
      onError: (Object e) {
        if (kDebugMode) debugPrint('[TripLocationTracker] Erreur GPS: $e');
      },
    );
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _tripId = null;
    _lastAttemptAt = null;
  }

  Future<bool> _ensurePermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        permissionDenied.value = true;
        return false;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      final granted = permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      permissionDenied.value = !granted;
      return granted;
    } catch (_) {
      permissionDenied.value = true;
      return false;
    }
  }

  LocationSettings _settings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
        intervalDuration: _minSendInterval,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Trajet en cours',
          notificationText: 'Vos passagers suivent votre position en direct.',
          enableWakeLock: true,
        ),
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 20);
  }

  Future<void> _onPosition(Position pos) async {
    final tripId = _tripId;
    if (tripId == null) return;

    final now = DateTime.now();
    if (_lastAttemptAt != null && now.difference(_lastAttemptAt!) < _minSendInterval) return;
    _lastAttemptAt = now;

    try {
      await _repository.updateLocation(
        tripId,
        lat: pos.latitude,
        lng: pos.longitude,
        heading: pos.heading.isFinite ? pos.heading : null,
      );
      lastSentAt.value = DateTime.now();
    } catch (_) {
      // Réseau instable en route : on réessaiera à la position suivante.
    }
  }
}
