import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/glow.dart';
import '../../../core/widgets/meeting_point_card.dart';
import '../../../core/widgets/trip_card.dart' show RouteTimeline, RouteTimelineStop, formatFcfa;
import '../../../models/proposed_stop.dart';
import '../../../models/trip.dart';
import '../../../providers/app_provider.dart';
import '../../../services/booking_repository.dart';
import '../../../services/trip_repository.dart';
import '../widgets/propose_stop_card.dart' show proposalSummary;

/// Récapitulatif avant d'envoyer la réservation : le trajet, le nombre de
/// places (le plan des sièges est facultatif), le point de rendez-vous, les
/// bagages, le paiement en espèces, et ce qui se passe ensuite. Un seul
/// bouton envoie la demande.
class BookingConfirmationScreen extends StatefulWidget {
  final String tripId;

  /// Places choisies sur le plan du véhicule (facultatif).
  final List<String> seatIds;

  /// Nombre de places quand aucune n'est choisie sur le plan.
  final int seatCount;

  /// Arrêts de montée et de descente (points de rendez-vous du chauffeur) ;
  /// à défaut, le trajet complet.
  final String? boardingStopId;
  final String? alightingStopId;

  /// Point proposé par le passager : le chauffeur doit accepter de l'ajouter.
  final ProposedStop? proposal;

  const BookingConfirmationScreen({
    super.key,
    required this.tripId,
    this.seatIds = const [],
    this.seatCount = 1,
    this.boardingStopId,
    this.alightingStopId,
    this.proposal,
  });

  @override
  State<BookingConfirmationScreen> createState() => _BookingConfirmationScreenState();
}

class _BookingConfirmationScreenState extends State<BookingConfirmationScreen> {
  Trip? _trip;
  bool _isLoading = true;
  bool _isConfirming = false;
  bool _hasHeavyLuggage = false;
  final List<File> _luggagePhotos = [];
  final ImagePicker _picker = ImagePicker();

  late List<String> _seats = [...widget.seatIds];
  late int _count = widget.seatIds.isNotEmpty ? widget.seatIds.length : math.max(1, widget.seatCount);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final trip = await TripRepository().fetch(widget.tripId);
    if (!mounted) return;
    setState(() {
      _trip = trip;
      _isLoading = false;
      if (trip != null) _count = _count.clamp(1, _maxSeats(trip));
    });
  }

  static int _maxSeats(Trip trip) => math.max(1, math.min(trip.availableSeats, 8));

  int get _places => _seats.isNotEmpty ? _seats.length : _count;

  TripSegment get _segment => _trip!.segment(
        boardingStopId: widget.boardingStopId,
        alightingStopId: widget.alightingStopId,
        proposal: widget.proposal,
      );

  /// `&board=…&alight=…` pour ouvrir le plan des sièges sur le même tronçon.
  String get _segmentQuery => [
        if (widget.boardingStopId != null) '&board=${widget.boardingStopId}',
        if (widget.alightingStopId != null) '&alight=${widget.alightingStopId}',
        if (widget.proposal != null) '&proposal=${widget.proposal!.toQuery()}',
      ].join();

  void _setCount(int count) {
    setState(() {
      _count = count.clamp(1, _maxSeats(_trip!));
      // Le nombre change : les places du plan ne correspondent plus.
      _seats = [];
    });
  }

  Future<void> _pickSeats() async {
    final picked = await context.push<List<String>>('/seat-selection?tripId=${widget.tripId}&pick=1$_segmentQuery');
    if (!mounted || picked == null || picked.isEmpty) return;
    setState(() {
      _seats = picked;
      _count = picked.length;
    });
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
      if (picked != null) setState(() => _luggagePhotos.add(File(picked.path)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible d’accéder à la photo.')));
    }
  }

  void _showPhotoSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Photo de vos bagages', style: AppTextStyles.title2),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Prendre une photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir dans la galerie'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm() async {
    final trip = _trip;
    final user = context.read<AppProvider>().user;
    if (trip == null || user == null) return;

    if (_hasHeavyLuggage && _luggagePhotos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajoutez une photo de vos bagages pour que le chauffeur prévoie la place.')),
      );
      return;
    }

    setState(() => _isConfirming = true);
    try {
      final booking = await BookingRepository().requestBooking(
        tripId: trip.id,
        passengerId: user.id,
        passengerName: user.name.isEmpty ? user.phoneNumber : user.name,
        passengerPhone: user.phoneNumber,
        seatIds: _seats,
        seatCount: _places,
        hasHeavyLuggage: _hasHeavyLuggage,
        luggagePhotos: _luggagePhotos,
        boardingStopId: _segment.boardingStopId,
        alightingStopId: _segment.alightingStopId,
        proposedStop: widget.proposal,
      );
      if (!mounted) return;
      context.go('/booking/success?bookingId=${booking.id}');
    } catch (e) {
      if (!mounted) return;
      final seatTaken = e is ApiException && (e.fieldErrors?.containsKey('seat_numbers') ?? false);
      setState(() {
        _isConfirming = false;
        // Places prises entre-temps : le chauffeur placera le passager.
        if (seatTaken) _seats = [];
      });
      final msg = e is ApiException && e.message.isNotEmpty ? e.message : 'La demande n’a pas pu être envoyée. Réessayez.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final trip = _trip;
    if (trip == null) {
      return Scaffold(
        appBar: BrandAppBar(title: 'Réservation', onBack: () => context.pop()),
        body: Center(child: Text('Trajet introuvable', style: AppTextStyles.title2)),
      );
    }
    final segment = _segment;
    final instant = trip.status == TripStatus.inProgress;
    final boardAt = segment.boarding?.scheduledAt ?? trip.departureTime;
    final arriveAt = segment.alighting?.scheduledAt ?? trip.departureTime.add(trip.estimatedDuration);
    final time = DateFormat('HH:mm');

    return Scaffold(
      appBar: BrandAppBar(
        title: 'Votre réservation',
        subtitle: toBeginningOfSentenceCase(DateFormat('EEEE d MMMM', 'fr_FR').format(boardAt)),
        onBack: () => context.pop(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _Card(
            child: RouteTimeline(
              stops: [
                RouteTimelineStop(
                  time: time.format(boardAt),
                  place: segment.boarding?.name ?? trip.departure,
                  hint: segment.boarding?.displayAddress ?? trip.departureAddress,
                ),
                RouteTimelineStop(
                  time: time.format(arriveAt),
                  place: segment.alighting?.name ?? trip.arrival,
                  hint: segment.alighting?.displayAddress ?? trip.arrivalAddress,
                ),
              ],
              duration: segment.durationLabel(trip),
            ),
          ),
          const SizedBox(height: 12),
          _SeatsCard(
            count: _places,
            max: _maxSeats(trip),
            seats: _seats,
            onCount: _setCount,
            onPickSeats: _pickSeats,
          ),
          if (widget.proposal != null) ...[
            const SizedBox(height: 12),
            _ProposalNotice(proposal: widget.proposal!),
          ],
          if (segment.boarding != null) ...[
            const SizedBox(height: 12),
            MeetingPointCard(stop: segment.boarding!),
          ],
          const SizedBox(height: 12),
          _LuggageCard(
            hasHeavyLuggage: _hasHeavyLuggage,
            photos: _luggagePhotos,
            onToggle: (value) => setState(() {
              _hasHeavyLuggage = value;
              if (!value) _luggagePhotos.clear();
            }),
            onAddPhoto: _showPhotoSourceSheet,
            onRemovePhoto: (index) => setState(() => _luggagePhotos.removeAt(index)),
          ),
          const SizedBox(height: 12),
          const _InfoRow(
            icon: Icons.payments_outlined,
            title: 'Paiement en espèces',
            body: 'Vous payez le chauffeur à la montée. Aucun frais caché.',
          ),
          const SizedBox(height: 8),
          _InfoRow(
            icon: instant ? Icons.bolt_rounded : Icons.notifications_active_outlined,
            title: instant ? 'Confirmation immédiate' : 'Le chauffeur confirme',
            body: instant
                ? 'Le trajet est déjà en route : votre place est réservée tout de suite.'
                : 'Il accepte ou refuse votre demande ; vous êtes prévenu par notification.',
          ),
        ],
      ),
      bottomNavigationBar: _ConfirmBar(
        pricePerSeat: segment.pricePerSeat,
        places: _places,
        isLoading: _isConfirming,
        instant: instant,
        onConfirm: _confirm,
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => NeuBox(padding: const EdgeInsets.all(16), child: child);
}

/// Nombre de places, avec le plan des sièges en option.
class _SeatsCard extends StatelessWidget {
  final int count;
  final int max;
  final List<String> seats;
  final ValueChanged<int> onCount;
  final VoidCallback onPickSeats;

  const _SeatsCard({
    required this.count,
    required this.max,
    required this.seats,
    required this.onCount,
    required this.onPickSeats,
  });

  @override
  Widget build(BuildContext context) {
    return NeuBox(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Places', style: AppTextStyles.bodyLargeSemibold),
                    Text(
                      seats.isEmpty
                          ? 'Le chauffeur vous place à la montée'
                          : 'Sur le plan : n° ${seats.join(', ')}',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
              _Stepper(value: count, min: 1, max: max, onChanged: onCount),
            ],
          ),
          TextButton.icon(
            onPressed: onPickSeats,
            icon: const Icon(Icons.event_seat_outlined, size: 18),
            label: Text(seats.isEmpty ? 'Choisir mes places sur le plan' : 'Changer de places'),
          ),
        ],
      ),
    );
  }
}

/// − valeur + : boutons ronds de 48 dp, valeur annoncée aux lecteurs d'écran.
class _Stepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _Stepper({required this.value, required this.min, required this.max, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String label, VoidCallback? onTap) => IconButton(
          tooltip: label,
          onPressed: onTap,
          style: IconButton.styleFrom(
            backgroundColor: AppColors.muted,
            disabledBackgroundColor: AppColors.muted.withValues(alpha: 0.5),
          ),
          icon: Icon(icon, size: 20),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(Icons.remove_rounded, 'Une place de moins', value > min ? () => onChanged(value - 1) : null),
        SizedBox(
          width: 36,
          child: Semantics(
            liveRegion: true,
            label: '$value place${value > 1 ? 's' : ''}',
            child: Text('$value', textAlign: TextAlign.center, style: AppTextStyles.title2),
          ),
        ),
        button(Icons.add_rounded, 'Une place de plus', value < max ? () => onChanged(value + 1) : null),
      ],
    );
  }
}

class _LuggageCard extends StatelessWidget {
  final bool hasHeavyLuggage;
  final List<File> photos;
  final ValueChanged<bool> onToggle;
  final VoidCallback onAddPhoto;
  final ValueChanged<int> onRemovePhoto;

  const _LuggageCard({
    required this.hasHeavyLuggage,
    required this.photos,
    required this.onToggle,
    required this.onAddPhoto,
    required this.onRemovePhoto,
  });

  @override
  Widget build(BuildContext context) {
    return NeuBox(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: hasHeavyLuggage,
            onChanged: onToggle,
            secondary: const Icon(Icons.luggage_outlined),
            title: Text('Bagages volumineux', style: AppTextStyles.bodyLargeSemibold),
            subtitle: Text('Valises, malles, cartons…', style: AppTextStyles.caption),
          ),
          if (hasHeavyLuggage) ...[
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 8),
              child: Text(
                'Ajoutez une photo : le chauffeur vérifie qu’il a la place dans son coffre.',
                style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary),
              ),
            ),
            SizedBox(
              height: 80,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  Material(
                    color: AppColors.muted,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: onAddPhoto,
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 80,
                        height: 80,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_a_photo_outlined),
                            const SizedBox(height: 4),
                            Text('Photo', style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  for (var i = 0; i < photos.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(photos[i], width: 80, height: 80, fit: BoxFit.cover),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: IconButton(
                              tooltip: 'Retirer la photo',
                              onPressed: () => onRemovePhoto(i),
                              style: IconButton.styleFrom(backgroundColor: Colors.black54, minimumSize: const Size(32, 32)),
                              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _InfoRow({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: AppColors.textPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.bodySemibold),
                Text(body, style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Barre fixe du bas : total (places × prix) et envoi de la demande.
class _ConfirmBar extends StatelessWidget {
  final double pricePerSeat;
  final int places;
  final bool isLoading;
  final bool instant;
  final VoidCallback onConfirm;

  const _ConfirmBar({
    required this.pricePerSeat,
    required this.places,
    required this.isLoading,
    required this.instant,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return BottomActionBar(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  places > 1 ? '$places places × ${formatFcfa(pricePerSeat)}' : '1 place',
                  style: AppTextStyles.caption,
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(formatFcfa(pricePerSeat * places), maxLines: 1, style: AppTextStyles.priceLarge.copyWith(fontSize: 21)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GlowButton(
            label: instant ? 'Réserver' : 'Envoyer la demande',
            expanded: false,
            isLoading: isLoading,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            onPressed: isLoading ? null : onConfirm,
          ),
        ],
      ),
    );
  }
}

/// Rappel avant d'envoyer : le point proposé dépend de l'accord du chauffeur.
class _ProposalNotice extends StatelessWidget {
  final ProposedStop proposal;

  const _ProposalNotice({required this.proposal});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.brandSurface, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.add_location_alt_outlined, color: AppColors.brandText),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Vous proposez de ${proposal.isBoarding ? 'monter' : 'descendre'} à ${proposal.name}. '
              '${proposalSummary(proposal)}',
              style: AppTextStyles.body,
            ),
          ),
        ],
      ),
    );
  }
}
