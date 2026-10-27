import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../models/vehicle.dart';
import '../models/seat.dart';
import '../painters/generic_vehicle_painter.dart';
import '../painters/sprinter_painter.dart';
import 'seat_indicator.dart';
import 'selection_bubble.dart';

enum SeatLayoutMode {
  /// Non interactif — utilisé dans le profil chauffeur pour visualiser le
  /// plan dès que le type de véhicule est choisi (Phase 8).
  preview,

  /// Interactif — utilisé côté passager pour choisir un siège (Phase 7),
  /// avec sièges pris/disponibles reflétant l'état réel de `seatsAvailable`.
  selection,
}

/// Plan de sièges générique, paramétré par [VehicleType] : remplace l'ancien
/// `InteractiveSeatMap` câblé en dur sur le Sprinter. Le rendu de la
/// carrosserie (Sprinter réaliste pour le van 9 places, silhouette générique
/// pour les autres) est un détail d'implémentation caché derrière ce widget.
class SeatLayoutWidget extends StatelessWidget {
  final VehicleType vehicleType;
  final SeatLayoutMode mode;
  final Set<String> occupiedSeatIds;
  final String? selectedSeatId;
  final ValueChanged<String>? onSeatTap;

  const SeatLayoutWidget({
    super.key,
    required this.vehicleType,
    required this.mode,
    this.occupiedSeatIds = const {},
    this.selectedSeatId,
    this.onSeatTap,
  });

  static const double _kIndicatorRadiusFraction = 0.072;

  double get _aspect {
    switch (vehicleType) {
      case VehicleType.van9:
        return 0.520;
      case VehicleType.minibus15:
        return 0.480;
      case VehicleType.berline:
        return 0.680;
      case VehicleType.septPlaces:
        return 0.600;
      case VehicleType.suv:
        return 0.620;
    }
  }

  @override
  Widget build(BuildContext context) {
    final template = seatLayoutFor(vehicleType);
    final seats = template.map((config) {
      SeatStatus status;
      if (config.initialStatus == SeatStatus.driver) {
        status = SeatStatus.driver;
      } else if (mode == SeatLayoutMode.selection && config.id == selectedSeatId) {
        status = SeatStatus.selected;
      } else if (mode == SeatLayoutMode.selection && occupiedSeatIds.contains(config.id)) {
        status = SeatStatus.occupied;
      } else {
        status = SeatStatus.available;
      }
      return SeatState(config: config, status: status);
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = constraints.maxWidth;
        final availH = constraints.maxHeight.isInfinite ? availW / _aspect : constraints.maxHeight;
        final naturalH = availW / _aspect;
        final h = math.min(naturalH, availH);
        final w = h * _aspect;
        final radius = w * _kIndicatorRadiusFraction;

        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CustomPaint(
                      painter: vehicleType == VehicleType.van9
                          ? const SprinterPainter()
                          : const GenericVehiclePainter(),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                ...seats.map(
                  (seat) => _buildSeatLayer(
                    seat: seat,
                    containerW: w,
                    containerH: h,
                    radius: radius,
                    onTap: mode == SeatLayoutMode.selection && seat.isInteractive
                        ? () => onSeatTap?.call(seat.config.id)
                        : null,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSeatLayer({
    required SeatState seat,
    required double containerW,
    required double containerH,
    required double radius,
    required VoidCallback? onTap,
  }) {
    final cx = seat.config.dx * containerW;
    final cy = seat.config.dy * containerH;

    if (seat.isSelected && mode == SeatLayoutMode.selection) {
      const bubbleH = 40.0;
      const bubbleW = 148.0;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: cx - bubbleW / 2,
            top: cy - radius * 1.15 - bubbleH - 2,
            width: bubbleW,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              builder: (_, v, child) => Opacity(opacity: v, child: child),
              child: SelectionBubble(seatLabel: seat.config.label),
            ),
          ),
          Positioned(
            left: cx - radius * 1.15,
            top: cy - radius * 1.15,
            child: SeatIndicator(seat: seat, radius: radius, onTap: onTap),
          ),
        ],
      );
    }

    return Positioned(
      left: cx - radius,
      top: cy - radius,
      child: SeatIndicator(seat: seat, radius: radius, onTap: onTap),
    );
  }
}

/// Libellé utilitaire pour l'en-tête des écrans qui affichent ce plan.
String vehicleSeatSummaryLabel(VehicleType type) =>
    '${type.label} · ${type.passengerSeatCount} places passagers';
