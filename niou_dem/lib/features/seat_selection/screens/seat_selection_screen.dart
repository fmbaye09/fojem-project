import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../models/proposed_stop.dart';
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

  /// Point proposé par le passager à la place d'un arrêt.
  final ProposedStop? proposal;

  /// Ouvert depuis le récapitulatif : « Valider » rend les places choisies
  /// (`context.pop(List<String>)`) au lieu d'ouvrir le récapitulatif.
  final bool pickOnly;

  const SeatSelectionScreen({
    super.key,
    this.tripId,
    this.boardingStopId,
    this.alightingStopId,
    this.proposal,
    this.pickOnly = false,
  });

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
      proposal: widget.proposal,
    );
    return ChangeNotifierProvider(
      create: (_) => SeatSelectionProvider.forTrip(_trip!,
          pricePerSeat: segment.pricePerSeat),
      child: _SeatSelectionContent(
        tripId: _trip!.id,
        pickOnly: widget.pickOnly,
        segmentQuery: [
          if (segment.query.isNotEmpty) segment.query,
          if (widget.proposal != null) 'proposal=${widget.proposal!.toQuery()}',
        ].join('&'),
      ),
    );
  }
}

class _SeatSelectionContent extends StatelessWidget {
  final String tripId;

  /// `board=…&alight=…`, relayé à l'écran de confirmation.
  final String segmentQuery;
  final bool pickOnly;
  const _SeatSelectionContent({required this.tripId, required this.segmentQuery, required this.pickOnly});

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
                title: 'Choisissez vos places',
                subtitle: provider.availableCount > 1
                    ? '${provider.availableCount} places libres · touchez un siège'
                    : '${provider.availableCount} place libre · touchez un siège',
                onBack: () => context.canPop() ? context.pop() : null,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: GlassPanel(
                    radius: 24,
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
            const _SeatLegend(),
          ],
        ),
        bottomNavigationBar: ReservationBar(
          label: pickOnly ? 'Valider' : 'Continuer',
          onConfirm: () => _onConfirm(context),
        ),
      ),
    );
  }

  /// Places choisies : rendues au récapitulatif qui a ouvert le plan, ou
  /// récapitulatif ouvert directement (sans fenêtre de confirmation : c'est
  /// le récapitulatif qui envoie la demande).
  void _onConfirm(BuildContext context) {
    final provider = context.read<SeatSelectionProvider>();
    if (!provider.hasSelection) return;
    final seats = provider.selectedSeats.map((s) => s.config.id).toList();
    if (pickOnly) {
      context.pop(seats);
      return;
    }
    context.push(
      '/booking/confirm?tripId=$tripId&seats=${Uri.encodeComponent(seats.join(','))}'
      '${segmentQuery.isEmpty ? '' : '&$segmentQuery'}',
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
          // Mêmes couleurs que les pastilles du plan (SeatIndicator).
          _LegendItem(
            label: 'Disponible',
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 20),
          _LegendItem(
            label: 'Choisi',
            decoration: BoxDecoration(
              color: AppColors.accent,
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

