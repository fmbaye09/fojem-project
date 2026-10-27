import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/fojem_button.dart';
import '../../../models/ride_request.dart';
import '../../../providers/app_provider.dart';
import '../../../services/ride_request_repository.dart';

class MyRideRequestsScreen extends StatefulWidget {
  const MyRideRequestsScreen({super.key});

  @override
  State<MyRideRequestsScreen> createState() => _MyRideRequestsScreenState();
}

class _MyRideRequestsScreenState extends State<MyRideRequestsScreen> {
  final _repository = RideRequestRepository();
  List<RideRequest> _requests = [];
  final Map<String, List<MatchedTripScore>> _matchesByRequest = {};
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    final userId = context.read<AppProvider>().user?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final list = await _repository.fetchForPassenger(userId);
      final matchesMap = <String, List<MatchedTripScore>>{};
      for (final req in list) {
        if (req.status == RideRequestStatus.open) {
          try {
            matchesMap[req.id] = await _repository.fetchMatches(req.id);
          } catch (_) {
            matchesMap[req.id] = const [];
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _requests = list;
        _matchesByRequest
          ..clear()
          ..addAll(matchesMap);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Impossible de charger vos demandes.';
      });
    }
  }

  Future<void> _cancelRequest(String requestId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler la demande'),
        content: const Text('Voulez-vous vraiment annuler cette demande de trajet ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Non'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Oui, annuler'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _repository.cancel(requestId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Demande annulée avec succès.'),
          backgroundColor: AppColors.success,
        ),
      );
      _loadRequests();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erreur lors de l\'annulation.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Mes demandes & Matchs'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRequests,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_errorMessage!, style: AppTextStyles.body),
                        const SizedBox(height: AppSpacing.md),
                        FojemButton.secondary(
                          label: 'Réessayer',
                          onPressed: _loadRequests,
                        ),
                      ],
                    ),
                  )
                : _requests.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: const BoxDecoration(
                                  color: AppColors.surface,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.alt_route_outlined,
                                  size: 40,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              Text('Aucune demande publiée', style: AppTextStyles.title2),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                'Lorsque vous publiez une demande pour un trajet sans offre existante, elle apparaîtra ici avec les chauffeurs compatibles.',
                                textAlign: TextAlign.center,
                                style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                              ),
                              const SizedBox(height: AppSpacing.xl),
                              FojemButton.primary(
                                label: 'Créer une demande',
                                prefixIcon: Icons.add,
                                onPressed: () => context.push('/ride-request/create'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadRequests,
                        color: AppColors.primary,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          itemCount: _requests.length,
                          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
                          itemBuilder: (ctx, index) {
                            final req = _requests[index];
                            final matches = _matchesByRequest[req.id] ?? const [];
                            return _RideRequestCard(
                              request: req,
                              matches: matches,
                              onCancel: () => _cancelRequest(req.id),
                            );
                          },
                        ),
                      ),
      ),
    );
  }
}

class _RideRequestCard extends StatelessWidget {
  final RideRequest request;
  final List<MatchedTripScore> matches;
  final VoidCallback onCancel;

  const _RideRequestCard({
    required this.request,
    required this.matches,
    required this.onCancel,
  });

  String _formatStatus(RideRequestStatus status) {
    switch (status) {
      case RideRequestStatus.open:
        return matches.isNotEmpty
            ? '${matches.length} trajet${matches.length > 1 ? 's' : ''} compatible${matches.length > 1 ? 's' : ''}'
            : 'En recherche de chauffeur';
      case RideRequestStatus.matched:
        return 'Chauffeur trouvé';
      case RideRequestStatus.closed:
        return 'Terminée / Annulée';
    }
  }

  Color _statusColor(RideRequestStatus status) {
    switch (status) {
      case RideRequestStatus.open:
        return matches.isNotEmpty ? AppColors.success : AppColors.primary;
      case RideRequestStatus.matched:
        return AppColors.success;
      case RideRequestStatus.closed:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(request.status);
    final isCancelable = request.status == RideRequestStatus.open;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _formatStatus(request.status),
                  style: AppTextStyles.caption.copyWith(color: statusColor, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                DateFormat('dd MMM yyyy, HH:mm', 'fr_FR').format(request.desiredDateTime),
                style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              const Icon(Icons.my_location, size: 16, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  request.origin.address.isNotEmpty ? request.origin.address : 'Point de départ',
                  style: AppTextStyles.bodySemibold,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(left: 7),
            child: SizedBox(
              height: 14,
              child: VerticalDivider(color: AppColors.border, thickness: 1.5),
            ),
          ),
          Row(
            children: [
              const Icon(Icons.location_on, size: 16, color: AppColors.danger),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  request.destination.address.isNotEmpty ? request.destination.address : 'Destination',
                  style: AppTextStyles.bodySemibold,
                ),
              ),
            ],
          ),
          if (matches.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(color: AppColors.border),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Meilleures correspondances (FOJËM Match)',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final m in matches.take(3)) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primarySurface,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${m.compatibilityScore.round()}%',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${m.trip.departure} → ${m.trip.arrival}',
                            style: AppTextStyles.bodySemibold.copyWith(fontSize: 13),
                          ),
                          Text(
                            '${m.trip.driver?.name ?? 'Chauffeur'} · ${m.trip.pricePerSeat.toInt()} FCFA · ${DateFormat('dd/MM HH:mm').format(m.trip.departureTime)}',
                            style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.push('/trip/${m.trip.id}'),
                      child: const Text('Voir'),
                    ),
                  ],
                ),
              ),
            ],
          ],
          if (isCancelable) ...[
            const SizedBox(height: AppSpacing.xs),
            const Divider(color: AppColors.border),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.close, size: 16, color: AppColors.danger),
                label: Text(
                  'Annuler la demande',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
