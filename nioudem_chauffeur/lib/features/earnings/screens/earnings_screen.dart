import 'package:flutter/material.dart';
import '../../../core/events/data_refresh.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glow.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../services/wallet_repository.dart';
import '../../../core/widgets/trip_card.dart' show formatFcfa;

enum _EarningsPeriod { day, week, month }

class _PeriodStats {
  final double total;
  final int tripCount;
  final int passengerCount;

  const _PeriodStats({required this.total, required this.tripCount, required this.passengerCount});
}

/// "Gains" (route `/driver/earnings`) : 3 onglets Jour/Semaine/Mois. Reprend
/// le même pattern que la carte "gains du mois" de `/home`
/// (`BookingRepository.fetchForDriver` + filtre `BookingStatus.confirmed`),
/// étendu à `completed` et aux 3 fenêtres temporelles, en se basant sur la
/// date de départ du trajet plutôt que la date de réservation.
class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> with SingleTickerProviderStateMixin, AutoRefresh<EarningsScreen> {
  @override
  Future<void> onAutoRefresh() => _load(silent: true);

  late final TabController _tabController =
      TabController(length: 3, vsync: this);

  bool _isLoading = true;
  bool _hasError = false;
  List<WalletTransaction> _transactions = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Basé sur le grand livre réel du wallet (`GET /wallet/transactions`,
  /// type `payment`, statut `completed`) plutôt que sur les réservations
  /// (aucun endpoint ne liste les réservations d'un chauffeur — voir
  /// `BookingRepository`). Reste vide tant que le backend ne crédite pas
  /// automatiquement le wallet chauffeur à la complétion d'une réservation
  /// (voir le commentaire dans `wallet_repository.dart`).
  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final transactions = await WalletRepository().fetchTransactions();
      final relevant = transactions
          .where((t) => t.type == 'payment' && t.status == 'completed')
          .toList();
      if (!mounted) return;
      setState(() {
        _transactions = relevant;
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

  _PeriodStats _statsFor(_EarningsPeriod period) {
    final now = DateTime.now();
    late DateTime start;
    late DateTime end;
    switch (period) {
      case _EarningsPeriod.day:
        start = DateTime(now.year, now.month, now.day);
        end = start.add(const Duration(days: 1));
        break;
      case _EarningsPeriod.week:
        final startOfDay = DateTime(now.year, now.month, now.day);
        // Semaine ISO : lundi -> dimanche.
        start = startOfDay.subtract(Duration(days: now.weekday - 1));
        end = start.add(const Duration(days: 7));
        break;
      case _EarningsPeriod.month:
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 1);
        break;
    }

    final inRange = _transactions.where((t) {
      return !t.createdAt.isBefore(start) && t.createdAt.isBefore(end);
    }).toList();

    final total = inRange.fold<double>(0, (sum, t) => sum + t.amount);
    final tripCount = inRange.map((t) => t.bookingId).whereType<String>().toSet().length;

    return _PeriodStats(total: total, tripCount: tripCount, passengerCount: inRange.length);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BrandAppBar(
        title: 'Gains',
        onBack: () => context.canPop() ? context.pop() : context.go('/home'),
        bottomHeight: 46,
        bottom: AnimatedBuilder(
          animation: _tabController,
          builder: (_, __) => GlowSegmented<int>(
            onBrand: true,
            value: _tabController.index,
            options: const [(0, 'Jour'), (1, 'Semaine'), (2, 'Mois')],
            onChanged: _tabController.animateTo,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: _isLoading
              ? const _EarningsSkeleton()
              : _hasError
                  ? _ErrorState(onRetry: _load)
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _PeriodView(stats: _statsFor(_EarningsPeriod.day), periodLabel: "aujourd'hui"),
                        _PeriodView(stats: _statsFor(_EarningsPeriod.week), periodLabel: 'cette semaine'),
                        _PeriodView(stats: _statsFor(_EarningsPeriod.month), periodLabel: 'ce mois-ci'),
                      ],
                    ),
        ),
      ),
    );
  }
}

class _PeriodView extends StatelessWidget {
  final _PeriodStats stats;
  final String periodLabel;

  const _PeriodView({required this.stats, required this.periodLabel});

  @override
  Widget build(BuildContext context) {
    if (stats.tripCount == 0 && stats.passengerCount == 0) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
        children: [
          const _EmptyEarnings(),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(AppSpacing.borderRadiusCard),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Gains $periodLabel',
                  style: AppTextStyles.body.copyWith(color: Colors.white.withOpacity(0.85))),
              const SizedBox(height: 6),
              Text(
                formatFcfa(stats.total),
                style: AppTextStyles.display.copyWith(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: Icons.route_rounded,
                value: '${stats.tripCount}',
                label: stats.tripCount > 1 ? 'trajets' : 'trajet',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatTile(
                icon: Icons.people_alt_rounded,
                value: '${stats.passengerCount}',
                label: stats.passengerCount > 1 ? 'passagers' : 'passager',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatTile({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: AppColors.softCardDecoration,
      child: Column(
        children: [
          Icon(icon, size: 22, color: AppColors.primary),
          const SizedBox(height: 8),
          Text(value, style: AppTextStyles.title2.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: AppTextStyles.caption),
        ],
      ),
    );
  }
}

class _EmptyEarnings extends StatelessWidget {
  const _EmptyEarnings();

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
            child: const Icon(Icons.account_balance_wallet_outlined,
                size: 26, color: AppColors.primary),
          ),
          const SizedBox(height: 14),
          Text('Aucun gain sur cette période', style: AppTextStyles.bodyLargeSemibold),
          const SizedBox(height: 6),
          Text(
            'Les trajets confirmés ou terminés sur cette période apparaîtront ici.',
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: AppColors.softCardDecoration,
          child: Text(
            'Impossible de charger vos gains. Tirez vers le bas pour réessayer.',
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _EarningsSkeleton extends StatelessWidget {
  const _EarningsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        children: [
          const SkeletonBox(height: 110),
          const SizedBox(height: 16),
          Row(
            children: const [
              Expanded(child: SkeletonBox(height: 90)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 90)),
            ],
          ),
        ],
      ),
    );
  }
}
