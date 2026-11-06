import 'dart:async';

import 'package:flutter/material.dart';
import '../core/geo/geo_location.dart';
import '../services/current_location.dart';

/// Recherche en cours, partagée par l'accueil et l'écran de résultats.
///
/// Départ et arrivée sont des points précis (adresse, position GPS ou
/// centre-ville) : la recherche trouve les trajets dont un point de
/// rendez-vous est proche de chacun, comme BlaBlaCar. Rien n'est pré-rempli :
/// le départ devient la position actuelle du passager ([locateOrigin]).
class SearchProvider extends ChangeNotifier {
  GeoLocation? _origin;
  GeoLocation? _destination;
  DateTime _date = DateTime.now();
  int _passengers = 1;

  /// Position trouvée par [locateOrigin], affichée « Ma position » tant que
  /// le passager ne l'a pas remplacée.
  GeoLocation? _currentPosition;
  bool _locating = false;
  bool _locatedOnce = false;

  GeoLocation? get origin => _origin;
  GeoLocation? get destination => _destination;

  /// Libellés courts (« Dakar », « Gare routière », « Ma position · Rufisque »).
  String? get departure => _label(_origin);
  String? get arrival => _label(_destination);
  DateTime get date => _date;
  int get passengers => _passengers;
  bool get hasSearch => _origin != null && _destination != null;

  /// Vrai pendant la recherche de la position actuelle.
  bool get isLocating => _locating;
  bool isCurrentPosition(GeoLocation? location) => location != null && identical(location, _currentPosition);

  String? _label(GeoLocation? location) {
    if (location == null) return null;
    if (!isCurrentPosition(location)) return location.shortLabel;
    final where = location.locality?.trim();
    return where == null || where.isEmpty ? kCurrentPositionLabel : '$kCurrentPositionLabel · $where';
  }

  /// Départ par défaut : la position actuelle, cherchée une fois par
  /// lancement de l'app et seulement si aucun départ n'est choisi. Rend la
  /// main dès que la position est connue ; l'adresse suit.
  Future<void> locateOrigin({
    Future<GeoLocation?> Function() locate = locateDevice,
    Future<GeoLocation?> Function(GeoLocation) describe = describeLocation,
  }) async {
    if (_locatedOnce || _origin != null) return;
    _locatedOnce = true;
    _locating = true;
    notifyListeners();
    final here = await locate();
    _locating = false;
    if (here != null && _origin == null) {
      _origin = _currentPosition = here;
      unawaited(_describe(here, describe));
    }
    notifyListeners();
  }

  Future<void> _describe(GeoLocation here, Future<GeoLocation?> Function(GeoLocation) describe) async {
    final described = await describe(here);
    if (described == null || !identical(_currentPosition, here)) return;
    // Le passager a pu inverser départ et arrivée entre-temps.
    if (identical(_origin, here)) _origin = described;
    if (identical(_destination, here)) _destination = described;
    _currentPosition = described;
    notifyListeners();
  }

  void setOrigin(GeoLocation location) {
    _origin = location;
    notifyListeners();
  }

  void setDestination(GeoLocation location) {
    _destination = location;
    notifyListeners();
  }

  void swap() {
    final temp = _origin;
    _origin = _destination;
    _destination = temp;
    notifyListeners();
  }

  void setDate(DateTime date) {
    _date = date;
    notifyListeners();
  }

  void setPassengers(int count) {
    _passengers = count.clamp(1, 8);
    notifyListeners();
  }
}
