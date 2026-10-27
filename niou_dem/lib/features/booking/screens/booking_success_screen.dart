import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/fojem_button.dart';
import '../../../core/widgets/price_display.dart';
import '../../../core/widgets/fojem_logo.dart';
import '../../../models/booking.dart';
import '../../../services/booking_repository.dart';

/// Confirmation d'une **demande** de réservation envoyée au chauffeur
/// (statut `pending`, Phase 7) — code de confirmation généré et QR réel
/// (contenant l'id de réservation), plus de code/QR en dur.
class BookingSuccessScreen extends StatefulWidget {
  final String bookingId;

  const BookingSuccessScreen({super.key, required this.bookingId});

  @override
  State<BookingSuccessScreen> createState() => _BookingSuccessScreenState();
}

class _BookingSuccessScreenState extends State<BookingSuccessScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;
  Booking? _booking;
  bool _isLoading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 1.0),
      ),
    );
    _controller.forward();

    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted) return;
      if (_booking?.status == BookingStatus.pending) {
        final updated = await BookingRepository().fetch(widget.bookingId);
        if (!mounted || updated == null) return;
        if (updated.status != _booking?.status) {
          setState(() => _booking = updated);
        }
      }
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
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    final booking = _booking;
    if (booking == null || booking.trip == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: Text('Réservation introuvable')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: AppSpacing.pagePadding.copyWith(top: AppSpacing.md, bottom: AppSpacing.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const FojemLogo.icon(),
                  Icon(Icons.notifications_outlined, color: AppColors.textPrimary, size: 26),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  children: [
                    const SizedBox(height: AppSpacing.xl),
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _scaleAnim.value,
                          child: Opacity(
                            opacity: _controller.value.clamp(0.0, 1.0),
                            child: child,
                          ),
                        );
                      },
                      child: _SuccessIcon(),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AnimatedBuilder(
                      animation: _fadeAnim,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _fadeAnim.value,
                          child: child,
                        );
                      },
                      child: Column(
                        children: [
                          Text(
                            'Demande envoyée !',
                            style: AppTextStyles.title1,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Votre demande a été transmise au chauffeur. '
                            'Vous serez notifié dès qu\'il l\'accepte.',
                            style: AppTextStyles.bodyLarge.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          const _PendingTicketCard(),
                          const SizedBox(height: AppSpacing.lg),
                          _TripSummaryCard(booking: booking),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  FojemButton.primary(
                    label: 'Voir mes réservations',
                    onPressed: () => context.go('/my-trips'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FojemButton.ghost(
                    label: 'Retour à l\'accueil',
                    onPressed: () => context.go('/home'),
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

class _SuccessIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: const BoxDecoration(
        color: AppColors.successSurface,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.check_circle_outline,
        size: 52,
        color: AppColors.success,
      ),
    );
  }
}

/// Le billet (code + QR d'embarquement) n'est attribué qu'après
/// acceptation par le chauffeur : il apparaît alors dans le suivi du trajet.
class _PendingTicketCard extends StatelessWidget {
  const _PendingTicketCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top_rounded, color: Color(0xFFD97706), size: 30),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('En attente du chauffeur', style: AppTextStyles.bodySemibold),
                const SizedBox(height: 4),
                Text(
                  'Votre billet et votre QR code d\'embarquement seront '
                  'disponibles dans le suivi du trajet dès que le chauffeur '
                  'aura accepté votre demande.',
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13,
                    color: AppColors.textSecondary,
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

class _TripSummaryCard extends StatelessWidget {
  final Booking booking;

  const _TripSummaryCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final trip = booking.trip!;
    final timeFormat = DateFormat('HH:mm');
    final dateFormat = DateFormat('EEE d MMMM', 'fr_FR');

    return Container(
      width: double.infinity,
      padding: AppSpacing.cardPadding,
      decoration: AppColors.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Récapitulatif', style: AppTextStyles.bodySemibold),
          const SizedBox(height: AppSpacing.md),
          _Row(
            label: 'Trajet',
            value: '${booking.boardingStop?.name ?? trip.departure} → '
                '${booking.alightingStop?.name ?? trip.arrival}',
          ),
          _Row(
            label: 'Date',
            value: dateFormat.format(booking.boardingStop?.scheduledAt ?? trip.departureTime),
          ),
          _Row(
            label: 'Rendez-vous',
            value: [
              timeFormat.format(booking.boardingStop?.scheduledAt ?? trip.departureTime),
              booking.boardingStop?.displayAddress ?? trip.departureAddress,
            ].join(' · '),
          ),
          _Row(
            label: 'Chauffeur',
            value: trip.driver?.name ?? '—',
          ),
          _Row(
            label: booking.seatNumbers.length > 1 ? 'Places' : 'Place',
            value: booking.seatNumbers.isEmpty
                ? booking.seatLabel
                : '#${booking.seatNumbers.join(', ')}',
          ),
          const Divider(height: AppSpacing.md, color: AppColors.border),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text('Montant à régler au chauffeur', style: AppTextStyles.bodySemibold)),
              const SizedBox(width: AppSpacing.sm),
              PriceDisplay(amount: booking.price),
            ],
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;

  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
          const SizedBox(width: AppSpacing.md),
          // Les adresses longues passent à la ligne au lieu de déborder.
          Expanded(
            child: Text(value, textAlign: TextAlign.end, style: AppTextStyles.bodySemibold),
          ),
        ],
      ),
    );
  }
}
