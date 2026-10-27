import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/events/data_refresh.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bottom_nav_bar.dart';
import '../../../core/widgets/glow.dart';
import '../../../core/widgets/trip_card.dart';
import '../../../core/widgets/fojem_button.dart';
import '../../../core/widgets/notification_bell.dart';
import '../../../core/widgets/verification_dialog.dart';
import '../../../models/trip.dart';
import '../../../models/vehicle.dart';
import '../../../providers/app_provider.dart';
import '../../../services/trip_repository.dart';
import '../../../services/vehicle_repository.dart';
import '../../../services/wallet_repository.dart';

/// Tableau de bord chauffeur — logo + cloche, salutation, 3 cartes de
/// statistiques (trajets à venir, revenu du mois, note moyenne), prochain
/// trajet à gérer, et l'entrée vers la publication d'un trajet.
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
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 12), (_) => _load(silent: true));
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
    if (!silent) {
      setState(() => _isLoading = true);
    }
    try {
      final trips = await TripRepository().fetchForDriver(driverId);
      final now = DateTime.now();
      final upcoming = trips
          .where((t) =>
              t.status == TripStatus.upcoming &&
              t.departureTime.isAfter(now))
          .toList()
        ..sort((a, b) => a.departureTime.compareTo(b.departureTime));

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

      Vehicle? vehicle;
      if (upcoming.isNotEmpty && upcoming.first.vehicleId.isNotEmpty) {
        try {
          vehicle = await VehicleRepository().fetch(upcoming.first.vehicleId);
        } catch (e) {
          debugPrint('Vehicle load ignored: $e');
        }
      }

      if (!mounted) return;
      setState(() {
        _upcomingCount = upcoming.length;
        _nextTrip = upcoming.isEmpty ? null : upcoming.first;
        _nextTripVehicle = vehicle;
        _monthRevenue = monthRevenue;
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

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppProvider>().user;
    final firstName = user?.name.trim().isNotEmpty == true
        ? user!.name.trim().split(RegExp(r'\s+')).first
        : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: BrandHeaderLayout(
        onRefresh: _load,
        header: BrandHeader(
          title: firstName == null ? 'Bonjour' : 'Bonjour, $firstName',
          subtitle: 'Gérez vos trajets et vos passagers',
          trailing: const NotificationBellButton(onBrand: true),
          overlap: 72,
        ),
        children: [
          RiseIn(
            child: _isLoading
                ? const _StatsRowSkeleton()
                : _StatsRow(
                    upcomingCount: _upcomingCount,
                    monthRevenue: _monthRevenue,
                    rating: user?.rating ?? 0,
                  ),
          ),
          if (user != null && !user.isApprovedDriver) ...[
            const SizedBox(height: 18),
            RiseIn(
              delay: const Duration(milliseconds: 60),
              child: _VerificationBanner(
                title: user.isPendingReview
                    ? 'Vérification en cours'
                    : user.isRejectedDriver
                        ? 'Dossier refusé'
                        : 'Compte non vérifié',
                body: user.isPendingReview
                    ? 'Votre dossier est en cours d’examen par notre équipe. Vous serez notifié dès sa validation.'
                    : user.isRejectedDriver
                        ? 'Certaines pièces de votre dossier ont été refusées. Mettez-les à jour pour activer votre compte.'
                        : 'Faites vérifier votre identité et ajoutez votre véhicule pour pouvoir publier des trajets.',
                actionLabel: user.isPendingReview
                    ? 'Voir le statut'
                    : user.isRejectedDriver
                        ? 'Corriger mon dossier'
                        : 'Faire vérifier mon compte',
                onAction: () => context.push(user.isPendingReview ? '/verification-pending' : '/profile/identity'),
              ),
            ),
          ],
          const SizedBox(height: 26),
          Text('Prochain trajet', style: AppTextStyles.title2),
          const SizedBox(height: 12),
          if (_isLoading)
            const TripCardSkeleton()
          else if (_hasError)
            const _InlineNotice(
              text: 'Impossible de charger vos trajets. Tirez vers le bas pour réessayer.',
            )
          else if (_nextTrip == null)
            const _NoTripCard()
          else
            RiseIn(
              delay: const Duration(milliseconds: 120),
              child: _NextTripCard(trip: _nextTrip!, vehicle: _nextTripVehicle),
            ),
          const SizedBox(height: 26),
          Text('Vous souhaitez publier un trajet ?', style: AppTextStyles.bodyLargeSemibold),
          const SizedBox(height: 12),
          NeuButton(
            label: 'Publier un trajet',
            icon: Icons.add_circle_outline_rounded,
            onPressed: () {
              if (user?.isApprovedDriver != true) {
                showVerificationRequiredDialog(context, action: 'publier un trajet');
                return;
              }
              context.push('/publish-trip');
            },
          ),
          const SizedBox(height: 14),
          NeuButton(
            label: 'Demandes de passagers sur ma route',
            icon: Icons.person_search_rounded,
            color: AppColors.textPrimary,
            onPressed: () {
              if (user?.isApprovedDriver != true) {
                showVerificationRequiredDialog(
                  context,
                  action: 'consulter et répondre aux demandes de passagers',
                );
                return;
              }
              context.push('/driver/passenger-requests');
            },
          ),
        ],
      ),
      bottomNavigationBar: const DriverBottomNavBar(current: DriverTab.home),
    );
  }
}

/// Bandeau « compte non vérifié / en cours / refusé », en verre teinté.
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
    return GlassPanel(
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.shield_outlined, color: AppColors.accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: AppTextStyles.bodyLargeSemibold.copyWith(fontWeight: FontWeight.w800))),
            ],
          ),
          const SizedBox(height: 10),
          Text(body, style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 14),
          GlowButton(label: actionLabel, leadingIcon: Icons.badge_outlined, onPressed: onAction),
        ],
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  final String text;

  const _InlineNotice({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: AppColors.softCardDecoration,
      child: Text(text,
          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
    );
  }
}

class _NoTripCard extends StatelessWidget {
  const _NoTripCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: AppColors.softCardDecoration,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: AppColors.primarySurface,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.route_rounded,
                size: 26, color: AppColors.primary),
          ),
          const SizedBox(height: 14),
          Text('Aucun trajet prévu', style: AppTextStyles.bodyLargeSemibold),
          const SizedBox(height: 6),
          Text(
            'Publiez un trajet pour commencer à recevoir des passagers.',
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ─── Cartes de statistiques ────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final int upcomingCount;
  final double monthRevenue;
  final double rating;

  const _StatsRow({
    required this.upcomingCount,
    required this.monthRevenue,
    required this.rating,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            iconBg: AppColors.primarySurface,
            iconColor: AppColors.primary,
            icon: Icons.calendar_month_rounded,
            value: '$upcomingCount',
            label: upcomingCount > 1 ? 'trajets à venir' : 'trajet à venir',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            iconBg: AppColors.successSurface,
            iconColor: AppColors.success,
            icon: Icons.account_balance_wallet_rounded,
            value: formatFcfaShort(monthRevenue),
            label: 'ce mois-ci',
            onTap: () => context.push('/driver/earnings'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            iconBg: const Color(0xFFFFF1D6),
            iconColor: const Color(0xFFE8A317),
            icon: Icons.star_rounded,
            value: rating > 0 ? rating.toStringAsFixed(1).replaceAll('.', ',') : '—',
            label: 'note moyenne',
          ),
        ),
      ],
    );
  }
}

/// "18 500" sans "FCFA" — la carte affiche déjà l'unité sur une ligne
/// séparée, comme sur la maquette.
String formatFcfaShort(num amount) => formatFcfa(amount).replaceAll(' FCFA', '');

class _StatCard extends StatelessWidget {
  final Color iconBg;
  final Color iconColor;
  final IconData icon;
  final String value;
  final String label;
  final VoidCallback? onTap;

  const _StatCard({
    required this.iconBg,
    required this.iconColor,
    required this.icon,
    required this.value,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: AppColors.softCardDecoration,
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.title2.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(fontSize: 11.5),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
      child: content,
    );
  }
}

class _StatsRowSkeleton extends StatelessWidget {
  const _StatsRowSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget card() => Expanded(
          child: Container(
            height: 108,
            decoration: AppColors.softCardDecoration,
          ),
        );
    return Row(
      children: [card(), const SizedBox(width: 10), card(), const SizedBox(width: 10), card()],
    );
  }
}

// ─── Carte "Prochain trajet" ────────────────────────────────────────────────

class _NextTripCard extends StatelessWidget {
  final Trip trip;
  final Vehicle? vehicle;

  const _NextTripCard({required this.trip, required this.vehicle});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppColors.softCardDecoration,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(trip.departure,
                    style: AppTextStyles.title1.copyWith(fontSize: 20)),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Icon(Icons.arrow_forward_rounded,
                    size: 20, color: AppColors.primary),
              ),
              Expanded(
                child: Text(
                  trip.arrival,
                  textAlign: TextAlign.right,
                  style: AppTextStyles.title1.copyWith(fontSize: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 16),
          _InfoRow(
            icon: Icons.access_time_rounded,
            child: Text(
              '${formatDayLabel(trip.departureTime)} • '
              '${trip.departureTime.hour.toString().padLeft(2, '0')}:'
              '${trip.departureTime.minute.toString().padLeft(2, '0')}',
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15.5),
            ),
          ),
          const SizedBox(height: 12),
          _InfoRow(
            icon: Icons.directions_car_outlined,
            child: Text(
              vehicle == null ? 'Véhicule' : '${vehicle!.brand} ${vehicle!.model}',
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15.5),
            ),
            trailing: vehicle == null
                ? null
                : _Pill(text: vehicle!.plateNumber),
          ),
          const SizedBox(height: 12),
          _InfoRow(
            icon: Icons.people_alt_outlined,
            child: Text(
              '${trip.availableSeats} places restantes',
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15.5),
            ),
            trailing: SeatCountBadge(count: trip.availableSeats),
          ),
          const SizedBox(height: 18),
          FojemButton.primary(
            label: 'Voir et gérer ce trajet',
            prefixIcon: Icons.list_alt_rounded,
            onPressed: () => context.push('/trip/${trip.id}'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  const _InfoRow({required this.icon, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: 12),
        Expanded(child: child),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;

  const _Pill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusSm),
      ),
      child: Text(text, style: AppTextStyles.label.copyWith(fontSize: 12.5)),
    );
  }
}
