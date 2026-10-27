import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/driver_avatar.dart';
import '../../../core/widgets/star_rating.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../models/driver.dart';
import '../../../services/driver_repository.dart';

class DriverProfileScreen extends StatefulWidget {
  final String driverId;

  const DriverProfileScreen({super.key, required this.driverId});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  Driver? _driver;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final driver = await DriverRepository().fetch(widget.driverId);
    if (!mounted) return;
    setState(() {
      _driver = driver;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    final driver = _driver;
    if (driver == null) {
      return Scaffold(
        appBar: AppBar(leading: IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back))),
        body: const Center(child: Text('Profil introuvable')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          _DriverProfileAppBar(driver: driver),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatsRow(driver: driver),
                  const SizedBox(height: AppSpacing.lg),
                  _VehicleCard(driver: driver),
                  const SizedBox(height: AppSpacing.lg),
                  _ReviewsSection(driver: driver),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverProfileAppBar extends StatelessWidget {
  final Driver driver;

  const _DriverProfileAppBar({required this.driver});

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 260,
      pinned: true,
      leading: IconButton(
        onPressed: () => context.pop(),
        icon: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          color: AppColors.primary,
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: AppSpacing.xl),
                DriverAvatar(
                  name: driver.name,
                  photoUrl: driver.photoUrl,
                  isOnline: driver.isOnline,
                  size: 80,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  driver.name,
                  style: AppTextStyles.title1.copyWith(color: Colors.white),
                ),
                const SizedBox(height: AppSpacing.xs),
                StarRating(
                  rating: driver.rating,
                  size: 16,
                  reviewCount: driver.reviews.length,
                ),
                const SizedBox(height: AppSpacing.sm),
                StatusChip(
                  variant: driver.isOnline
                      ? StatusChipVariant.online
                      : StatusChipVariant.offline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final Driver driver;

  const _StatsRow({required this.driver});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: AppColors.cardDecoration,
      child: Row(
        children: [
          _Stat(
            value: driver.rating.toStringAsFixed(1),
            label: 'Note',
            icon: Icons.star_rounded,
            iconColor: AppColors.accent,
          ),
          _VertDivider(),
          _Stat(
            value: '${driver.totalTrips}',
            label: 'Trajets',
            icon: Icons.route_outlined,
            iconColor: AppColors.primary,
          ),
          _VertDivider(),
          _Stat(
            value: '${driver.reviews.length}',
            label: 'Avis',
            icon: Icons.chat_bubble_outline,
            iconColor: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

class _VertDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 48, color: AppColors.border);
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color iconColor;

  const _Stat({
    required this.value,
    required this.label,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTextStyles.title2,
          ),
          Text(label, style: AppTextStyles.caption),
        ],
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  final Driver driver;

  const _VehicleCard({required this.driver});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Véhicule', style: AppTextStyles.title2),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: AppSpacing.cardPadding,
          decoration: AppColors.cardDecoration,
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.directions_car_outlined,
                  size: 28,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driver.vehicle.model,
                      style: AppTextStyles.bodyLargeSemibold,
                    ),
                    Text(
                      '${driver.vehicle.color} · ${driver.vehicle.totalSeats} places',
                      style: AppTextStyles.caption,
                    ),
                    Text(
                      driver.vehicle.plateNumber,
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(AppSpacing.borderRadiusSm),
                ),
                child: Text(
                  driver.vehicle.typeLabel,
                  style: AppTextStyles.label.copyWith(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReviewsSection extends StatelessWidget {
  final Driver driver;

  const _ReviewsSection({required this.driver});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Avis voyageurs', style: AppTextStyles.title2),
            const Spacer(),
            StarRating(
              rating: driver.rating,
              size: 14,
              reviewCount: driver.reviews.length,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (driver.reviews.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: AppColors.cardDecoration,
            child: Center(
              child: Text(
                'Aucun avis pour le moment',
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          )
        else
          ...driver.reviews.map((review) {
            final dateStr = DateFormat('d MMM yyyy', 'fr_FR').format(review.date);
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Container(
                padding: AppSpacing.cardPadding,
                decoration: AppColors.cardDecoration,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          review.authorName,
                          style: AppTextStyles.bodySemibold,
                        ),
                        const Spacer(),
                        StarRating(
                          rating: review.rating,
                          size: 13,
                          showLabel: false,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(dateStr, style: AppTextStyles.caption),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(review.comment, style: AppTextStyles.body),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}
