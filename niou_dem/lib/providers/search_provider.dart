import 'package:flutter/material.dart';
import '../core/geo/senegal_city_coordinates.dart';
import '../models/trip.dart';
import '../services/trip_repository.dart';

class SearchProvider extends ChangeNotifier {
  final TripRepository _tripRepository;

  SearchProvider({TripRepository? tripRepository})
      : _tripRepository = tripRepository ?? TripRepository();

  // Pré-rempli comme sur la maquette d'accueil : Dakar → Thiès, l'axe le
  // plus demandé. L'accueil et l'onglet Trajets partagent cette recherche.
  String? _departure = 'Dakar';
  String? _arrival = 'Thiès';
  DateTime _date = DateTime.now();
  int _passengers = 1;
  bool _isLoading = false;
  List<Trip> _results = [];
  String? _errorMessage;

  String? get departure => _departure;
  String? get arrival => _arrival;
  DateTime get date => _date;
  int get passengers => _passengers;
  bool get isLoading => _isLoading;
  List<Trip> get results => _results;
  String? get errorMessage => _errorMessage;
  bool get hasSearch => _departure != null && _arrival != null;

  void setDeparture(String city) {
    _departure = city;
    notifyListeners();
  }

  void setArrival(String city) {
    _arrival = city;
    notifyListeners();
  }

  void swapCities() {
    final temp = _departure;
    _departure = _arrival;
    _arrival = temp;
    notifyListeners();
  }

  void setDate(DateTime date) {
    _date = date;
    notifyListeners();
  }

  void setPassengers(int count) {
    _passengers = count.clamp(1, 9);
    notifyListeners();
  }

  /// Recherche géographique réelle contre `GET /trips/search` — le backend
  /// filtre lui-même par rayon autour de l'origine/destination demandées
  /// (voir `TripRepository.search`), plus de matching client sur une liste
  /// globale (qui n'existe plus côté API).
  Future<void> search() async {
    if (_departure == null || _arrival == null) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final desiredOrigin = coordinatesForCity(_departure!);
      final desiredDestination = coordinatesForCity(_arrival!);
      final candidates = await _tripRepository.search(
        origin: desiredOrigin,
        destination: desiredDestination,
      );

      _results = candidates.where((t) {
        final sameDay = t.departureTime.year == _date.year &&
            t.departureTime.month == _date.month &&
            t.departureTime.day == _date.day;
        return sameDay && !t.isFull;
      }).toList()
        ..sort((a, b) => a.departureTime.compareTo(b.departureTime));
    } catch (e) {
      _errorMessage = 'Impossible de charger les trajets. Réessayez.';
      _results = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  void clear() {
    _departure = null;
    _arrival = null;
    _date = DateTime.now();
    _passengers = 1;
    _results = [];
    _errorMessage = null;
    notifyListeners();
  }
}
