import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glow.dart';
import '../../../core/widgets/trip_card.dart' show formatFcfa;
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/fojem_button.dart';
import '../../../core/widgets/meeting_point_card.dart';
import '../../../core/widgets/price_display.dart';
import '../../../models/trip.dart';
import '../../../providers/app_provider.dart';
import '../../../services/booking_repository.dart';
import '../../../services/trip_repository.dart';

class BookingConfirmationScreen extends StatefulWidget {
  final String tripId;

  /// Sièges choisis sur le plan du véhicule (au moins un).
  final List<String> seatIds;

  /// Arrêts de montée et de descente (points de rendez-vous du chauffeur) ;
  /// à défaut, le trajet complet.
  final String? boardingStopId;
  final String? alightingStopId;

  const BookingConfirmationScreen({
    super.key,
    required this.tripId,
    required this.seatIds,
    this.boardingStopId,
    this.alightingStopId,
  });

  @override
  State<BookingConfirmationScreen> createState() =>
      _BookingConfirmationScreenState();
}

class _BookingConfirmationScreenState
    extends State<BookingConfirmationScreen> {
  Trip? _trip;
  bool _isLoading = true;
  bool _isConfirming = false;
  bool _hasHeavyLuggage = false;
  final List<File> _luggagePhotos = [];
  final ImagePicker _picker = ImagePicker();

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
    });
  }

  TripSegment get _segment => _trip!.segment(
        boardingStopId: widget.boardingStopId,
        alightingStopId: widget.alightingStopId,
      );

  /// `&board=…&alight=…` pour revenir au plan des sièges sans perdre le tronçon.
  String get _segmentQuery => [
        if (widget.boardingStopId != null) '&board=${widget.boardingStopId}',
        if (widget.alightingStopId != null) '&alight=${widget.alightingStopId}',
      ].join();

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked != null) {
        setState(() {
          _luggagePhotos.add(File(picked.path));
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d\'accéder à la photo.')),
      );
    }
  }

  void _showPhotoSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.borderRadiusLg)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Photo de vos bagages', style: AppTextStyles.bodyLargeSemibold),
              const SizedBox(height: AppSpacing.sm),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: AppColors.primary),
                title: Text('Prendre une photo (Appareil photo)', style: AppTextStyles.body),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickPhoto(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: AppColors.primary),
                title: Text('Choisir dans la galerie', style: AppTextStyles.body),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickPhoto(ImageSource.gallery);
                },
              ),
            ],
          ),
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
        const SnackBar(
          content: Text('Veuillez ajouter au moins une photo de vos bagages lourds.'),
          backgroundColor: AppColors.danger,
        ),
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
        seatIds: widget.seatIds,
        hasHeavyLuggage: _hasHeavyLuggage,
        luggagePhotos: _luggagePhotos,
        boardingStopId: _segment.boarding?.id,
        alightingStopId: _segment.alighting?.id,
      );
      if (!mounted) return;
      context.go('/booking/success?bookingId=${booking.id}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isConfirming = false);
      final msg = e is ApiException && e.message.isNotEmpty
          ? e.message
          : 'Échec de la demande de réservation. Réessayez.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      // Place prise entre-temps par un autre passager : retour au plan,
      // rechargé avec les sièges à jour.
      if (e is ApiException && (e.fieldErrors?.containsKey('seat_numbers') ?? false)) {
        context.pushReplacement('/seat-selection?tripId=${trip.id}$_segmentQuery');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    if (_trip == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(leading: IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back))),
        body: const Center(child: Text('Trajet introuvable')),
      );
    }
    final trip = _trip!;
    final segment = _segment;
    final user = context.watch<AppProvider>().user;

    if (widget.seatIds.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(leading: IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: FojemButton.primary(
              label: 'Choisir une place',
              onPressed: () => context.pushReplacement('/seat-selection?tripId=${trip.id}$_segmentQuery'),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BrandAppBar(
        title: 'Confirmer la réservation',
        subtitle: '${segment.boarding?.name ?? trip.departure} → ${segment.alighting?.name ?? trip.arrival}',
        onBack: () => context.pop(),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TripSummaryCard(trip: trip, segment: segment),
                  const SizedBox(height: AppSpacing.lg),
                  if (segment.boarding != null) ...[
                    MeetingPointCard(stop: segment.boarding!),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  Text(
                    widget.seatIds.length > 1 ? 'Vos places' : 'Votre place',
                    style: AppTextStyles.title2,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _SeatSummary(seatIds: widget.seatIds),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Récapitulatif passager', style: AppTextStyles.title2),
                  const SizedBox(height: AppSpacing.md),
                  _PassengerSummary(
                    name: user?.name.isNotEmpty == true ? user!.name : 'Votre profil',
                    phone: user?.phoneNumber ?? '',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _LuggageSection(
                    hasHeavyLuggage: _hasHeavyLuggage,
                    photos: _luggagePhotos,
                    onToggle: (val) {
                      setState(() {
                        _hasHeavyLuggage = val;
                        if (!val) _luggagePhotos.clear();
                      });
                    },
                    onAddPhoto: _showPhotoSourceSheet,
                    onRemovePhoto: (index) {
                      setState(() {
                        _luggagePhotos.removeAt(index);
                      });
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _PriceSummary(
                    pricePerSeat: segment.pricePerSeat,
                    seatCount: widget.seatIds.length,
                  ),
                ],
              ),
            ),
          ),
          _ConfirmBar(
            total: segment.pricePerSeat * widget.seatIds.length,
            isLoading: _isConfirming,
            onConfirm: _confirm,
          ),
        ],
      ),
    );
  }
}

class _TripSummaryCard extends StatelessWidget {
  final Trip trip;
  final TripSegment segment;

  const _TripSummaryCard({required this.trip, required this.segment});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Montée', style: AppTextStyles.caption),
                Text(segment.boarding?.name ?? trip.departure, style: AppTextStyles.bodyLargeSemibold),
              ],
            ),
          ),
          Column(
            children: [
              const Icon(
                Icons.arrow_forward,
                color: AppColors.primary,
                size: 20,
              ),
              Text(trip.durationLabel, style: AppTextStyles.caption),
            ],
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Descente', style: AppTextStyles.caption),
                Text(
                  segment.alighting?.name ?? trip.arrival,
                  style: AppTextStyles.bodyLargeSemibold,
                  textAlign: TextAlign.end,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SeatSummary extends StatelessWidget {
  final List<String> seatIds;

  const _SeatSummary({required this.seatIds});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppColors.cardDecoration,
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Row(
          children: [
            const Icon(
              Icons.event_seat_outlined,
              color: AppColors.primary,
              size: 22,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                seatIds.length > 1
                    ? 'Places #${seatIds.join(', ')}'
                    : 'Place #${seatIds.first}',
                style: AppTextStyles.bodyLargeSemibold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PassengerSummary extends StatelessWidget {
  final String name;
  final String phone;

  const _PassengerSummary({required this.name, required this.phone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: AppColors.cardDecoration,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppColors.primarySurface,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                _initials(name),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: AppTextStyles.bodyLargeSemibold),
              Text(phone, style: AppTextStyles.caption),
            ],
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

class _PriceSummary extends StatelessWidget {
  final double pricePerSeat;
  final int seatCount;

  const _PriceSummary({required this.pricePerSeat, required this.seatCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: AppColors.cardDecoration,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total', style: AppTextStyles.bodyLargeSemibold),
              if (seatCount > 1)
                Text(
                  '$seatCount places × ${pricePerSeat.round()} FCFA',
                  style: AppTextStyles.caption,
                ),
            ],
          ),
          PriceDisplay(amount: pricePerSeat * seatCount, isLarge: true),
        ],
      ),
    );
  }
}

class _ConfirmBar extends StatelessWidget {
  final double total;
  final bool isLoading;
  final VoidCallback onConfirm;

  const _ConfirmBar({
    required this.total,
    required this.isLoading,
    required this.onConfirm,
  });

  /// Barre fixe du bas : total et envoi de la demande.
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
                    Text('Total', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700)),
                    Text(formatFcfa(total), style: AppTextStyles.priceLarge.copyWith(fontSize: 20)),
                  ],
                ),
              ),
              GlowButton(
                label: 'Envoyer la demande',
                expanded: false,
                isLoading: isLoading,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                onPressed: isLoading ? null : onConfirm,
              ),
            ],
          ),
    );
  }
}

class _LuggageSection extends StatelessWidget {
  final bool hasHeavyLuggage;
  final List<File> photos;
  final ValueChanged<bool> onToggle;
  final VoidCallback onAddPhoto;
  final ValueChanged<int> onRemovePhoto;

  const _LuggageSection({
    required this.hasHeavyLuggage,
    required this.photos,
    required this.onToggle,
    required this.onAddPhoto,
    required this.onRemovePhoto,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: AppColors.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: hasHeavyLuggage ? AppColors.primarySurface : AppColors.background,
                  borderRadius: BorderRadius.circular(AppSpacing.borderRadiusSm),
                ),
                child: Icon(
                  Icons.luggage_rounded,
                  size: 20,
                  color: hasHeavyLuggage ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bagages lourds ou volumineux ?', style: AppTextStyles.bodyLargeSemibold),
                    Text(
                      'Valises volumineuses, malles, cartons…',
                      style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _LuggageChoiceChip(
                  label: 'Non (Normal)',
                  icon: Icons.check_circle_outline_rounded,
                  isSelected: !hasHeavyLuggage,
                  onTap: () => onToggle(false),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _LuggageChoiceChip(
                  label: 'Oui (Lourds / Grand)',
                  icon: Icons.luggage_rounded,
                  isSelected: hasHeavyLuggage,
                  onTap: () => onToggle(true),
                ),
              ),
            ],
          ),
          if (hasHeavyLuggage) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.amberSurface,
                borderRadius: BorderRadius.circular(AppSpacing.borderRadiusSm),
                border: Border.all(color: AppColors.amber.withValues(alpha: 0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, color: AppColors.amber, size: 18),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Prenez une ou plusieurs photos de vos bagages pour informer le chauffeur et vous assurer qu\'il a la place nécessaire dans son coffre.',
                      style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 84,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  InkWell(
                    onTap: onAddPhoto,
                    borderRadius: BorderRadius.circular(AppSpacing.borderRadiusSm),
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: AppColors.primarySurface,
                        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusSm),
                        border: Border.all(color: AppColors.primary, width: 1.2),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_a_photo_rounded, color: AppColors.primary, size: 24),
                          const SizedBox(height: 4),
                          Text(
                            'Photo',
                            style: AppTextStyles.label.copyWith(color: AppColors.primary, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ...photos.asMap().entries.map((entry) {
                    final index = entry.key;
                    final file = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppSpacing.borderRadiusSm),
                            child: Image.file(
                              file,
                              width: 84,
                              height: 84,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: InkWell(
                              onTap: () => onRemovePhoto(index),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close, color: Colors.white, size: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            if (photos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${photos.length} photo(s) ajoutée(s)',
                  style: AppTextStyles.caption.copyWith(color: AppColors.success, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _LuggageChoiceChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _LuggageChoiceChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.borderRadiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primarySurface : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.borderRadiusSm),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: AppTextStyles.body.copyWith(
                  color: isSelected ? AppColors.primary : AppColors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
