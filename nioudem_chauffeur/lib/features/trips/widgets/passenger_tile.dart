import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/countdown.dart';
import '../../../core/widgets/driver_avatar.dart';
import '../../../core/widgets/fojem_button.dart';
import '../../../models/booking.dart';
import '../../../providers/app_provider.dart';
import '../../../services/chat_repository.dart';

/// Fiche d'un passager confirmé sur l'écran du trajet : statut à bord,
/// position partagée, appel, message et « Absent » (décompté jusqu'à la fin
/// de l'attente au point de montée).
class PassengerTile extends StatefulWidget {
  final Booking booking;
  final String tripId;

  /// Déclarer le passager absent ; null quand le trajet est terminé.
  final Future<void> Function(Booking)? onMarkAbsent;

  /// Fin de l'attente au point de montée : « Absent » s'active à cette heure.
  final DateTime? waitUntil;

  const PassengerTile({
    super.key,
    required this.booking,
    required this.tripId,
    this.onMarkAbsent,
    this.waitUntil,
  });

  @override
  State<PassengerTile> createState() => _PassengerTileState();
}

class _PassengerTileState extends State<PassengerTile> {
  bool _isOpeningChat = false;
  bool _isMarkingAbsent = false;

  Future<void> _markAbsent() async {
    setState(() => _isMarkingAbsent = true);
    try {
      await widget.onMarkAbsent!(widget.booking);
    } finally {
      if (mounted) setState(() => _isMarkingAbsent = false);
    }
  }

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
    // Seul un passager confirmé, pas encore à bord, peut être absent ; et
    // seulement tant que le trajet n'est pas terminé (onMarkAbsent non nul).
    final canMarkAbsent =
        booking.status == BookingStatus.confirmed && !isBoarded && widget.onMarkAbsent != null;

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
                        // Le code à 4 chiffres n'est pas affiché ici : il doit
                        // venir du billet du passager pour prouver sa présence.
                        if (!isBoarded && booking.passengerLocation != null) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: GestureDetector(
                              onTap: () => _showPassengerLocation(context, booking),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.successSurface,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Position partagée · ${DateFormat('HH:mm').format(booking.passengerLocation!.updatedAt)}',
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.caption.copyWith(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
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
              if (canMarkAbsent) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: EverySecond(builder: (context, now) {
                    final left = widget.waitUntil?.difference(now);
                    final waiting = left != null && left > Duration.zero;
                    return _SmallActionButton(
                      icon: waiting ? Icons.hourglass_bottom_rounded : Icons.person_off_outlined,
                      label: waiting ? 'Absent · ${formatCountdown(left)}' : 'Absent',
                      isLoading: _isMarkingAbsent,
                      onTap: _isMarkingAbsent || waiting ? null : _markAbsent,
                    );
                  }),
                ),
              ],
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
    final color = onTap == null && !isLoading ? AppColors.textMuted : AppColors.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        // Trois boutons côte à côte sur un écran étroit : le libellé
        // rétrécit un peu plutôt que de déborder.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primary),
                )
              else
                Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTextStyles.bodySemibold.copyWith(
                  fontSize: 12,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Position partagée par un passager avant l'embarquement : carte et
/// itinéraire jusqu'à lui.
void _showPassengerLocation(BuildContext context, Booking booking) {
  final location = booking.passengerLocation;
  if (location == null) return;
  final point = ll.LatLng(location.lat, location.lng);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Position de ${booking.passengerName}', style: AppTextStyles.title2),
          const SizedBox(height: 4),
          Text(
            'Partagée par le passager · mise à jour à ${DateFormat('HH:mm').format(location.updatedAt)}',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 240,
              child: FlutterMap(
                options: MapOptions(initialCenter: point, initialZoom: 16),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'sn.fojem.chauffeur',
                  ),
                  MarkerLayer(markers: [
                    Marker(
                      point: point,
                      width: 44,
                      height: 44,
                      child: const Icon(Icons.person_pin_circle_rounded, color: AppColors.accent, size: 44),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          FojemButton.primary(
            label: 'Itinéraire jusqu’au passager',
            prefixIcon: Icons.directions_rounded,
            onPressed: () => launchUrl(
              Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${location.lat},${location.lng}'),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
    ),
  );
}
