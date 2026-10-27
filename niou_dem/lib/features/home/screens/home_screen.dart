import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/events/data_refresh.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/geo/senegal_city_coordinates.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bottom_nav_bar.dart';
import '../../../core/geo/geo_location.dart';
import '../../../core/widgets/location_picker_screen.dart';
import '../../../core/widgets/glow.dart';
import '../../../core/widgets/notification_bell.dart';
import '../../../core/widgets/trip_card.dart';
import '../../../core/widgets/trust_banner.dart';
import 'package:intl/intl.dart';
import '../../../models/booking.dart';
import '../../../models/trip.dart';
import '../../../providers/app_provider.dart';
import '../../../providers/search_provider.dart';
import '../../../services/booking_repository.dart';
import '../../../services/trip_repository.dart';

/// Accueil voyageur « Glow Flow » : en-tête en dégradé (salutation, cloche),
/// carte de recherche en verre qui le chevauche, réservation en cours,
/// prochains départs, bandeau de confiance.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with AutoRefresh<HomeScreen> {
  @override
  Future<void> onAutoRefresh() => _loadNearby(silent: true);

  bool _isLoading = true;
  bool _hasError = false;
  List<Trip> _nearby = [];
  Booking? _activeBooking;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadNearby();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _loadNearby(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadNearby({bool silent = false}) async {
    final search = context.read<SearchProvider>();
    final origin = search.origin ?? coordinatesForCity('Dakar');
    final destination = search.destination ?? coordinatesForCity('Thiès');

    final userId = context.read<AppProvider>().user?.id;
    Booking? activeBooking;
    if (userId != null) {
      try {
        final bookings = await BookingRepository().fetchForPassenger(userId);
        final activeList = bookings.where((b) =>
            b.status == BookingStatus.pending || b.status == BookingStatus.confirmed
        ).toList();
        if (activeList.isNotEmpty) {
          activeBooking = activeList.first;
        }
      } catch (_) {}
    }

    try {
      final trips = await TripRepository()
          .search(origin: origin, destination: destination)
          .timeout(const Duration(seconds: 15));
      final nearby = trips.where((t) => !t.isFull).toList()
        ..sort((a, b) => a.departureTime.compareTo(b.departureTime));
      if (!mounted) return;
      setState(() {
        _activeBooking = activeBooking;
        _nearby = nearby.take(3).toList();
        _isLoading = false;
        _hasError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _activeBooking = activeBooking;
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
        onRefresh: _loadNearby,
        header: BrandHeader(
          title: firstName == null ? 'Bonjour' : 'Bonjour, $firstName',
          subtitle: 'Où allez-vous aujourd’hui ?',
          trailing: const NotificationBellButton(onBrand: true),
          overlap: 64,
        ),
        children: [
          const RiseIn(child: _SearchCard()),
          const SizedBox(height: 16),
          if (_activeBooking != null) ...[
            RiseIn(
              delay: const Duration(milliseconds: 80),
              child: _ActiveBookingCard(booking: _activeBooking!),
            ),
            const SizedBox(height: 16),
          ],
          Text('Prochains départs', style: AppTextStyles.title2),
          const SizedBox(height: 8),
          if (_isLoading) ...[
            const TripCardSkeleton(),
            const SizedBox(height: 16),
            const TripCardSkeleton(),
            const SizedBox(height: 16),
          ] else if (_hasError)
            const _InlineNotice(
              text: 'Impossible de charger les trajets. Tirez vers le bas pour réessayer.',
            )
          else if (_nearby.isEmpty)
            const _InlineNotice(
              text: 'Aucun trajet prévu sur cet itinéraire pour le moment.',
            )
          else
            for (var i = 0; i < _nearby.length; i++) ...[
              RiseIn(
                delay: Duration(milliseconds: 120 + 70 * i),
                child: TripCard(
                  trip: _nearby[i],
                  onTap: () => context.push(tripDetailLocation(_nearby[i])),
                ),
              ),
              const SizedBox(height: 16),
            ],
          const SizedBox(height: 4),
          const TrustBanner(),
        ],
      ),
      bottomNavigationBar: const TravelerBottomNavBar(current: ClientTab.home),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  final String text;

  const _InlineNotice({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassPanel(
        radius: 24,
        child: Text(text, style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
      ),
    );
  }
}

// ─── Carte de recherche ───────────────────────────────────────────────────

/// Carte de recherche en verre (template) : départ / arrivée en creux avec
/// bouton d'inversion, « Aujourd'hui / Plus tard », bouton à dégradé.
class _SearchCard extends StatelessWidget {
  const _SearchCard();

  /// Adresse, quartier, gare ou position GPS : la recherche trouve les
  /// points de rendez-vous des chauffeurs proches de ce lieu.
  Future<void> _pickPlace(BuildContext context, {required bool isDeparture}) async {
    final search = context.read<SearchProvider>();
    final picked = await Navigator.of(context).push<GeoLocation>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          title: isDeparture ? 'D’où partez-vous ?' : 'Où allez-vous ?',
          initial: isDeparture ? search.origin : search.destination,
        ),
      ),
    );
    if (picked == null) return;
    isDeparture ? search.setOrigin(picked) : search.setDestination(picked);
  }

  Future<void> _pickDate(BuildContext context) async {
    final search = context.read<SearchProvider>();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: search.date.isAfter(today) ? search.date : today.add(const Duration(days: 1)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 90)),
      locale: const Locale('fr', 'FR'),
    );
    if (picked != null) search.setDate(picked);
  }

  static bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final search = context.watch<SearchProvider>();
    final today = _isToday(search.date);

    return GlassPanel(
      radius: 32,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            alignment: Alignment.centerRight,
            children: [
              Column(
                children: [
                  _PlaceField(
                    icon: Icons.radio_button_unchecked_rounded,
                    iconColor: AppColors.primary,
                    value: search.departure,
                    placeholder: 'D’où partez-vous ?',
                    onTap: () => _pickPlace(context, isDeparture: true),
                  ),
                  const SizedBox(height: 12),
                  _PlaceField(
                    icon: Icons.place_rounded,
                    iconColor: AppColors.accent,
                    value: search.arrival,
                    placeholder: 'Où allez-vous ?',
                    onTap: () => _pickPlace(context, isDeparture: false),
                  ),
                ],
              ),
              Positioned(
                right: 12,
                child: NeuBox(
                  small: true,
                  radius: 20,
                  padding: const EdgeInsets.all(8),
                  onTap: search.swap,
                  child: const Icon(Icons.swap_vert_rounded, size: 20, color: AppColors.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GlowSegmented<bool>(
            value: today,
            options: [
              (true, 'Aujourd’hui'),
              (false, today ? 'Plus tard' : formatDayLabel(search.date)),
            ],
            onChanged: (isToday) {
              if (isToday) {
                search.setDate(DateTime.now());
              } else {
                _pickDate(context);
              }
            },
          ),
          const SizedBox(height: 14),
          GlowButton(
            label: 'Rechercher un trajet',
            leadingIcon: Icons.search_rounded,
            onPressed: search.hasSearch ? () => context.push('/search') : null,
          ),
        ],
      ),
    );
  }
}

/// Champ départ / arrivée « en creux ».
class _PlaceField extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String? value;
  final String placeholder;
  final VoidCallback onTap;

  const _PlaceField({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.placeholder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: NeuInset(
        radius: 18,
        padding: const EdgeInsets.fromLTRB(16, 15, 60, 15),
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value ?? placeholder,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyLargeSemibold.copyWith(
                  color: value == null ? AppColors.textMuted : AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Réservation en cours : ligne compacte vers le billet (template).
class _ActiveBookingCard extends StatelessWidget {
  final Booking booking;

  const _ActiveBookingCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final trip = booking.trip;
    final isConfirmed = booking.status == BookingStatus.confirmed;
    final isBoarded = booking.isBoarded;
    final statusColor = isBoarded || isConfirmed ? AppColors.success : AppColors.amber;
    final statusLabel = isBoarded
        ? 'À bord du véhicule'
        : (isConfirmed ? 'Réservation confirmée' : 'Demande en attente');
    final when = booking.boardingStop?.scheduledAt ?? trip?.departureTime;

    return NeuBox(
      onTap: () => context.push('/trip/${booking.tripId}/tracking'),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              isConfirmed ? Icons.qr_code_2_rounded : Icons.hourglass_top_rounded,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('● $statusLabel',
                    style: AppTextStyles.caption.copyWith(color: statusColor, fontWeight: FontWeight.w800)),
                Text(
                  '${booking.boardingStop?.name ?? trip?.departure ?? 'Départ'} → '
                  '${booking.alightingStop?.name ?? trip?.arrival ?? 'Arrivée'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySemibold.copyWith(fontWeight: FontWeight.w800),
                ),
                if (when != null)
                  Text(
                    '${DateFormat('EEE d MMM · HH:mm', 'fr_FR').format(when)} · ${booking.seatLabel}',
                    style: AppTextStyles.caption,
                  ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ],
      ),
    );
  }
}
