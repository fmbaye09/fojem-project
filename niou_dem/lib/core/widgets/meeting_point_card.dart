import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:url_launcher/url_launcher.dart';
import '../../models/trip_stop.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'glow.dart';

/// Ouvre l'itinéraire vers [stop] dans Google Maps (ou l'app de navigation
/// installée) : c'est le passager qui se rend au point de rendez-vous.
Future<void> openDirectionsTo(TripStop stop) {
  return launchUrl(
    Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${stop.lat},${stop.lng}'),
    mode: LaunchMode.externalApplication,
  );
}

/// « Votre point de rendez-vous » : où et quand retrouver le chauffeur,
/// avec une mini-carte et l'accès à l'itinéraire.
class MeetingPointCard extends StatelessWidget {
  final TripStop stop;
  final String title;

  const MeetingPointCard({super.key, required this.stop, this.title = 'Votre point de rendez-vous'});

  @override
  Widget build(BuildContext context) {
    final point = ll.LatLng(stop.lat, stop.lng);
    final time = stop.scheduledAt != null ? DateFormat('HH:mm').format(stop.scheduledAt!) : null;
    return Container(
      decoration: AppColors.softCardDecoration,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 130,
            child: IgnorePointer(
              child: FlutterMap(
                options: MapOptions(initialCenter: point, initialZoom: 15),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'sn.fojem.app',
                  ),
                  MarkerLayer(markers: [
                    Marker(
                      point: point,
                      width: 40,
                      height: 40,
                      alignment: Alignment.topCenter,
                      child: const Icon(Icons.location_on, color: AppColors.primary, size: 40),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          Padding(
            padding: AppSpacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Text(
                  time != null ? '${stop.name} · $time' : stop.name,
                  style: AppTextStyles.bodyLargeSemibold,
                ),
                if (stop.displayAddress != stop.name) ...[
                  const SizedBox(height: 2),
                  Text(stop.displayAddress, style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
                ],
                const SizedBox(height: 4),
                Text(
                  'Le chauffeur vous attend à ce point : soyez-y quelques minutes avant l’heure.',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 10),
                NeuButton(
                  label: 'M’y rendre',
                  icon: Icons.navigation_rounded,
                  color: AppColors.accent,
                  onPressed: () => openDirectionsTo(stop),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
