import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/driver_avatar.dart';
import '../../../core/widgets/fojem_logo.dart';
import '../../../core/widgets/trip_card.dart' show formatDayLabel;
import '../../../core/widgets/fojem_button.dart';
import '../../../models/booking.dart';
import '../../../models/trip.dart';
import '../../../services/booking_repository.dart';
import '../../../services/trip_repository.dart';

/// Demandes de réservation reçues sur un trajet (design/screens/
/// fojem_booking_requests.png) : en-tête, résumé du trajet, une carte par
/// demande en attente avec Accepter/Refuser.
class BookingRequestsScreen extends StatefulWidget {
  final String tripId;

  const BookingRequestsScreen({super.key, required this.tripId});

  @override
  State<BookingRequestsScreen> createState() => _BookingRequestsScreenState();
}

class _BookingRequestsScreenState extends State<BookingRequestsScreen> {
  Trip? _trip;
  List<Booking> _pending = [];
  bool _isLoading = true;
  String? _unavailableMessage;
  final _processingIds = <String>{};
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _unavailableMessage = null;
      });
    }
    try {
      final trip = await TripRepository().fetch(widget.tripId);
      try {
        final bookings = await BookingRepository().fetchForTrip(widget.tripId);
        if (!mounted) return;
        setState(() {
          _trip = trip;
          _pending = bookings.where((b) => b.status == BookingStatus.pending).toList();
          _isLoading = false;
        });
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() {
          _trip = trip;
          _pending = [];
          _unavailableMessage = e.message;
          _isLoading = false;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _unavailableMessage = e.message;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _respond(Booking booking, {required bool accept}) async {
    setState(() => _processingIds.add(booking.id));
    try {
      if (accept) {
        await BookingRepository().accept(booking.id);
      } else {
        await BookingRepository().refuse(booking.id);
      }
      if (!mounted) return;
      setState(() {
        _pending.removeWhere((b) => b.id == booking.id);
        _processingIds.remove(booking.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept
              ? 'Réservation acceptée.'
              : 'Réservation refusée.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _processingIds.remove(booking.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Échec de la mise à jour. Réessayez.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
                    icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
                  ),
                  Text('Demandes reçues',
                      style: AppTextStyles.title2.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  const FojemLogo.icon(size: 36),
                  const Spacer(),
                  IconButton(
                    onPressed: () => context.push('/notifications'),
                    icon: const Icon(Icons.notifications_none_rounded,
                        size: 24, color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),
            if (_trip != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: _TripSummaryBar(trip: _trip!),
              ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.5),
                    )
                  : _unavailableMessage != null
                      ? _UnavailableState(message: _unavailableMessage!)
                      : _pending.isEmpty
                      ? const _EmptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                          itemCount: _pending.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 16),
                          itemBuilder: (context, index) {
                            final booking = _pending[index];
                            return _RequestCard(
                              booking: booking,
                              isProcessing: _processingIds.contains(booking.id),
                              onAccept: () => _respond(booking, accept: true),
                              onRefuse: () => _respond(booking, accept: false),
                            );
                          },
                        ),
            ),
            if (!_isLoading)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_active_outlined,
                          size: 20, color: AppColors.textSecondary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Le passager sera notifié dès que vous acceptez ou refusez sa demande.',
                          style: AppTextStyles.caption.copyWith(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TripSummaryBar extends StatelessWidget {
  final Trip trip;

  const _TripSummaryBar({required this.trip});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: AppColors.softCardDecoration,
      child: Row(
        children: [
          Text(trip.departure, style: AppTextStyles.bodyLargeSemibold),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.primary),
          ),
          Text(trip.arrival, style: AppTextStyles.bodyLargeSemibold),
          const SizedBox(width: 8),
          Text('·', style: AppTextStyles.body.copyWith(color: AppColors.textMuted)),
          const SizedBox(width: 8),
          Text(
            '${formatDayLabel(trip.departureTime)} · '
            '${trip.departureTime.hour.toString().padLeft(2, '0')}:'
            '${trip.departureTime.minute.toString().padLeft(2, '0')}',
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary, fontSize: 13.5),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatefulWidget {
  final Booking booking;
  final bool isProcessing;
  final VoidCallback onAccept;
  final VoidCallback onRefuse;

  const _RequestCard({
    required this.booking,
    required this.isProcessing,
    required this.onAccept,
    required this.onRefuse,
  });

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  void _showPhotoDialog(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: InteractiveViewer(
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => Container(
                    width: 260,
                    height: 260,
                    color: Colors.black26,
                    child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    width: 260,
                    height: 260,
                    color: Colors.black26,
                    child: const Center(
                      child: Icon(Icons.broken_image, color: Colors.white, size: 40),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.booking.passengerName.isNotEmpty
        ? widget.booking.passengerName
        : 'Passager';
    return Container(
      decoration: AppColors.softCardDecoration,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DriverAvatar(name: name, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyLargeSemibold.copyWith(fontSize: 17)),
              ),
              const _PendingChip(),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.event_seat_outlined, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text('Places demandées',
                  style: AppTextStyles.body.copyWith(color: AppColors.textSecondary, fontSize: 14)),
              const SizedBox(width: 8),
              Container(
                constraints: const BoxConstraints(minWidth: 22),
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.seatBadge,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${widget.booking.seatsBooked}',
                  style: AppTextStyles.label.copyWith(color: Colors.white, fontSize: 12, height: 1),
                ),
              ),
              if (widget.booking.seatNumbers.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'n° ${widget.booking.seatNumbers.join(', ')}',
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySemibold.copyWith(fontSize: 14),
                  ),
                ),
              ],
            ],
          ),

          // Signalement des bagages lourds / volumineux
          if (widget.booking.hasHeavyLuggage) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.amberSurface,
                borderRadius: BorderRadius.circular(AppSpacing.borderRadiusSm),
                border: Border.all(color: AppColors.amber.withOpacity(0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.luggage_rounded, size: 16, color: AppColors.amber),
                  const SizedBox(width: 6),
                  Text(
                    'Bagages volumineux signalés',
                    style: AppTextStyles.label.copyWith(color: AppColors.amber, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            if (widget.booking.luggagePhotoUrls.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Photos des bagages (appuyez pour agrandir) :',
                style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 68,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.booking.luggagePhotoUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) {
                    final url = widget.booking.luggagePhotoUrls[i];
                    return GestureDetector(
                      onTap: () => _showPhotoDialog(context, url),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusSm),
                        child: Stack(
                          children: [
                            CachedNetworkImage(
                              imageUrl: url,
                              width: 68,
                              height: 68,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                width: 68,
                                height: 68,
                                color: AppColors.background,
                                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                width: 68,
                                height: 68,
                                color: AppColors.border,
                                child: const Icon(Icons.broken_image, size: 20, color: AppColors.textMuted),
                              ),
                            ),
                            Positioned(
                              right: 2,
                              bottom: 2,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.zoom_in, color: Colors.white, size: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FojemButton.primary(
                  label: 'Accepter',
                  isLoading: widget.isProcessing,
                  onPressed: widget.isProcessing ? null : widget.onAccept,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FojemButton.dangerOutline(
                  label: 'Refuser',
                  onPressed: widget.isProcessing ? null : widget.onRefuse,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PendingChip extends StatelessWidget {
  const _PendingChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.access_time_filled_rounded, size: 13, color: AppColors.primary),
          const SizedBox(width: 4),
          Text('En attente',
              style: AppTextStyles.label.copyWith(color: AppColors.primary, fontSize: 11)),
        ],
      ),
    );
  }
}

class _UnavailableState extends StatelessWidget {
  final String message;

  const _UnavailableState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 44, color: AppColors.borderStrong),
            const SizedBox(height: 16),
            Text('Impossible de charger les demandes', style: AppTextStyles.bodyLargeSemibold),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 44, color: AppColors.borderStrong),
            const SizedBox(height: 16),
            Text('Aucune demande en attente', style: AppTextStyles.bodyLargeSemibold),
            const SizedBox(height: 6),
            Text(
              'Les nouvelles demandes de réservation sur ce trajet apparaîtront ici.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
