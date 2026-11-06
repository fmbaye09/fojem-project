import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/proposed_stop.dart';
import '../../../models/trip_stop.dart';

/// Le point proposé, sous la forme d'un arrêt, pour l'afficher comme les autres.
TripStop proposedAsStop(ProposedStop proposal) => TripStop(
      id: '',
      position: -1,
      name: proposal.name,
      address: proposal.address,
      lat: proposal.lat,
      lng: proposal.lng,
      scheduledAt: proposal.scheduledAt,
      priceFromOrigin: proposal.priceFromOrigin,
    );

/// Demande avec un point hors des arrêts du trajet : le chauffeur voit le
/// détour et le point sur la carte avant d'accepter.
class ProposedStopNotice extends StatelessWidget {
  final ProposedStop proposal;
  final List<TripStop> tripStops;

  const ProposedStopNotice({super.key, required this.proposal, this.tripStops = const []});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.amberSurface,
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.add_location_alt_rounded, size: 20, color: AppColors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Nouvel arrêt proposé : ${proposal.name}',
                  style: AppTextStyles.bodySemibold.copyWith(color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              '${proposal.detourMinutes <= 1 ? 'Presque aucun détour' : 'Environ ${proposal.detourMinutes} min de détour'} pour vous. '
              'En acceptant, l’arrêt s’ajoute à votre trajet et les passagers qui montent après sont prévenus de leur nouvelle heure.',
              style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _showOnMap(context),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('Voir sur la carte'),
            ),
          ),
        ],
      ),
    );
  }

  void _showOnMap(BuildContext context) {
    final point = ll.LatLng(proposal.lat, proposal.lng);
    final route = [for (final s in tripStops) ll.LatLng(s.lat, s.lng)];
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
            Text(proposal.name, style: AppTextStyles.title2),
            const SizedBox(height: 4),
            Text(
              [
                proposal.displayAddress,
                if (proposal.scheduledAt != null) 'passage vers ${DateFormat('HH:mm').format(proposal.scheduledAt!)}',
              ].join(' · '),
              style: AppTextStyles.caption,
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 260,
                child: FlutterMap(
                  options: route.length >= 2
                      ? MapOptions(
                          initialCameraFit: CameraFit.coordinates(
                            coordinates: [...route, point],
                            padding: const EdgeInsets.all(36),
                          ),
                        )
                      : MapOptions(initialCenter: point, initialZoom: 13),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'sn.fojem.chauffeur',
                    ),
                    if (route.length >= 2)
                      PolylineLayer(polylines: [
                        Polyline(points: route, strokeWidth: 3, color: AppColors.primary.withValues(alpha: 0.5)),
                      ]),
                    MarkerLayer(markers: [
                      for (final stop in route)
                        Marker(
                          point: stop,
                          width: 16,
                          height: 16,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.primary, width: 3),
                            ),
                          ),
                        ),
                      Marker(
                        point: point,
                        width: 44,
                        height: 44,
                        child: const Icon(Icons.add_location_alt_rounded, color: AppColors.amber, size: 40),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Le chauffeur confirme qu'il ajoute l'arrêt avant d'accepter la demande.
Future<bool> confirmAddProposedStop(BuildContext context, ProposedStop proposal) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Ajouter l’arrêt ${proposal.name} ?'),
      content: Text(
        'Votre trajet passera par ce point'
        '${proposal.detourMinutes > 1 ? ', environ ${proposal.detourMinutes} min de détour' : ''}. '
        'Les heures des arrêts suivants seront décalées d’autant et leurs passagers prévenus.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ajouter et accepter')),
      ],
    ),
  );
  return confirmed == true;
}
