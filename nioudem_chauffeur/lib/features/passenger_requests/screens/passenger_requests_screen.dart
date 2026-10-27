import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/driver_avatar.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/trip_card.dart' show formatDayLabel;
import '../../../core/widgets/fojem_button.dart';
import '../../../core/widgets/verification_dialog.dart';
import '../../../models/ride_request.dart';
import '../../../models/trip.dart';
import '../../../providers/app_provider.dart';
import '../../../services/chat_repository.dart';
import '../../../services/ride_request_repository.dart';
import '../../../services/trip_repository.dart';

class _MatchedRequest {
  final RideRequest request;
  final Trip trip;

  const _MatchedRequest({required this.request, required this.trip});
}

/// "Demandes de passagers sur ma route" (route `/driver/passenger-requests`) :
/// liste les demandes `ride_requests` ouvertes compatibles avec les trajets
/// à venir du chauffeur connecté, via `GET /trips/{id}/nearby-ride-requests`
/// (matching géospatial + score de compatibilité PostGIS/MatchingService).
class PassengerRequestsScreen extends StatefulWidget {
  const PassengerRequestsScreen({super.key});

  @override
  State<PassengerRequestsScreen> createState() => _PassengerRequestsScreenState();
}

class _PassengerRequestsScreenState extends State<PassengerRequestsScreen> {
  bool _isLoading = true;
  bool _hasError = false;
  List<_MatchedRequest> _matches = const [];
  final _openingChatIds = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final driverId = context.read<AppProvider>().user?.id;
    if (driverId == null) {
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
      return;
    }
    setState(() => _isLoading = true);
    try {
      final trips = await TripRepository().fetchForDriver(driverId);
      final now = DateTime.now();
      final upcomingTrips = trips
          .where((t) => t.status == TripStatus.upcoming && t.departureTime.isAfter(now))
          .toList();

      final rideRequestRepo = RideRequestRepository();
      final seenRequestIds = <String>{};
      final matches = <_MatchedRequest>[];
      for (final trip in upcomingTrips) {
        final nearby = await rideRequestRepo.fetchNearTrip(trip.id);
        for (final request in nearby) {
          if (!seenRequestIds.add(request.id)) continue;
          matches.add(_MatchedRequest(request: request, trip: trip));
        }
      }
      matches.sort((a, b) {
        final scoreA = a.request.compatibilityScore ?? 0;
        final scoreB = b.request.compatibilityScore ?? 0;
        if (scoreA != scoreB) return scoreB.compareTo(scoreA);
        return a.trip.departureTime.compareTo(b.trip.departureTime);
      });

      if (!mounted) return;
      setState(() {
        _matches = matches;
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

  Future<void> _respond(_MatchedRequest match) async {
    final user = context.read<AppProvider>().user;
    if (user?.isApprovedDriver != true) {
      showVerificationRequiredDialog(
        context,
        action: 'contacter un passager',
      );
      return;
    }
    final driverId = user?.id;
    if (driverId == null) return;
    setState(() => _openingChatIds.add(match.request.id));
    try {
      final conversation = await ChatRepository().findOrCreate(
        userIdA: driverId,
        userIdB: match.request.passengerId,
        relatedRequestId: match.request.id,
      );
      if (!mounted) return;
      setState(() => _openingChatIds.remove(match.request.id));
      context.push(
        '/chat/${conversation.id}?name=${Uri.encodeComponent(match.request.passengerName)}&otherId=${match.request.passengerId}',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _openingChatIds.remove(match.request.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’ouvrir la conversation. Réessayez.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Demandes de passagers'),
        leading: IconButton(
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
        ),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: _isLoading
              ? const _RequestsSkeleton()
              : _hasError
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: AppColors.softCardDecoration,
                          child: Text(
                            'Impossible de charger les demandes. Tirez vers le bas pour réessayer.',
                            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    )
                  : _matches.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
                          children: const [_EmptyState()],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          itemCount: _matches.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 14),
                          itemBuilder: (context, index) {
                            final match = _matches[index];
                            return _RequestCard(
                              match: match,
                              isOpeningChat: _openingChatIds.contains(match.request.id),
                              onRespond: () => _respond(match),
                            );
                          },
                        ),
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final _MatchedRequest match;
  final bool isOpeningChat;
  final VoidCallback onRespond;

  const _RequestCard({
    required this.match,
    required this.isOpeningChat,
    required this.onRespond,
  });

  @override
  Widget build(BuildContext context) {
    final request = match.request;
    final approxDistanceKm = match.trip.origin.distanceKm(request.origin);
    final score = request.compatibilityScore;
    final detourKm = request.detourDistanceM != null
        ? (request.detourDistanceM! / 1000.0)
        : approxDistanceKm;

    return Container(
      decoration: AppColors.softCardDecoration,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DriverAvatar(name: request.passengerName, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(request.passengerName, style: AppTextStyles.bodyLargeSemibold),
                    const SizedBox(height: 2),
                    Text(
                      '${formatDayLabel(request.desiredDateTime)} • '
                      '${request.desiredDateTime.hour.toString().padLeft(2, '0')}:'
                      '${request.desiredDateTime.minute.toString().padLeft(2, '0')} • '
                      '${request.seatsNeeded} place${request.seatsNeeded > 1 ? 's' : ''}',
                      style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(AppSpacing.borderRadiusSm),
                    ),
                    child: Text(
                      score != null
                          ? '${score.round()}% compatible'
                          : '~${approxDistanceKm.toStringAsFixed(1)} km',
                      style: AppTextStyles.label.copyWith(color: AppColors.primary, fontSize: 11),
                    ),
                  ),
                  if (score != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      'Détour ~${detourKm.toStringAsFixed(1)} km',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textMuted,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  request.origin.address.isNotEmpty ? request.origin.address : 'Départ',
                  style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.primary),
              ),
              Expanded(
                child: Text(
                  request.destination.address.isNotEmpty ? request.destination.address : 'Arrivée',
                  textAlign: TextAlign.right,
                  style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Sur votre trajet ${match.trip.departure} → ${match.trip.arrival}',
            style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),
          FojemButton.primary(
            label: 'Répondre',
            prefixIcon: Icons.chat_bubble_outline_rounded,
            size: FojemButtonSize.medium,
            isLoading: isOpeningChat,
            onPressed: isOpeningChat ? null : onRespond,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
            child: const Icon(Icons.person_search_rounded, size: 26, color: AppColors.primary),
          ),
          const SizedBox(height: 14),
          Text('Aucune demande sur vos trajets', style: AppTextStyles.bodyLargeSemibold),
          const SizedBox(height: 6),
          Text(
            'Les demandes de passagers proches de vos trajets à venir apparaîtront ici.',
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _RequestsSkeleton extends StatelessWidget {
  const _RequestsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: SkeletonList(itemCount: 3, itemSkeleton: SkeletonBox(height: 150)),
    );
  }
}
