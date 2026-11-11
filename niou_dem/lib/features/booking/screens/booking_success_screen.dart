import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/glow.dart';
import '../../../core/widgets/trip_card.dart' show formatFcfa;
import '../../../models/booking.dart';
import '../../../services/booking_repository.dart';

/// Demande de réservation envoyée (ou confirmée d'office) : ce qui va se
/// passer ensuite, le récapitulatif, et l'accès au suivi de la réservation.
/// L'écran se met à jour si le chauffeur accepte pendant qu'il est ouvert.
class BookingSuccessScreen extends StatefulWidget {
  final String bookingId;

  const BookingSuccessScreen({super.key, required this.bookingId});

  @override
  State<BookingSuccessScreen> createState() => _BookingSuccessScreenState();
}

class _BookingSuccessScreenState extends State<BookingSuccessScreen> {
  Booking? _booking;
  bool _isLoading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted || _booking?.status != BookingStatus.pending) return;
      final updated = await BookingRepository().fetch(widget.bookingId);
      if (!mounted || updated == null) return;
      if (updated.status != _booking?.status) setState(() => _booking = updated);
    });
  }

  Future<void> _load() async {
    final booking = await BookingRepository().fetch(widget.bookingId);
    if (!mounted) return;
    setState(() {
      _booking = booking;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final booking = _booking;
    if (booking == null || booking.trip == null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Réservation introuvable', style: AppTextStyles.title2),
                  const SizedBox(height: 16),
                  GlowButton(label: 'Mes réservations', dark: true, expanded: false, onPressed: () => context.go('/my-trips')),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final confirmed = booking.status == BookingStatus.confirmed;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: IconButton(
                  tooltip: 'Fermer',
                  onPressed: () => context.go('/home'),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: [
                  Center(child: _StatusIcon(confirmed: confirmed)),
                  const SizedBox(height: 20),
                  Semantics(
                    header: true,
                    liveRegion: true,
                    child: Text(
                      confirmed ? 'Réservation confirmée' : 'Demande envoyée',
                      style: AppTextStyles.display.copyWith(fontSize: 26),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    // Confirmée d'office pour un trajet déjà parti, ou acceptée
                    // pendant que l'écran est ouvert.
                    confirmed
                        ? 'Votre billet est prêt. Soyez au point de rendez-vous quelques minutes avant l’heure.'
                        : 'Le chauffeur a reçu votre demande. Vous serez prévenu dès qu’il l’accepte.',
                    style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  _NextSteps(confirmed: confirmed),
                  const SizedBox(height: 20),
                  _Summary(booking: booking),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                children: [
                  GlowButton(
                    label: confirmed ? 'Voir mon billet' : 'Suivre ma réservation',
                    onPressed: () => context.go('/trip/${booking.tripId}/tracking'),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => context.go('/home'),
                    child: const Text('Retour à l’accueil'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final bool confirmed;

  const _StatusIcon({required this.confirmed});

  @override
  Widget build(BuildContext context) {
    final color = confirmed ? AppColors.success : AppColors.amber;
    final surface = confirmed ? AppColors.successSurface : AppColors.amberSurface;
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!confirmed) PulseRing(size: 96, radius: 48, color: color),
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(color: surface, shape: BoxShape.circle),
            child: Icon(confirmed ? Icons.check_rounded : Icons.hourglass_top_rounded, size: 44, color: color),
          ),
        ],
      ),
    );
  }
}

/// Les étapes jusqu'au départ, l'étape en cours mise en avant.
class _NextSteps extends StatelessWidget {
  final bool confirmed;

  const _NextSteps({required this.confirmed});

  @override
  Widget build(BuildContext context) {
    final steps = [
      ('Demande envoyée', true),
      ('Le chauffeur accepte', confirmed),
      ('Billet prêt : rendez-vous au point de montée', confirmed),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i < steps.length - 1 ? 12 : 0),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: steps[i].$2 ? AppColors.success : AppColors.surface,
                      border: Border.all(color: steps[i].$2 ? AppColors.success : AppColors.borderStrong, width: 2),
                    ),
                    child: steps[i].$2
                        ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                        : Center(child: Text('${i + 1}', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w800))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      steps[i].$1,
                      style: AppTextStyles.bodySemibold.copyWith(
                        color: steps[i].$2 ? AppColors.textPrimary : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final Booking booking;

  const _Summary({required this.booking});

  @override
  Widget build(BuildContext context) {
    final trip = booking.trip!;
    final when = booking.boardingStop?.scheduledAt ?? trip.departureTime;
    return NeuBox(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${booking.boardingStop?.name ?? trip.departure} → ${booking.alightingStop?.name ?? trip.arrival}',
            style: AppTextStyles.bodyLargeSemibold.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            toBeginningOfSentenceCase(DateFormat('EEEE d MMMM · HH:mm', 'fr_FR').format(when)) ?? '',
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
          _Row(
            icon: Icons.place_outlined,
            label: 'Rendez-vous',
            value: booking.boardingStop?.displayAddress ?? trip.departureAddress,
          ),
          if (trip.driver != null) _Row(icon: Icons.person_outline_rounded, label: 'Chauffeur', value: trip.driver!.name),
          _Row(
            icon: Icons.event_seat_outlined,
            label: booking.seatNumbers.length > 1 ? 'Places' : 'Place',
            value: booking.seatNumbers.isEmpty ? booking.seatLabel : 'n° ${booking.seatNumbers.join(', ')}',
          ),
          _Row(icon: Icons.payments_outlined, label: 'À payer au chauffeur', value: formatFcfa(booking.price), strong: true),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool strong;

  const _Row({required this.icon, required this.label, required this.value, this.strong = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Text(label, style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
          const SizedBox(width: 12),
          // Les adresses longues passent à la ligne au lieu de déborder.
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: strong ? AppTextStyles.bodyLargeSemibold.copyWith(fontWeight: FontWeight.w800) : AppTextStyles.bodySemibold,
            ),
          ),
        ],
      ),
    );
  }
}
