import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../models/trip.dart';
import '../../../services/trip_repository.dart';
import '../providers/seat_selection_provider.dart';
import '../widgets/reservation_bar.dart';
import '../widgets/seat_layout_widget.dart';
import '../../../core/widgets/glow.dart';

/// Écran principal de sélection de place — "Choix de votre place".
///
/// Charge le trajet réel ([TripRepository]) pour connaître le véhicule
/// (Phase 8) et le prix (Phase 7) avant de construire le plan de sièges —
/// plus de van Sprinter/prix fixes indépendants du trajet consulté.
class SeatSelectionScreen extends StatefulWidget {
  final String? tripId;

  /// Tronçon choisi sur le détail du trajet (prix et réservation).
  final String? boardingStopId;
  final String? alightingStopId;

  const SeatSelectionScreen(
      {super.key, this.tripId, this.boardingStopId, this.alightingStopId});

  @override
  State<SeatSelectionScreen> createState() => _SeatSelectionScreenState();
}

class _SeatSelectionScreenState extends State<SeatSelectionScreen> {
  Trip? _trip;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tripId = widget.tripId;
    final trip = tripId == null ? null : await TripRepository().fetch(tripId);
    if (!mounted) return;
    setState(() {
      _trip = trip;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body:
            Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    if (_trip == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(backgroundColor: AppColors.surface, elevation: 0),
        body: const Center(child: Text('Trajet introuvable')),
      );
    }

    final segment = _trip!.segment(
      boardingStopId: widget.boardingStopId,
      alightingStopId: widget.alightingStopId,
    );
    return ChangeNotifierProvider(
      create: (_) => SeatSelectionProvider.forTrip(_trip!,
          pricePerSeat: segment.pricePerSeat),
      child: _SeatSelectionContent(
        tripId: _trip!.id,
        segmentQuery: [
          if (segment.boarding != null) 'board=${segment.boarding!.id}',
          if (segment.alighting != null) 'alight=${segment.alighting!.id}',
        ].join('&'),
      ),
    );
  }
}

class _SeatSelectionContent extends StatelessWidget {
  final String tripId;

  /// `board=…&alight=…`, relayé à l'écran de confirmation.
  final String segmentQuery;
  const _SeatSelectionContent(
      {required this.tripId, required this.segmentQuery});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            Consumer<SeatSelectionProvider>(
              builder: (context, provider, _) => BrandHeader(
                title: 'Choix de votre place',
                subtitle: provider.availableCount > 1
                    ? 'Jusqu’à ${provider.availableCount} places · '
                        '${provider.availableCount}/${provider.totalPassengerSeats} disponibles'
                    : '${provider.availableCount}/${provider.totalPassengerSeats} place disponible',
                onBack: () => context.canPop() ? context.pop() : null,
              ),
            ),
            Expanded(
              child: Transform.translate(
                offset: const Offset(0, -40),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GlassPanel(
                    radius: 40,
                    padding: const EdgeInsets.all(18),
                    child: Consumer<SeatSelectionProvider>(
                      builder: (context, provider, _) {
                        return SeatLayoutWidget(
                          vehicleType: provider.vehicleType,
                          mode: SeatLayoutMode.selection,
                          selectedSeatIds: provider.selectedSeatIds,
                          occupiedSeatIds: provider.seats
                              .where((s) => s.isOccupied)
                              .map((s) => s.config.id)
                              .toSet(),
                          onSeatTap: (seatId) {
                            final refusal = provider.toggleSeat(seatId);
                            if (refusal != null) {
                              ScaffoldMessenger.of(context)
                                ..hideCurrentSnackBar()
                                ..showSnackBar(
                                    SnackBar(content: Text(refusal)));
                            }
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            const _SeatLegend(),
            const SizedBox(height: 96),
          ],
        ),
        bottomNavigationBar: ReservationBar(
          onConfirm: () => _onConfirm(context),
        ),
      ),
    );
  }

  void _onConfirm(BuildContext context) {
    final provider = context.read<SeatSelectionProvider>();
    if (!provider.hasSelection) return;
    final seatIds = provider.selectedSeats.map((s) => s.config.id).join(',');

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConfirmationSheet(
        selectionLabel: provider.selectionLabel,
        price: provider.formattedPrice,
        onConfirmed: () {
          Navigator.of(context).pop();
          context.push(
            '/booking/confirm?tripId=$tripId&seats=${Uri.encodeComponent(seatIds)}'
            '${segmentQuery.isEmpty ? '' : '&$segmentQuery'}',
          );
        },
      ),
    );
  }
}

// ── Légende (Disponible / Choisi / Occupé) ─────────────────────────────────
class _SeatLegend extends StatelessWidget {
  const _SeatLegend();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _LegendItem(
            label: 'Disponible',
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border, width: 1.5),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 20),
          _LegendItem(
            label: 'Choisi',
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 20),
          _LegendItem(
            label: 'Occupé',
            decoration: BoxDecoration(
              color: const Color(0xFF7A7A7A),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final String label;
  final BoxDecoration decoration;

  const _LegendItem({required this.label, required this.decoration});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 14, height: 14, decoration: decoration),
        const SizedBox(width: 6),
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}

// ── Bottom sheet de confirmation ───────────────────────────────────────────
class _ConfirmationSheet extends StatelessWidget {
  final String selectionLabel;
  final String price;
  final VoidCallback onConfirmed;

  const _ConfirmationSheet({
    required this.selectionLabel,
    required this.price,
    required this.onConfirmed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: AppColors.primarySurface,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.event_seat_rounded,
                color: AppColors.primary, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            'Confirmer : $selectionLabel ?',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Montant à payer : $price',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text('Annuler',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onConfirmed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text('Confirmer',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
