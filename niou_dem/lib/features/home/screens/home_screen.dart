import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/geo/senegal_city_coordinates.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bottom_nav_bar.dart';
import '../../../core/widgets/city_selector.dart';
import '../../../core/widgets/fojem_logo.dart';
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

/// Accueil voyageur — fidèle à la maquette : logo + cloche, salutation,
/// carte de recherche (départ, arrivée, date, bouton), "Trajets près de
/// vous", bandeau de confiance.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
    final origin = coordinatesForCity(search.departure ?? 'Dakar');
    final destination = coordinatesForCity(search.arrival ?? 'Thiès');

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
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _loadNearby,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              const Row(
                children: [
                  FojemLogo.icon(size: 40),
                  Spacer(),
                  NotificationBellButton(),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                firstName == null ? 'Bonjour' : 'Bonjour, $firstName',
                style: AppTextStyles.display
                    .copyWith(fontSize: 28, letterSpacing: -0.6),
              ),
              const SizedBox(height: 6),
              Text(
                'Trouvez un trajet fiable et économique',
                style: AppTextStyles.bodyLarge.copyWith(
                  fontSize: 15.5,
                  color: AppColors.textSecondary,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 24),
              if (_activeBooking != null) ...[
                _ActiveBookingCard(booking: _activeBooking!),
                const SizedBox(height: 12),
              ],
              const _SearchCard(),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Trajets près de vous',
                      style: AppTextStyles.title1
                          .copyWith(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.go('/trips'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.only(left: 12, right: 4),
                      minimumSize: const Size(0, 44),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Voir tout',
                            style: AppTextStyles.bodyLarge.copyWith(
                              fontSize: 15,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w500,
                              height: 1,
                            )),
                        const SizedBox(width: 6),
                        const Icon(Icons.chevron_right_rounded, size: 24),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_isLoading) ...[
                const TripCardSkeleton(),
                const SizedBox(height: 14),
                const TripCardSkeleton(),
                const SizedBox(height: 14),
              ] else if (_hasError)
                const _InlineNotice(
                  text:
                      'Impossible de charger les trajets. Tirez vers le bas pour réessayer.',
                )
              else if (_nearby.isEmpty)
                const _InlineNotice(
                  text:
                      'Aucun trajet prévu au départ de chez vous pour le moment.',
                )
              else
                for (final trip in _nearby) ...[
                  TripCard(
                    trip: trip,
                    onTap: () => context.push('/trip/${trip.id}'),
                  ),
                  const SizedBox(height: 14),
                ],
              const SizedBox(height: 6),
              const TrustBanner(),
            ],
          ),
        ),
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
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: AppColors.softCardDecoration,
      child: Text(text,
          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
    );
  }
}

// ─── Carte de recherche ───────────────────────────────────────────────────

const double _railWidth = 40;
const double _cityRowHeight = 72;

class _SearchCard extends StatelessWidget {
  const _SearchCard();

  Future<void> _pickCity(BuildContext context,
      {required bool isDeparture}) async {
    final search = context.read<SearchProvider>();
    final city = await showCitySelector(
      context,
      title: isDeparture ? 'Ville de départ' : 'Ville d’arrivée',
      excludeCity: isDeparture ? search.arrival : search.departure,
    );
    if (city == null) return;
    isDeparture ? search.setDeparture(city) : search.setArrival(city);
  }

  Future<void> _pickDate(BuildContext context) async {
    final search = context.read<SearchProvider>();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: search.date.isBefore(today) ? today : search.date,
      firstDate: today,
      lastDate: today.add(const Duration(days: 90)),
      locale: const Locale('fr', 'FR'),
    );
    if (picked != null) search.setDate(picked);
  }

  @override
  Widget build(BuildContext context) {
    final search = context.watch<SearchProvider>();

    return Container(
      decoration: AppColors.softCardDecoration,
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            const SizedBox(height: 4),
            Stack(
              children: [
                Column(
                  children: [
                    _CityRow(
                      label: 'Départ',
                      city: search.departure,
                      placeholder: 'D’où partez-vous ?',
                      onTap: () => _pickCity(context, isDeparture: true),
                    ),
                    const _Divider(indent: 16 + _railWidth + 12),
                    _CityRow(
                      label: 'Arrivée',
                      city: search.arrival,
                      placeholder: 'Où allez-vous ?',
                      onTap: () => _pickCity(context, isDeparture: false),
                    ),
                  ],
                ),
                const Positioned(
                  left: 16,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(child: _RouteRail()),
                ),
              ],
            ),
            const _Divider(indent: 16),
            _FieldRow(
              onTap: () => _pickDate(context),
              leading: const Icon(Icons.calendar_month_rounded,
                  size: 24, color: AppColors.textPrimary),
              height: 62,
              child: Text(formatDayLabel(search.date), style: _valueStyle),
            ),
            const _Divider(indent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed:
                      search.hasSearch ? () => context.push('/trips') : null,
                  icon: const Icon(Icons.search_rounded, size: 22),
                  label: const Text('Rechercher un trajet'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppColors.primary.withValues(alpha: 0.4),
                    disabledForegroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppSpacing.borderRadiusButton),
                    ),
                    textStyle:
                        AppTextStyles.buttonLarge.copyWith(fontSize: 16.5),
                    elevation: 0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final TextStyle _valueStyle = AppTextStyles.bodyLargeSemibold.copyWith(
  fontSize: 16.5,
  height: 1.2,
);

class _CityRow extends StatelessWidget {
  final String label;
  final String? city;
  final String placeholder;
  final VoidCallback onTap;

  const _CityRow({
    required this.label,
    required this.city,
    required this.placeholder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _FieldRow(
      onTap: onTap,
      height: _cityRowHeight,
      leading: const SizedBox.shrink(),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.body.copyWith(
              color: AppColors.textSecondary,
              fontSize: 13.5,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            city == null ? placeholder : '$city, Sénégal',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: city == null
                ? _valueStyle.copyWith(color: AppColors.textMuted)
                : _valueStyle,
          ),
        ],
      ),
    );
  }
}

/// Ligne touchable de la carte : colonne d'icône fixe, contenu, chevron.
class _FieldRow extends StatelessWidget {
  final VoidCallback onTap;
  final Widget leading;
  final Widget child;
  final double height;

  const _FieldRow({
    required this.onTap,
    required this.leading,
    required this.child,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 20),
          child: Row(
            children: [
              SizedBox(width: _railWidth, child: Center(child: leading)),
              const SizedBox(width: 12),
              Expanded(child: child),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  size: 24, color: AppColors.textPrimary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rail gauche départ → arrivée : pastille grise "origine", point orange,
/// pointillés gris, épingle orange — chaque icône centrée sur sa ligne.
class _RouteRail extends StatelessWidget {
  const _RouteRail();

  @override
  Widget build(BuildContext context) {
    Widget dot(Color color, double size) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        );

    return SizedBox(
      width: _railWidth,
      child: Column(
        children: [
          const SizedBox(height: (_cityRowHeight - 40) / 2),
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Color(0xFFEFEDE9),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.adjust_rounded,
                size: 20, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          dot(AppColors.primary, 7),
          const SizedBox(height: 5),
          dot(AppColors.borderStrong, 5),
          const SizedBox(height: 5),
          dot(AppColors.borderStrong, 5),
          const SizedBox(height: 4),
          const Icon(Icons.location_on_rounded,
              size: 30, color: AppColors.primary),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final double indent;

  const _Divider({required this.indent});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent, right: 16),
      child: const Divider(height: 1, thickness: 1, color: Color(0xFFECEAE5)),
    );
  }
}

class _ActiveBookingCard extends StatelessWidget {
  final Booking booking;

  const _ActiveBookingCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final trip = booking.trip;
    final isConfirmed = booking.status == BookingStatus.confirmed;
    final isBoarded = booking.isBoarded;

    final Color accentColor = isBoarded
        ? const Color(0xFF2E7D32)
        : (isConfirmed ? AppColors.primary : const Color(0xFFD97706));

    final Color bgSurface = isBoarded
        ? const Color(0xFFF1F8F4)
        : (isConfirmed ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB));

    final String statusLabel = isBoarded
        ? 'À bord du véhicule'
        : (isConfirmed ? 'Réservation confirmée' : 'Demande en attente');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/trip/${booking.tripId}/tracking'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: bgSurface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isBoarded
                                ? Icons.check_circle_rounded
                                : (isConfirmed ? Icons.qr_code_2_rounded : Icons.hourglass_top_rounded),
                            size: 14,
                            color: accentColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            statusLabel,
                            style: AppTextStyles.caption.copyWith(
                              color: accentColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textSecondary),
                  ],
                ),
                const SizedBox(height: 12),

                // Trajet
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${trip?.departure ?? 'Départ'} → ${trip?.arrival ?? 'Arrivée'}',
                            style: AppTextStyles.bodyLargeSemibold.copyWith(fontSize: 16),
                          ),
                          if (trip != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${DateFormat('EEEE d MMM à HH:mm', 'fr_FR').format(trip.departureTime)} • ${booking.seatLabel}',
                              style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Bottom row with QR shortcut or tracking hint
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: bgSurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isConfirmed ? Icons.qr_code_scanner_rounded : Icons.info_outline_rounded,
                        size: 18,
                        color: accentColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isConfirmed
                              ? (isBoarded
                                  ? 'Présence confirmée • Bon voyage !'
                                  : 'Code QR disponible pour le départ')
                              : 'En attente de validation par le chauffeur',
                          style: AppTextStyles.caption.copyWith(
                            color: accentColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        'Suivi →',
                        style: AppTextStyles.caption.copyWith(
                          color: accentColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
