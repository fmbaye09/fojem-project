import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/driver_avatar.dart';
import '../../../core/widgets/trip_card.dart' show formatDayLabel, formatFcfa;
import '../../../core/widgets/fojem_button.dart';
import '../../../models/booking.dart';
import '../../../models/trip.dart';
import '../../../models/vehicle.dart';
import '../../../providers/app_provider.dart';
import '../../../services/booking_repository.dart';
import '../../../services/chat_repository.dart';
import '../../../services/trip_repository.dart';
import '../../../services/vehicle_repository.dart';

/// Détail d'un trajet côté chauffeur : carte récapitulative enrichie,
/// itinéraire visuel, véhicule, émission GPS temps réel quand le trajet est
/// `inProgress`, passagers confirmés avec statut boarding, scanner QR,
/// demandes en attente, et actions de gestion.
class TripManageScreen extends StatefulWidget {
  final String tripId;

  const TripManageScreen({super.key, required this.tripId});

  @override
  State<TripManageScreen> createState() => _TripManageScreenState();
}

class _TripManageScreenState extends State<TripManageScreen> {
  Trip? _trip;
  Vehicle? _vehicle;
  List<Booking> _confirmed = [];
  int _pendingCount = 0;
  bool _isLoading = true;
  bool _isCancelling = false;
  bool _isStarting = false;
  bool _isCompleting = false;
  String? _bookingsUnavailableMessage;
  Timer? _pollTimer;
  DateTime? _lastGpsSentAt;
  bool _gpsPermissionDenied = false;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _load(silent: true);
      if (_trip?.status == TripStatus.inProgress) {
        _broadcastCurrentGps();
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _broadcastCurrentGps() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _gpsPermissionDenied = true);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 6),
        ),
      );
      await TripRepository().updateLocation(
        widget.tripId,
        lat: pos.latitude,
        lng: pos.longitude,
        heading: pos.heading.isFinite ? pos.heading : null,
      );
      if (!mounted) return;
      setState(() {
        _gpsPermissionDenied = false;
        _lastGpsSentAt = DateTime.now();
      });
    } catch (_) {
      // Silencieux en arrière-plan pour ne pas interrompre la conduite
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }
    try {
      final trip = await TripRepository().fetch(widget.tripId);
      final vehicle = trip == null ? null : await VehicleRepository().fetch(trip.vehicleId);
      try {
        final bookings = await BookingRepository().fetchForTrip(widget.tripId);
        if (!mounted) return;
        setState(() {
          _trip = trip;
          _vehicle = vehicle;
          _confirmed = bookings.where((b) => b.status == BookingStatus.confirmed).toList();
          _pendingCount = bookings.where((b) => b.status == BookingStatus.pending).length;
          _bookingsUnavailableMessage = null;
          _isLoading = false;
        });
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() {
          _trip = trip;
          _vehicle = vehicle;
          _confirmed = [];
          _pendingCount = 0;
          _bookingsUnavailableMessage = e.message;
          _isLoading = false;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _bookingsUnavailableMessage = e.message;
        _isLoading = false;
      });
    }
  }

  Future<void> _cancelTrip() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd)),
        title: Text('Annuler ce trajet ?', style: AppTextStyles.title2),
        content: Text(
          'Les passagers déjà confirmés seront notifiés de l\'annulation.',
          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Retour')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Annuler le trajet',
                style: AppTextStyles.bodySemibold.copyWith(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isCancelling = true);
    await TripRepository().updateStatus(widget.tripId, TripStatus.cancelled);
    if (!mounted) return;
    setState(() {
      _isCancelling = false;
      _trip = _trip?.copyWith(status: TripStatus.cancelled);
    });
  }

  Future<void> _startTrip() async {
    setState(() => _isStarting = true);
    try {
      await TripRepository().updateStatus(widget.tripId, TripStatus.inProgress);
      if (!mounted) return;
      setState(() {
        _isStarting = false;
        _trip = _trip?.copyWith(status: TripStatus.inProgress);
      });
      _broadcastCurrentGps();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isStarting = false);
    }
  }

  Future<void> _completeTrip() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd)),
        title: Text('Terminer ce trajet ?', style: AppTextStyles.title2),
        content: Text(
          'Tous les passagers confirmés seront marqués comme arrivés et vos gains crédités sur votre portefeuille.',
          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Retour')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Terminer le trajet',
                style: AppTextStyles.bodySemibold.copyWith(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isCompleting = true);
    try {
      await TripRepository().updateStatus(widget.tripId, TripStatus.completed);
      if (!mounted) return;
      setState(() {
        _isCompleting = false;
        _trip = _trip?.copyWith(status: TripStatus.completed);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trajet terminé avec succès ! Vos gains sont crédités.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCompleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }

  void _openScanner() async {
    final result = await context.push<bool>('/trip/${widget.tripId}/scan');
    if (result == true) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _trip == null
              ? const Center(child: Text('Trajet introuvable'))
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _load,
                  child: CustomScrollView(
                    slivers: [
                      // ── App bar with gradient ──
                      SliverAppBar(
                        expandedHeight: 180,
                        pinned: true,
                        leading: IconButton(
                          onPressed: () => context.canPop() ? context.pop() : context.go('/trips'),
                          icon: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                          ),
                        ),
                        flexibleSpace: FlexibleSpaceBar(
                          background: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF1A5C2E),
                                  AppColors.primary,
                                  Color(0xFF2D8A4E),
                                ],
                              ),
                            ),
                            child: SafeArea(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _trip!.departure,
                                                style: AppTextStyles.display.copyWith(
                                                  color: Colors.white,
                                                  fontSize: 24,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.white70),
                                              const SizedBox(width: 6),
                                              Text(
                                                _trip!.arrival,
                                                style: AppTextStyles.bodySemibold.copyWith(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    _TripStatusBadge(status: _trip!.status),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      SliverPadding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            // ── Live GPS Broadcast Banner when inProgress ──
                            if (_trip!.status == TripStatus.inProgress) ...[
                              _LiveGpsBanner(
                                lastSentAt: _lastGpsSentAt ?? _trip!.locationUpdatedAt,
                                permissionDenied: _gpsPermissionDenied,
                                onForceSend: _broadcastCurrentGps,
                              ),
                              const SizedBox(height: 16),
                            ],

                            // ── Quick stats row ──
                            _QuickStatsRow(trip: _trip!, confirmedCount: _confirmed.length),
                            const SizedBox(height: 20),

                            // ── Trip info card ──
                            _TripInfoCard(trip: _trip!, vehicle: _vehicle),
                            const SizedBox(height: 16),

                            // ── Vehicle card ──
                            if (_vehicle != null) ...[
                              _VehicleCard(vehicle: _vehicle!),
                              const SizedBox(height: 16),
                            ],

                            // ── Actions row: Scanner + Demandes ──
                            if (_trip!.status == TripStatus.upcoming || _trip!.status == TripStatus.inProgress) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: _ActionCard(
                                      icon: Icons.qr_code_scanner_rounded,
                                      label: 'Scanner QR',
                                      subtitle: 'Valider un passager',
                                      color: AppColors.primary,
                                      onTap: _openScanner,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _ActionCard(
                                      icon: Icons.inbox_rounded,
                                      label: 'Demandes',
                                      subtitle: _pendingCount > 0
                                          ? '$_pendingCount en attente'
                                          : 'Aucune',
                                      color: _pendingCount > 0
                                          ? const Color(0xFFE67E22)
                                          : AppColors.textSecondary,
                                      badge: _pendingCount > 0 ? _pendingCount : null,
                                      onTap: () => context.push('/trip/${widget.tripId}/requests'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                            ],

                            // ── Passengers section ──
                            Row(
                              children: [
                                const Icon(Icons.people_alt_rounded, size: 22, color: AppColors.primary),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Passagers confirmés',
                                    style: AppTextStyles.title2.copyWith(fontSize: 18),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${_confirmed.length}',
                                    style: AppTextStyles.bodySemibold.copyWith(
                                      color: AppColors.primary,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),

                            if (_bookingsUnavailableMessage != null)
                              _EmptyPassengerCard(
                                icon: Icons.error_outline_rounded,
                                text: _bookingsUnavailableMessage!,
                              )
                            else if (_confirmed.isEmpty)
                              const _EmptyPassengerCard(
                                icon: Icons.person_search_rounded,
                                text: 'Aucun passager confirmé pour l\'instant',
                              )
                            else
                              ..._confirmed.map((b) => Padding(
                                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                                    child: _PassengerTile(booking: b, tripId: widget.tripId),
                                  )),

                            const SizedBox(height: 20),

                            // ── Bottom actions ──
                            if (_trip!.status == TripStatus.upcoming && _confirmed.isNotEmpty) ...[
                              FojemButton.primary(
                                label: 'Démarrer le trajet',
                                prefixIcon: Icons.play_arrow_rounded,
                                isLoading: _isStarting,
                                onPressed: _isStarting ? null : _startTrip,
                              ),
                              const SizedBox(height: 12),
                            ],

                            if (_trip!.status == TripStatus.inProgress) ...[
                              FojemButton.primary(
                                label: 'Terminer le trajet',
                                prefixIcon: Icons.check_circle_rounded,
                                isLoading: _isCompleting,
                                onPressed: _isCompleting ? null : _completeTrip,
                              ),
                              const SizedBox(height: 12),
                            ],

                            if (_trip!.status == TripStatus.upcoming) ...[
                              FojemButton.dangerOutline(
                                label: 'Annuler le trajet',
                                prefixIcon: Icons.cancel_outlined,
                                isLoading: _isCancelling,
                                onPressed: _isCancelling ? null : _cancelTrip,
                              ),
                            ],

                            const SizedBox(height: AppSpacing.xl),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _LiveGpsBanner extends StatelessWidget {
  final DateTime? lastSentAt;
  final bool permissionDenied;
  final VoidCallback onForceSend;

  const _LiveGpsBanner({
    required this.lastSentAt,
    required this.permissionDenied,
    required this.onForceSend,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = lastSentAt != null
        ? '${lastSentAt!.toLocal().hour.toString().padLeft(2, '0')}:${lastSentAt!.toLocal().minute.toString().padLeft(2, '0')}:${lastSentAt!.toLocal().second.toString().padLeft(2, '0')}'
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: permissionDenied ? AppColors.dangerSurface : AppColors.primarySurface,
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
        border: Border.all(
          color: permissionDenied
              ? AppColors.danger.withOpacity(0.3)
              : AppColors.primary.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            permissionDenied ? Icons.gps_off_rounded : Icons.gps_fixed_rounded,
            size: 20,
            color: permissionDenied ? AppColors.danger : AppColors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  permissionDenied
                      ? 'Partage GPS désactivé (permission refusée)'
                      : 'Position GPS partagée en direct',
                  style: AppTextStyles.bodySemibold.copyWith(
                    fontSize: 13.5,
                    color: permissionDenied ? AppColors.danger : AppColors.primary,
                  ),
                ),
                Text(
                  timeStr != null
                      ? 'Dernier envoi aux passagers : $timeStr'
                      : 'Synchronisation GPS automatique toutes les 8s…',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onForceSend,
            tooltip: 'Actualiser ma position GPS',
            icon: Icon(
              Icons.refresh_rounded,
              size: 20,
              color: permissionDenied ? AppColors.danger : AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TripStatusBadge extends StatelessWidget {
  final TripStatus status;
  const _TripStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      TripStatus.upcoming => ('Programmé', Colors.white, Icons.schedule_rounded),
      TripStatus.inProgress => ('En cours', const Color(0xFFFFD700), Icons.navigation_rounded),
      TripStatus.completed => ('Terminé', const Color(0xFF90EE90), Icons.check_circle_rounded),
      TripStatus.cancelled => ('Annulé', const Color(0xFFFF6B6B), Icons.cancel_rounded),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.bodySemibold.copyWith(color: color, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _QuickStatsRow extends StatelessWidget {
  final Trip trip;
  final int confirmedCount;
  const _QuickStatsRow({required this.trip, required this.confirmedCount});

  @override
  Widget build(BuildContext context) {
    final bookedSeats = trip.seatsTotal - trip.availableSeats;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusCard),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Expanded(child: _StatItem(
            icon: Icons.airline_seat_recline_normal_rounded,
            value: '$bookedSeats/${trip.seatsTotal}',
            label: 'Places',
            color: AppColors.primary,
          )),
          Container(width: 1, height: 40, color: AppColors.border),
          Expanded(child: _StatItem(
            icon: Icons.people_alt_rounded,
            value: '$confirmedCount',
            label: 'Confirmés',
            color: const Color(0xFF3498DB),
          )),
          Container(width: 1, height: 40, color: AppColors.border),
          Expanded(child: _StatItem(
            icon: Icons.payments_outlined,
            value: formatFcfa(trip.pricePerSeat),
            label: 'Par place',
            color: const Color(0xFFE67E22),
          )),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  const _StatItem({required this.icon, required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(height: 6),
        Text(value, style: AppTextStyles.bodySemibold.copyWith(fontSize: 15)),
        Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
      ],
    );
  }
}

class _TripInfoCard extends StatelessWidget {
  final Trip trip;
  final Vehicle? vehicle;
  const _TripInfoCard({required this.trip, required this.vehicle});

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
              const Icon(Icons.route_rounded, size: 20, color: AppColors.primary),
              const SizedBox(width: 10),
              Text('Itinéraire', style: AppTextStyles.title2.copyWith(fontSize: 16)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 6),
                      ],
                    ),
                  ),
                  Container(
                    width: 2,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [AppColors.primary, AppColors.primary.withOpacity(0.3)],
                      ),
                    ),
                  ),
                  const Icon(Icons.location_on_rounded, size: 18, color: AppColors.danger),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Départ', style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
                    Text(trip.departure, style: AppTextStyles.bodyLargeSemibold),
                    const SizedBox(height: 28),
                    Text('Arrivée', style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
                    Text(trip.arrival, style: AppTextStyles.bodyLargeSemibold),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.calendar_today_rounded, size: 18, color: Color(0xFFE67E22)),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatDayLabel(trip.departureTime),
                    style: AppTextStyles.bodySemibold.copyWith(fontSize: 14),
                  ),
                  Text(
                    '${trip.departureTime.hour.toString().padLeft(2, '0')}:'
                    '${trip.departureTime.minute.toString().padLeft(2, '0')}',
                    style: AppTextStyles.body.copyWith(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
              const Spacer(),
              if (trip.durationLabel.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_outlined, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 5),
                      Text(trip.durationLabel,
                          style: AppTextStyles.bodySemibold.copyWith(fontSize: 13, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  final Vehicle vehicle;
  const _VehicleCard({required this.vehicle});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppColors.softCardDecoration,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4F0),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.directions_car_rounded, size: 28, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${vehicle.brand} ${vehicle.model}',
                    style: AppTextStyles.bodyLargeSemibold),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(vehicle.plateNumber,
                          style: AppTextStyles.bodySemibold.copyWith(
                            fontSize: 12,
                            letterSpacing: 1.2,
                            color: AppColors.textSecondary,
                          )),
                    ),
                    const SizedBox(width: 8),
                    if (vehicle.color.isNotEmpty) ...[
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: AppColors.textMuted,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.border),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(vehicle.color,
                          style: AppTextStyles.body.copyWith(fontSize: 13, color: AppColors.textSecondary)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(vehicle.typeLabel,
                style: AppTextStyles.bodySemibold.copyWith(color: AppColors.primary, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final int? badge;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.borderRadiusCard),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.borderRadiusCard),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(color: Color(0x08000000), blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 22, color: color),
                ),
                const Spacer(),
                if (badge != null)
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$badge',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(label, style: AppTextStyles.bodySemibold.copyWith(fontSize: 15)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _EmptyPassengerCard extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyPassengerCard({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: AppColors.cardDecoration,
      child: Column(
        children: [
          Icon(icon, size: 36, color: AppColors.borderStrong),
          const SizedBox(height: AppSpacing.sm),
          Text(text,
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _PassengerTile extends StatefulWidget {
  final Booking booking;
  final String tripId;

  const _PassengerTile({required this.booking, required this.tripId});

  @override
  State<_PassengerTile> createState() => _PassengerTileState();
}

class _PassengerTileState extends State<_PassengerTile> {
  bool _isOpeningChat = false;

  Future<void> _openChat() async {
    final driverId = context.read<AppProvider>().user?.id;
    if (driverId == null) return;
    setState(() => _isOpeningChat = true);
    try {
      final conversation = await ChatRepository().findOrCreate(
        userIdA: driverId,
        userIdB: widget.booking.passengerId,
        relatedTripId: widget.tripId,
      );
      if (!mounted) return;
      setState(() => _isOpeningChat = false);
      context.push(
        '/chat/${conversation.id}?name=${Uri.encodeComponent(widget.booking.passengerName)}&otherId=${widget.booking.passengerId}',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isOpeningChat = false);
    }
  }

  void _callPassenger() {
    final phone = widget.booking.passengerPhone;
    if (phone.isNotEmpty) {
      launchUrl(Uri.parse('tel:$phone'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    final isBoarded = booking.isBoarded;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusCard),
        border: Border.all(
          color: isBoarded ? AppColors.primary.withOpacity(0.3) : AppColors.border,
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x06000000), blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              DriverAvatar(name: booking.passengerName, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(booking.passengerName,
                        style: AppTextStyles.bodyLargeSemibold.copyWith(fontSize: 15)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: isBoarded
                                ? AppColors.primary.withOpacity(0.1)
                                : const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isBoarded ? Icons.check_circle_rounded : Icons.hourglass_top_rounded,
                                size: 12,
                                color: isBoarded ? AppColors.primary : const Color(0xFFE67E22),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isBoarded ? 'À bord' : 'En attente',
                                style: AppTextStyles.caption.copyWith(
                                  color: isBoarded ? AppColors.primary : const Color(0xFFE67E22),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          booking.confirmationCode,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textMuted,
                            letterSpacing: 1,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SmallActionButton(
                  icon: Icons.phone_outlined,
                  label: 'Appeler',
                  onTap: _callPassenger,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SmallActionButton(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Message',
                  isLoading: _isOpeningChat,
                  onTap: _isOpeningChat ? null : _openChat,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SmallActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isLoading;

  const _SmallActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primary),
              )
            else
              Icon(icon, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(label,
                style: AppTextStyles.bodySemibold.copyWith(fontSize: 12, color: AppColors.primary)),
          ],
        ),
      ),
    );
  }
}
