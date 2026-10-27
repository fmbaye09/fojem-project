import '../../../models/vehicle.dart';

enum SeatStatus { available, selected, occupied, driver }

class SeatConfig {
  final String id;
  final String label;
  final SeatStatus initialStatus;

  /// Position relative au conteneur image : 0.0 → bord gauche, 1.0 → bord droit
  final double dx;

  /// Position relative au conteneur image : 0.0 → bord haut, 1.0 → bord bas
  final double dy;

  const SeatConfig({
    required this.id,
    required this.label,
    required this.initialStatus,
    required this.dx,
    required this.dy,
  });
}

class SeatState {
  final SeatConfig config;
  final SeatStatus status;

  const SeatState({required this.config, required this.status});

  SeatState copyWith({SeatStatus? status}) =>
      SeatState(config: config, status: status ?? this.status);

  bool get isSelected => status == SeatStatus.selected;
  bool get isOccupied => status == SeatStatus.occupied;
  bool get isDriver => status == SeatStatus.driver;
  bool get isAvailable => status == SeatStatus.available;
  bool get isInteractive => isAvailable || isSelected;
}

/// Plan de sièges "van 9 places", calibré sur la vue isométrique Mercedes
/// Sprinter (top-down) dessinée par [SprinterPainter]. Tous les sièges
/// passagers démarrent `available` — l'état réel (occupé/sélectionné) est
/// appliqué dynamiquement à partir des données de réservation, pas ici.
///
/// Disposition physique :
///   [Chauffeur]  [Place 2]      ← Cabine rang 1
///   [Place 1]  [Place 3][Pl 4] ← Cabine rang 2
///   ═══ Cabine – Mercedes Sprinter ═══
///   [Place 6]  [Place 5][Pl 7] ← Carrosserie rang 1
///      [Place 8]   [Place 9]   ← Banquette arrière
const List<SeatConfig> kVan9SeatLayout = [
  SeatConfig(id: 'driver', label: 'Chauffeur', initialStatus: SeatStatus.driver, dx: 0.245, dy: 0.198),
  SeatConfig(id: '2', label: '2', initialStatus: SeatStatus.available, dx: 0.722, dy: 0.198),
  SeatConfig(id: '1', label: '1', initialStatus: SeatStatus.available, dx: 0.245, dy: 0.372),
  SeatConfig(id: '3', label: '3', initialStatus: SeatStatus.available, dx: 0.614, dy: 0.372),
  SeatConfig(id: '4', label: '4', initialStatus: SeatStatus.available, dx: 0.790, dy: 0.372),
  SeatConfig(id: '6', label: '6', initialStatus: SeatStatus.available, dx: 0.245, dy: 0.638),
  SeatConfig(id: '5', label: '5', initialStatus: SeatStatus.available, dx: 0.614, dy: 0.618),
  SeatConfig(id: '7', label: '7', initialStatus: SeatStatus.available, dx: 0.790, dy: 0.618),
  SeatConfig(id: '8', label: '8', initialStatus: SeatStatus.available, dx: 0.340, dy: 0.830),
  SeatConfig(id: '9', label: '9', initialStatus: SeatStatus.available, dx: 0.658, dy: 0.830),
];

/// Berline (4 places passagers) : chauffeur + 1 place avant + banquette
/// arrière 3 places.
const List<SeatConfig> kBerlineSeatLayout = [
  SeatConfig(id: 'driver', label: 'Chauffeur', initialStatus: SeatStatus.driver, dx: 0.28, dy: 0.18),
  SeatConfig(id: '1', label: '1', initialStatus: SeatStatus.available, dx: 0.72, dy: 0.18),
  SeatConfig(id: '2', label: '2', initialStatus: SeatStatus.available, dx: 0.24, dy: 0.62),
  SeatConfig(id: '3', label: '3', initialStatus: SeatStatus.available, dx: 0.50, dy: 0.66),
  SeatConfig(id: '4', label: '4', initialStatus: SeatStatus.available, dx: 0.76, dy: 0.62),
];

/// "Sept places" (référence très utilisée au Sénégal) : chauffeur + 1 place
/// avant + 2 rangées de 3.
const List<SeatConfig> kSeptPlacesSeatLayout = [
  SeatConfig(id: 'driver', label: 'Chauffeur', initialStatus: SeatStatus.driver, dx: 0.26, dy: 0.14),
  SeatConfig(id: '1', label: '1', initialStatus: SeatStatus.available, dx: 0.74, dy: 0.14),
  SeatConfig(id: '2', label: '2', initialStatus: SeatStatus.available, dx: 0.22, dy: 0.44),
  SeatConfig(id: '3', label: '3', initialStatus: SeatStatus.available, dx: 0.50, dy: 0.46),
  SeatConfig(id: '4', label: '4', initialStatus: SeatStatus.available, dx: 0.78, dy: 0.44),
  SeatConfig(id: '5', label: '5', initialStatus: SeatStatus.available, dx: 0.22, dy: 0.76),
  SeatConfig(id: '6', label: '6', initialStatus: SeatStatus.available, dx: 0.50, dy: 0.78),
  SeatConfig(id: '7', label: '7', initialStatus: SeatStatus.available, dx: 0.78, dy: 0.76),
];

/// SUV (6 places passagers) : chauffeur + 1 place avant + 2 sièges captain
/// + banquette arrière 3 places.
const List<SeatConfig> kSuvSeatLayout = [
  SeatConfig(id: 'driver', label: 'Chauffeur', initialStatus: SeatStatus.driver, dx: 0.26, dy: 0.14),
  SeatConfig(id: '1', label: '1', initialStatus: SeatStatus.available, dx: 0.74, dy: 0.14),
  SeatConfig(id: '2', label: '2', initialStatus: SeatStatus.available, dx: 0.30, dy: 0.48),
  SeatConfig(id: '3', label: '3', initialStatus: SeatStatus.available, dx: 0.70, dy: 0.48),
  SeatConfig(id: '4', label: '4', initialStatus: SeatStatus.available, dx: 0.22, dy: 0.80),
  SeatConfig(id: '5', label: '5', initialStatus: SeatStatus.available, dx: 0.50, dy: 0.82),
  SeatConfig(id: '6', label: '6', initialStatus: SeatStatus.available, dx: 0.78, dy: 0.80),
];

/// Minibus (15 places passagers) : chauffeur seul à l'avant + 5 rangées de 3.
const List<SeatConfig> kMinibus15SeatLayout = [
  SeatConfig(id: 'driver', label: 'Chauffeur', initialStatus: SeatStatus.driver, dx: 0.22, dy: 0.10),
  SeatConfig(id: '1', label: '1', initialStatus: SeatStatus.available, dx: 0.22, dy: 0.26),
  SeatConfig(id: '2', label: '2', initialStatus: SeatStatus.available, dx: 0.50, dy: 0.26),
  SeatConfig(id: '3', label: '3', initialStatus: SeatStatus.available, dx: 0.78, dy: 0.26),
  SeatConfig(id: '4', label: '4', initialStatus: SeatStatus.available, dx: 0.22, dy: 0.42),
  SeatConfig(id: '5', label: '5', initialStatus: SeatStatus.available, dx: 0.50, dy: 0.42),
  SeatConfig(id: '6', label: '6', initialStatus: SeatStatus.available, dx: 0.78, dy: 0.42),
  SeatConfig(id: '7', label: '7', initialStatus: SeatStatus.available, dx: 0.22, dy: 0.58),
  SeatConfig(id: '8', label: '8', initialStatus: SeatStatus.available, dx: 0.50, dy: 0.58),
  SeatConfig(id: '9', label: '9', initialStatus: SeatStatus.available, dx: 0.78, dy: 0.58),
  SeatConfig(id: '10', label: '10', initialStatus: SeatStatus.available, dx: 0.22, dy: 0.74),
  SeatConfig(id: '11', label: '11', initialStatus: SeatStatus.available, dx: 0.50, dy: 0.74),
  SeatConfig(id: '12', label: '12', initialStatus: SeatStatus.available, dx: 0.78, dy: 0.74),
  SeatConfig(id: '13', label: '13', initialStatus: SeatStatus.available, dx: 0.22, dy: 0.90),
  SeatConfig(id: '14', label: '14', initialStatus: SeatStatus.available, dx: 0.50, dy: 0.90),
  SeatConfig(id: '15', label: '15', initialStatus: SeatStatus.available, dx: 0.78, dy: 0.90),
];

/// Plan de sièges prédéfini par type de véhicule (Phase 8). [VehicleType.van9]
/// généralise l'ancien plan Sprinter câblé en dur ; les 4 autres types sont
/// de nouveaux plans schématiques cohérents avec le même langage visuel.
const Map<VehicleType, List<SeatConfig>> kVehicleSeatLayouts = {
  VehicleType.berline: kBerlineSeatLayout,
  VehicleType.septPlaces: kSeptPlacesSeatLayout,
  VehicleType.suv: kSuvSeatLayout,
  VehicleType.van9: kVan9SeatLayout,
  VehicleType.minibus15: kMinibus15SeatLayout,
};

List<SeatConfig> seatLayoutFor(VehicleType type) =>
    kVehicleSeatLayouts[type] ?? kSeptPlacesSeatLayout;
