import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/events/data_refresh.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bottom_nav_bar.dart';
import '../../../core/widgets/glow.dart';
import '../../../core/widgets/notification_bell.dart';
import '../../../core/widgets/trip_card.dart';
import '../../../core/widgets/verification_dialog.dart';
import '../../../models/booking.dart';
import '../../../models/trip.dart';
import '../../../models/vehicle.dart';
import '../../../providers/app_provider.dart';
import '../../../services/booking_repository.dart';
import '../../../services/trip_repository.dart';
import '../../../services/vehicle_repository.dart';
import '../../../services/wallet_repository.dart';

/// Accueil chauffeur, pensé pour l'essentiel en un coup d'œil : les
/// demandes de réservation qui attendent une réponse, le prochain trajet et
/// son action, « Publier un trajet » toujours visible, puis les chiffres du
/// mois.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with AutoRefresh<HomeScreen> {
  @override
  Future<void> onAutoRefresh() => _load(silent: true);

  bool _isLoading = true;
  bool _hasError = false;
  int _upcomingCount = 0;
  double _monthRevenue = 0;
  Trip? _nextTrip;
  Vehicle? _nextTripVehicle;

  /// Demandes en attente, par trajet (dans l'ordre des départs).
  List<_PendingGroup> _pending = const [];
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (shouldPoll(context)) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void reassemble() {
    super.reassemble();
    context.read<AppProvider>().refreshUser();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    final provider = context.read<AppProvider>();
    provider.refreshUser();
    final driverId = provider.user?.id;
    if (driverId == null) return;
    if (!silent) setState(() => _isLoading = true);
    try {
      final trips = await TripRepository().fetchForDriver(driverId);
      final now = DateTime.now();
      // Un trajet en cours reste « le prochain » : c'est lui qu'il faut gérer.
      final active = trips
          .where((t) => t.status == TripStatus.inProgress || (t.status == TripStatus.upcoming && t.departureTime.isAfter(now.subtract(const Duration(hours: 2)))))
          .toList()
        ..sort((a, b) {
          if (a.status == TripStatus.inProgress) return -1;
          if (b.status == TripStatus.inProgress) return 1;
          return a.departureTime.compareTo(b.departureTime);
        });

      double monthRevenue = 0;
      try {
        final transactions = await WalletRepository().fetchTransactions();
        monthRevenue = transactions
            .where((t) =>
                t.type == 'payment' &&
                t.status == 'completed' &&
                t.createdAt.year == now.year &&
                t.createdAt.month == now.month)
            .fold<double>(0, (sum, t) => sum + t.amount);
      } catch (e) {
        debugPrint('Wallet load ignored: $e');
      }

      var pending = <_PendingGroup>[];
      try {
        final requests = await BookingRepository().fetchForDriver(driverId, status: 'pending_driver');
        final byTrip = <String, List<Booking>>{};
        for (final booking in requests.where((b) => b.status == BookingStatus.pending)) {
          byTrip.putIfAbsent(booking.tripId, () => []).add(booking);
        }
        pending = [
          for (final entry in byTrip.entries)
            _PendingGroup(
              tripId: entry.key,
              trip: trips.where((t) => t.id == entry.key).firstOrNull ?? entry.value.first.trip,
              count: entry.value.length,
            ),
        ]..sort((a, b) => (a.trip?.departureTime ?? now).compareTo(b.trip?.departureTime ?? now));
      } catch (e) {
        debugPrint('Pending requests ignored: $e');
      }

      Vehicle? vehicle;
      if (active.isNotEmpty && active.first.vehicleId.isNotEmpty) {
        try {
          vehicle = await VehicleRepository().fetch(active.first.vehicleId);
        } catch (e) {
          debugPrint('Vehicle load ignored: $e');
        }
      }

      if (!mounted) return;
      setState(() {
        _upcomingCount = active.length;
        _nextTrip = active.isEmpty ? null : active.first;
        _nextTripVehicle = vehicle;
        _monthRevenue = monthRevenue;
        _pending = pending;
        _isLoading = false;
        _hasError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  void _publish() {
    final user = context.read<AppProvider>().user;
    if (user?.isApprovedDriver != true) {
      showVerificationRequiredDialog(context, action: 'publier un trajet');
      return;
    }
    context.push('/publish-trip');
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppProvider>().user;
    final firstName = user?.name.trim().isNotEmpty == true ? user!.name.trim().split(RegExp(r'\s+')).first : null;
    final pendingTotal = _pending.fold<int>(0, (sum, g) => sum + g.count);

    return Scaffold(
      body: BrandHeaderLayout(
        onRefresh: _load,
        header: BrandHeader(
          title: firstName == null ? 'Bonjour' : 'Bonjour, $firstName',
          subtitle: _isLoading
              ? ' '
              : pendingTotal > 0
                  ? '$pendingTotal demande${pendingTotal > 1 ? 's' : ''} à traiter'
                  : _upcomingCount > 0
                      ? '$_upcomingCount trajet${_upcomingCount > 1 ? 's' : ''} à venir'
                      : 'Aucun trajet prévu',
          trailing: const NotificationBellButton(onBrand: true),
        ),
        children: [
          if (user != null && !user.isApprovedDriver) ...[
            _VerificationBanner(
              title: user.isPendingReview
                  ? 'Vérification en cours'
                  : user.isRejectedDriver
                      ? 'Dossier refusé'
                      : 'Compte non vérifié',
              body: user.isPendingReview
                  ? 'Votre dossier est en cours d’examen. Vous serez notifié dès sa validation.'
                  : user.isRejectedDriver
                      ? 'Certaines pièces ont été refusées. Mettez-les à jour pour activer votre compte.'
                      : 'Faites vérifier votre identité et ajoutez votre véhicule pour publier des trajets.',
              actionLabel: user.isPendingReview
                  ? 'Voir le statut'
                  : user.isRejectedDriver
                      ? 'Corriger mon dossier'
                      : 'Faire vérifier mon compte',
              onAction: () => context.push(user.isPendingReview ? '/verification-pending' : '/profile/identity'),
            ),
            const SizedBox(height: 16),
          ],
          for (final group in _pending) ...[
            _PendingRequestsCard(group: group),
            const SizedBox(height: 12),
          ],
          GlowButton(
            label: 'Publier un trajet',
            leadingIcon: Icons.add_rounded,
            onPressed: _publish,
          ),
          const SizedBox(height: 24),
          Text(_nextTrip?.status == TripStatus.inProgress ? 'Trajet en cours' : 'Prochain trajet', style: AppTextStyles.title2),
          const SizedBox(height: 10),
          if (_isLoading)
            const TripCardSkeleton()
          else if (_hasError)
            _Notice(
              text: 'Impossible de charger vos trajets.',
              action: 'Réessayer',
              onAction: _load,
            )
          else if (_nextTrip == null)
            const _NoTripCard()
          else
            _NextTripCard(trip: _nextTrip!, vehicle: _nextTripVehicle),
          const SizedBox(height: 24),
          Text('Ce mois-ci', style: AppTextStyles.title2),
          const SizedBox(height: 10),
          _StatsCard(
            upcomingCount: _upcomingCount,
            monthRevenue: _monthRevenue,
            rating: user?.rating ?? 0,
            loading: _isLoading,
          ),
          const SizedBox(height: 12),
          NeuBox(
            padding: EdgeInsets.zero,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: const Icon(Icons.person_search_rounded),
              title: Text('Passagers qui cherchent un trajet', style: AppTextStyles.bodySemibold),
              subtitle: Text('Leurs demandes sur votre route', style: AppTextStyles.caption),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                if (user?.isApprovedDriver != true) {
                  showVerificationRequiredDialog(context, action: 'consulter et répondre aux demandes de passagers');
                  return;
                }
                context.push('/driver/passenger-requests');
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: const DriverBottomNavBar(current: DriverTab.home),
    );
  }
}

class _PendingGroup {
  final String tripId;
  final Trip? trip;
  final int count;

  const _PendingGroup({required this.tripId, required this.trip, required this.count});
}

/// Demandes de réservation à accepter ou refuser, pour un trajet : la
/// première chose à voir en ouvrant l'app.
class _PendingRequestsCard extends StatelessWidget {
  final _PendingGroup group;

  const _PendingRequestsCard({required this.group});

  @override
  Widget build(BuildContext context) {
    final trip = group.trip;
    final when = trip == null ? '' : '${formatDayLabel(trip.departureTime)} · ${DateFormat('HH:mm').format(trip.departureTime)}';
    return Material(
      color: AppColors.brandSurface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/trip/${group.tripId}/requests'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(
                  '${group.count}',
                  style: AppTextStyles.title2.copyWith(color: AppColors.onBrand),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.count > 1 ? '${group.count} demandes à traiter' : 'Nouvelle demande à traiter',
                      style: AppTextStyles.bodySemibold.copyWith(fontWeight: FontWeight.w800),
                    ),
                    if (trip != null) ...[
                      Text(
                        '${trip.departure} → ${trip.arrival}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary),
                      ),
                      Text(when, style: AppTextStyles.caption),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.brandText),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bandeau « compte non vérifié / en cours / refusé ».
class _VerificationBanner extends StatelessWidget {
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  const _VerificationBanner({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.amberSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined, color: AppColors.amber),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: AppTextStyles.bodyLargeSemibold.copyWith(fontWeight: FontWeight.w800))),
            ],
          ),
          const SizedBox(height: 6),
          Text(body, style: AppTextStyles.body.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          GlowButton(label: actionLabel, dark: true, leadingIcon: Icons.badge_outlined, onPressed: onAction),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  final String action;
  final VoidCallback onAction;

  const _Notice({required this.text, required this.action, required this.onAction});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.muted, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: AppTextStyles.body.copyWith(color: AppColors.textSecondary))),
          TextButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    );
  }
}

class _NoTripCard extends StatelessWidget {
  const _NoTripCard();

  @override
  Widget build(BuildContext context) {
    return NeuBox(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(color: AppColors.muted, shape: BoxShape.circle),
            child: const Icon(Icons.route_rounded, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Aucun trajet prévu', style: AppTextStyles.bodyLargeSemibold),
                Text(
                  'Publiez un trajet : les passagers sur votre route pourront réserver.',
                  style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Le prochain trajet (ou celui en cours) : itinéraire, véhicule, places,
/// et l'action qui compte maintenant.
class _NextTripCard extends StatelessWidget {
  final Trip trip;
  final Vehicle? vehicle;

  const _NextTripCard({required this.trip, required this.vehicle});

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm');
    final inProgress = trip.status == TripStatus.inProgress;
    final first = trip.stops.isNotEmpty ? trip.stops.first : null;
    final last = trip.stops.length > 1 ? trip.stops.last : null;
    final arrival = last?.scheduledAt ?? trip.departureTime.add(trip.estimatedDuration);
    final booked = trip.seatsTotal > trip.availableSeats ? trip.seatsTotal - trip.availableSeats : 0;
    return NeuBox(
      onTap: () => context.push('/trip/${trip.id}'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: inProgress ? AppColors.successSurface : AppColors.muted,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  inProgress ? 'En route' : formatDayLabel(trip.departureTime),
                  style: AppTextStyles.caption.copyWith(
                    color: inProgress ? AppColors.success : AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              if (trip.stops.length > 2)
                Text('${trip.stops.length - 2} arrêt${trip.stops.length > 3 ? 's' : ''} en route', style: AppTextStyles.caption),
            ],
          ),
          const SizedBox(height: 14),
          RouteTimeline(
            stops: [
              RouteTimelineStop(
                time: time.format(first?.scheduledAt ?? trip.departureTime),
                place: first?.name ?? trip.departure,
                hint: first?.address,
              ),
              RouteTimelineStop(time: time.format(arrival), place: last?.name ?? trip.arrival, hint: last?.address),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.directions_car_outlined, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  vehicle == null ? 'Véhicule' : '${vehicle!.brand} ${vehicle!.model} · ${vehicle!.plateNumber}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.event_seat_outlined, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                booked > 0
                    ? '$booked réservée${booked > 1 ? 's' : ''} · ${trip.availableSeats} libre${trip.availableSeats > 1 ? 's' : ''}'
                    : '${trip.availableSeats} libre${trip.availableSeats > 1 ? 's' : ''}',
                style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GlowButton(
            label: inProgress ? 'Reprendre le trajet' : 'Gérer ce trajet',
            leadingIcon: inProgress ? Icons.navigation_rounded : Icons.list_alt_rounded,
            dark: true,
            onPressed: () => context.push('/trip/${trip.id}'),
          ),
        ],
      ),
    );
  }
}

/// Trajets à venir, revenu du mois et note, sur une seule carte.
class _StatsCard extends StatelessWidget {
  final int upcomingCount;
  final double monthRevenue;
  final double rating;
  final bool loading;

  const _StatsCard({required this.upcomingCount, required this.monthRevenue, required this.rating, required this.loading});

  @override
  Widget build(BuildContext context) {
    Widget stat(String value, String label, {VoidCallback? onTap}) => Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(loading ? '…' : value, maxLines: 1, style: AppTextStyles.title2),
                  ),
                  const SizedBox(height: 2),
                  Text(label, textAlign: TextAlign.center, style: AppTextStyles.caption),
                ],
              ),
            ),
          ),
        );
    return NeuBox(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: IntrinsicHeight(
        child: Row(
          children: [
            stat('$upcomingCount', upcomingCount > 1 ? 'trajets à venir' : 'trajet à venir', onTap: () => context.go('/trips')),
            const VerticalDivider(width: 1, indent: 12, endIndent: 12),
            stat(formatFcfa(monthRevenue), 'gagnés', onTap: () => context.push('/driver/earnings')),
            const VerticalDivider(width: 1, indent: 12, endIndent: 12),
            stat(rating > 0 ? '★ ${rating.toStringAsFixed(1).replaceAll('.', ',')}' : '—', 'note moyenne'),
          ],
        ),
      ),
    );
  }
}
