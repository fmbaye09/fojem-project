import 'package:flutter/material.dart';
import '../core/geo/geo_location.dart';
import '../core/geo/senegal_city_coordinates.dart';

/// Recherche en cours, partagée par l'accueil et l'écran de résultats.
///
/// Départ et arrivée sont des points précis (adresse, position GPS ou
/// centre-ville) : la recherche trouve les trajets dont un point de
/// rendez-vous est proche de chacun, comme BlaBlaCar.
class SearchProvider extends ChangeNotifier {
  // Pré-rempli comme sur la maquette d'accueil : Dakar → Thiès, l'axe le
  // plus demandé.
  GeoLocation? _origin = _cityPoint('Dakar');
  GeoLocation? _destination = _cityPoint('Thiès');
  DateTime _date = DateTime.now();
  int _passengers = 1;

  static GeoLocation _cityPoint(String city) {
    final c = coordinatesForCity(city);
    return GeoLocation(lat: c.lat, lng: c.lng, address: city, locality: city);
  }

  GeoLocation? get origin => _origin;
  GeoLocation? get destination => _destination;

  /// Libellés courts (« Dakar », « Gare routière »).
  String? get departure => _origin?.shortLabel;
  String? get arrival => _destination?.shortLabel;
  DateTime get date => _date;
  int get passengers => _passengers;
  bool get hasSearch => _origin != null && _destination != null;

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
