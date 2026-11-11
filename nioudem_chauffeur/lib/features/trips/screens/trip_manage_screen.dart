import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/events/data_refresh.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/countdown.dart';
import '../../../core/widgets/en_route_switch.dart';
import '../../../core/widgets/trip_card.dart' show formatDayLabel, formatFcfa;
import '../../../core/widgets/fojem_button.dart';
import '../../../core/widgets/glow.dart';
import '../../../core/widgets/sos.dart';
import '../../../models/booking.dart';
import '../../../models/trip.dart';
import '../../../models/trip_stop.dart';
import '../../../models/vehicle.dart';
import '../../../services/booking_repository.dart';
import '../../../services/sos_repository.dart';
import '../../../services/trip_location_tracker.dart';
import '../../../services/trip_repository.dart';
import '../../../services/vehicle_repository.dart';
import '../departure_status.dart';
import '../widgets/complete_trip_sheet.dart';
import '../widgets/passenger_tile.dart';

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

class _TripManageScreenState extends State<TripManageScreen> with AutoRefresh<TripManageScreen> {
  @override
  Future<void> onAutoRefresh() => _load(silent: true);

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

  final _tracker = TripLocationTracker.instance;

  @override
  void initState() {
    super.initState();
    _tracker.lastSentAt.addListener(_onTrackerUpdate);
    _tracker.permissionDenied.addListener(_onTrackerUpdate);
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (shouldPoll(context)) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tracker.lastSentAt.removeListener(_onTrackerUpdate);
    _tracker.permissionDenied.removeListener(_onTrackerUpdate);
    // Le suivi GPS continue volontairement après la fermeture de l'écran :
    // il s'arrête à la fin ou à l'annulation du trajet.
    super.dispose();
  }

  void _onTrackerUpdate() {
    if (!mounted) return;
    setState(() {
      _lastGpsSentAt = _tracker.lastSentAt.value ?? _lastGpsSentAt;
      _gpsPermissionDenied = _tracker.permissionDenied.value;
    });
  }

  /// Dernière position envoyée avant le départ (au plus une par minute).
  DateTime? _lastPreDepartureFixAt;

  /// Aligne le suivi GPS sur le statut du trajet. Avant le départ, à
  /// l'approche de l'heure, une position par minute : l'arrivée au point de
  /// rendez-vous est enregistrée, preuve d'une éventuelle absence.
  void _syncTracking(Trip? trip) {
    if (trip == null) return;
    if (trip.status == TripStatus.inProgress) {
      _tracker.start(trip.id);
    } else if (_tracker.activeTripId == trip.id) {
      _tracker.stop();
    }

    final now = DateTime.now();
    final nearDeparture = now.isAfter(trip.departureTime.subtract(const Duration(hours: 1))) &&
        now.isBefore(trip.departureTime.add(const Duration(hours: 2)));
    final lastFix = _lastPreDepartureFixAt;
    if (trip.status == TripStatus.upcoming &&
        nearDeparture &&
        (lastFix == null || now.difference(lastFix) >= const Duration(minutes: 1))) {
      _lastPreDepartureFixAt = now;
      _broadcastCurrentGps();
    }
  }

  /// « Passager absent » : une position fraîche d'abord (preuve d'être au
  /// point de rendez-vous), puis la déclaration ; le backend dit s'il faut
  /// encore attendre.
  Future<void> _markAbsent(Booking booking) async {
    final name = booking.passengerName.isEmpty ? 'ce passager' : booking.passengerName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd)),
        title: Text('Passager absent ?', style: AppTextStyles.title2),
        content: Text(
          'Déclarez $name absent seulement après l’avoir attendu au point de rendez-vous, '
          'au moins 5 min après l’heure prévue. Sa place sera libérée et il sera prévenu.',
          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Retour')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Déclarer absent', style: AppTextStyles.bodySemibold.copyWith(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _broadcastCurrentGps();
    try {
      await BookingRepository().markNoShow(booking.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Absence enregistrée : vous pouvez reprendre la route.')),
      );
      _load(silent: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      // L'arrivée vient peut-être d'être enregistrée : le décompte apparaît.
      _load(silent: true);
    }
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
      _syncTracking(trip);
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
          'Les réservations en cours seront annulées et les passagers prévenus.',
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
    try {
      await TripRepository().updateStatus(widget.tripId, TripStatus.cancelled);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isCancelling = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    _tracker.stop();
    if (!mounted) return;
    setState(() {
      _isCancelling = false;
      _trip = _trip?.copyWith(status: TripStatus.cancelled);
    });
    _load(silent: true);
  }

  /// Démarrer sans des passagers attendus au départ : le chauffeur confirme.
  /// Avant la fin de l'attente, ils risquent de le manquer ; après, il peut
  /// les déclarer absents.
  Future<bool> _confirmLeavingWithout(Trip trip) async {
    if (trip.stops.isEmpty) return true;
    final start = trip.stops.first;
    final missing = _confirmed.where((b) => !b.isBoarded && boardsAt(b, start)).toList();
    if (missing.isEmpty) return true;

    final deadline = start.waitUntil ??
        (start.scheduledAt ?? trip.departureTime).add(const Duration(minutes: kDriverWaitMinutes));
    final early = DateTime.now().isBefore(deadline);
    final plural = missing.length > 1;
    final names = missing.map((b) => b.passengerName.isEmpty ? 'un passager' : b.passengerName).join(', ');
    final at = DateFormat('HH:mm').format(deadline);
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd)),
        title: Text(
          early ? 'Pas encore à bord' : 'Partir sans ${plural ? 'eux' : 'ce passager'} ?',
          style: AppTextStyles.title2,
        ),
        content: Text(
          early
              ? '$names ${plural ? 'ont' : 'a'} jusqu’à $at pour vous rejoindre à ${start.name}. '
                  'Si vous partez maintenant, ${plural ? 'ils seront prévenus' : 'il sera prévenu'} et '
                  '${plural ? 'leur' : 'son'} trajet sera « manqué », sans pénalité pour ${plural ? 'eux' : 'lui'}.'
              : 'Le délai d’attente est écoulé à ${start.name} : vous pouvez déclarer $names absent${plural ? 's' : ''}, '
                  'maintenant ou une fois parti.',
          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(early ? 'Attendre' : 'Retour')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Démarrer quand même',
                style: AppTextStyles.bodySemibold.copyWith(color: early ? AppColors.danger : AppColors.primary)),
          ),
        ],
      ),
    );
    return go == true;
  }

  Future<void> _startTrip() async {
    final trip = _trip;
    if (trip != null && !await _confirmLeavingWithout(trip)) return;
    if (!mounted) return;
    setState(() => _isStarting = true);
    try {
      await TripRepository().updateStatus(widget.tripId, TripStatus.inProgress);
      if (!mounted) return;
      setState(() {
        _isStarting = false;
        _trip = _trip?.copyWith(status: TripStatus.inProgress);
      });
      _tracker.start(widget.tripId);
      _broadcastCurrentGps();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isStarting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _completeTrip() async {
    // Passagers jamais validés à bord : le chauffeur dit s'ils ont voyagé.
    final notScanned = _confirmed.where((b) => !b.isBoarded).toList();
    final List<String>? notBoarded;
    if (notScanned.isEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd)),
          title: Text('Terminer ce trajet ?', style: AppTextStyles.title2),
          content: Text(
            'Vos passagers seront marqués comme arrivés et vos gains crédités sur votre portefeuille.',
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
      notBoarded = confirmed == true ? const [] : null;
    } else {
      notBoarded = await showCompleteTripSheet(context, notScanned);
    }
    if (notBoarded == null || !mounted) return;

    setState(() => _isCompleting = true);
    try {
      await TripRepository().complete(widget.tripId, notBoardedBookingIds: notBoarded);
      _tracker.stop();
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
        SnackBar(
          content: Text(e is ApiException ? e.message : 'Impossible de terminer le trajet. Réessayez.'),
        ),
      );
    }
  }

  void _openScanner() async {
    final result = await context.push<bool>('/trip/${widget.tripId}/scan');
    if (result == true) {
      _load();
    }
  }

  /// SOS visible pendant le trajet et autour du départ (2 h avant à 12 h après).
  bool get _showSos {
    final trip = _trip;
    if (trip == null) return false;
    if (trip.status == TripStatus.inProgress) return true;
    if (trip.status != TripStatus.upcoming) return false;
    final now = DateTime.now();
    return now.isAfter(trip.departureTime.subtract(const Duration(hours: 2))) &&
        now.isBefore(trip.departureTime.add(const Duration(hours: 12)));
  }

  bool _isSavingEnRoute = false;

  /// Affiché tout de suite, annulé si le backend refuse.
  Future<void> _setAcceptsEnRoute(bool value) async {
    setState(() {
      _isSavingEnRoute = true;
      _trip = _trip?.copyWith(acceptsEnRoute: value);
    });
    try {
      await TripRepository().setAcceptsEnRoute(widget.tripId, value);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _trip = _trip?.copyWith(acceptsEnRoute: !value));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isSavingEnRoute = false);
    }
  }

  /// Un passager ne peut être déclaré absent que sur un trajet pas terminé.
  bool get _canMarkAbsent => _trip?.status == TripStatus.upcoming || _trip?.status == TripStatus.inProgress;

  void _openSos() {
    final trip = _trip!;
    openSosScreen(
      context,
      api: SosRepository(),
      role: 'driver',
      tripId: trip.id,
      fallbackPosition: trip.currentLat != null && trip.currentLng != null
          ? (lat: trip.currentLat!, lng: trip.currentLng!)
          : null,
    );
  }

  /// L'action du moment, fixée en bas de l'écran : démarrer (dès qu'un
  /// passager est confirmé), puis terminer.
  Widget? get _mainAction {
    final trip = _trip;
    if (trip == null) return null;
    if (trip.status == TripStatus.upcoming && _confirmed.isNotEmpty) {
      return BottomActionBar(
        child: GlowButton(
          label: 'Démarrer le trajet',
          leadingIcon: Icons.play_arrow_rounded,
          isLoading: _isStarting,
          onPressed: _isStarting ? null : _startTrip,
        ),
      );
    }
    if (trip.status == TripStatus.inProgress) {
      return BottomActionBar(
        child: GlowButton(
          label: 'Terminer le trajet',
          leadingIcon: Icons.flag_rounded,
          isLoading: _isCompleting,
          onPressed: _isCompleting ? null : _completeTrip,
        ),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: _isLoading ? null : _mainAction,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _trip == null
              ? const Center(child: Text('Trajet introuvable'))
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _load,
                  child: CustomScrollView(
                    slivers: [
                      // ── En-tête : trajet, jour et heure, statut ──
                      SliverAppBar(
                        pinned: true,
                        toolbarHeight: 76,
                        backgroundColor: AppColors.background,
                        surfaceTintColor: Colors.transparent,
                        scrolledUnderElevation: 0.5,
                        automaticallyImplyLeading: false,
                        titleSpacing: 16,
                        title: Row(
                          children: [
                            GlassIconButton(
                              icon: Icons.arrow_back_rounded,
                              tooltip: 'Retour',
                              onPressed: () => context.canPop() ? context.pop() : context.go('/trips'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${_trip!.departure} → ${_trip!.arrival}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.title2.copyWith(fontSize: 19),
                                  ),
                                  Text(
                                    '${formatDayLabel(_trip!.departureTime)} · ${DateFormat('HH:mm').format(_trip!.departureTime)}',
                                    style: AppTextStyles.caption,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            _TripStatusBadge(status: _trip!.status),
                          ],
                        ),
                      ),

                      SliverPadding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            // ── Le temps : départ, attente au point de rendez-vous ──
                            EverySecond(builder: (context, now) {
                              final status = departureStatus(_trip!, _confirmed, now);
                              if (status == null) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: TimeStatusCard(status: status),
                              );
                            }),

                            // ── Live GPS Broadcast Banner when inProgress ──
                            if (_trip!.status == TripStatus.inProgress) ...[
                              _LiveGpsBanner(
                                lastSentAt: _lastGpsSentAt ?? _trip!.locationUpdatedAt,
                                permissionDenied: _gpsPermissionDenied,
                                onForceSend: _broadcastCurrentGps,
                              ),
                              const SizedBox(height: 16),
                            ],

                            // ── SOS : trajet en cours ou autour du départ ──
                            if (_showSos) ...[
                              SosButton(onTriggered: _openSos),
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
                                          ? AppColors.amber
                                          : AppColors.textSecondary,
                                      badge: _pendingCount > 0 ? _pendingCount : null,
                                      onTap: () => context.push('/trip/${widget.tripId}/requests'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              EnRouteSwitch(
                                value: _trip!.acceptsEnRoute,
                                onChanged: _isSavingEnRoute ? null : _setAcceptsEnRoute,
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
                                    color: AppColors.muted,
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
                            else if (_trip!.stops.length >= 2)
                              for (final stop in _trip!.stops)
                                _StopSection(
                                  stop: stop,
                                  isFirst: stop.position == 0,
                                  isLast: stop.position == _trip!.stops.last.position,
                                  boarding: [
                                    for (final b in _confirmed)
                                      if (boardsAt(b, stop)) b,
                                  ],
                                  alighting: [
                                    for (final b in _confirmed)
                                      if (b.alightingStop?.id == stop.id ||
                                          (b.alightingStop == null && stop.position == _trip!.stops.last.position))
                                        b,
                                  ],
                                  tripId: widget.tripId,
                                  onMarkAbsent: _canMarkAbsent ? _markAbsent : null,
                                )
                            else
                              ..._confirmed.map((b) => Padding(
                                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                                    child: PassengerTile(
                                      booking: b,
                                      tripId: widget.tripId,
                                      waitUntil: b.boardingStop?.waitUntil,
                                      onMarkAbsent: _canMarkAbsent ? _markAbsent : null,
                                    ),
                                  )),

                            const SizedBox(height: 20),

                            // ── Annuler : discret, en fin de page ──
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
    final (label, color, surface, icon) = switch (status) {
      TripStatus.upcoming => ('Programmé', AppColors.textPrimary, AppColors.muted, Icons.schedule_rounded),
      TripStatus.inProgress => ('En route', AppColors.success, AppColors.successSurface, Icons.navigation_rounded),
      TripStatus.completed => ('Terminé', AppColors.textSecondary, AppColors.muted, Icons.check_circle_rounded),
      TripStatus.cancelled => ('Annulé', AppColors.danger, AppColors.dangerSurface, Icons.cancel_rounded),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
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
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyLargeSemibold),
                const SizedBox(height: 3),
                // Plaque puis couleur, qui passe à la ligne à côté d'un
                // badge large (« Minibus 15 places »).
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
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
                    if (vehicle.color.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.muted,
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

/// Un point de rendez-vous du trajet : heure, adresse, accès à l'itinéraire,
/// passagers qui montent (avec leurs actions) et qui descendent.
class _StopSection extends StatelessWidget {
  final TripStop stop;
  final bool isFirst;
  final bool isLast;
  final List<Booking> boarding;
  final List<Booking> alighting;
  final String tripId;
  final Future<void> Function(Booking)? onMarkAbsent;

  const _StopSection({
    required this.stop,
    required this.isFirst,
    required this.isLast,
    required this.boarding,
    required this.alighting,
    required this.tripId,
    this.onMarkAbsent,
  });

  Future<void> _openDirections() async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${stop.lat},${stop.lng}&travelmode=driving',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final time = stop.scheduledAt != null ? DateFormat('HH:mm').format(stop.scheduledAt!) : '';
    final boardingSeats = boarding.fold<int>(0, (sum, b) => sum + b.seatsBooked);
    final summary = [
      if (boarding.isNotEmpty) '$boardingSeats à faire monter',
      if (alighting.isNotEmpty) '${alighting.length} à déposer',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(14),
      decoration: AppColors.softCardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isFirst
                    ? Icons.adjust_rounded
                    : isLast
                        ? Icons.location_on_rounded
                        : Icons.radio_button_checked_rounded,
                size: 22,
                color: AppColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [if (time.isNotEmpty) time, stop.name].join(' · '),
                      style: AppTextStyles.bodyLargeSemibold,
                    ),
                    if (stop.address != null && stop.address!.isNotEmpty && stop.address != stop.name)
                      Text(
                        stop.address!,
                        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      summary.isEmpty ? 'Aucun passager à cet arrêt' : summary,
                      style: AppTextStyles.caption.copyWith(
                        color: summary.isEmpty ? AppColors.textMuted : AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _openDirections,
                tooltip: 'Itinéraire vers ce point',
                icon: const Icon(Icons.directions_rounded, color: AppColors.primary),
              ),
            ],
          ),
          if (boarding.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final b in boarding)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: PassengerTile(
                  booking: b,
                  tripId: tripId,
                  waitUntil: stop.waitUntil,
                  onMarkAbsent: onMarkAbsent,
                ),
              ),
          ],
          if (alighting.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final b in alighting)
                  Chip(
                    avatar: const Icon(Icons.logout_rounded, size: 16, color: AppColors.textSecondary),
                    label: Text(
                      b.passengerName.isEmpty ? 'Passager' : b.passengerName,
                      style: AppTextStyles.caption,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
