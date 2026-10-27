import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/driver_avatar.dart';
import '../../../core/widgets/star_rating.dart';
import '../../../core/widgets/fojem_button.dart';
import '../../../models/driver.dart';
import '../../../providers/app_provider.dart';
import '../../../services/review_repository.dart';
import '../../../services/trip_repository.dart';

class RatingScreen extends StatefulWidget {
  final String tripId;

  const RatingScreen({super.key, required this.tripId});

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  double _rating = 0;
  final _commentController = TextEditingController();
  bool _isSubmitting = false;
  bool _isLoading = true;

  Driver? _driver;
  String _routeLabel = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final trip = await TripRepository().fetch(widget.tripId);
    if (!mounted) return;
    setState(() {
      _driver = trip?.driver;
      _routeLabel = trip == null ? '' : '${trip.departure} → ${trip.arrival}';
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final driver = _driver;
    final user = context.read<AppProvider>().user;
    if (_rating == 0 || driver == null || user == null) return;

    setState(() => _isSubmitting = true);
    final comment = [
      _commentController.text.trim(),
      if (_selectedTags.isNotEmpty) _selectedTags.join(', '),
    ].where((s) => s.isNotEmpty).join(' — ');

    try {
      await ReviewRepository().submitReview(
        tripId: widget.tripId,
        driverId: driver.id,
        authorId: user.id,
        authorName: user.name.isEmpty ? user.phoneNumber : user.name,
        rating: _rating,
        comment: comment,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      final message = e is ApiException
          ? e.message
          : e is StateError
              ? e.message
              : 'Impossible d\'envoyer votre note. Réessayez.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);
    context.go('/home');
  }

  static const _quickTags = [
    'Conduite douce',
    'Très ponctuel',
    'Véhicule propre',
    'Sympathique',
    'Trajet sécurisé',
    'Bonne climatisation',
  ];

  final Set<String> _selectedTags = {};

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    final driver = _driver;
    if (driver == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Évaluer le trajet')),
        body: const Center(child: Text('Trajet introuvable')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Évaluer le trajet'),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Comment était votre trajet ?',
                    style: AppTextStyles.title1,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '$_routeLabel · ${driver.name}',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  DriverAvatar(
                    name: driver.name,
                    photoUrl: driver.photoUrl,
                    isOnline: false,
                    size: 80,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(driver.name, style: AppTextStyles.title2),
                  Text(
                    driver.vehicle.model,
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  InteractiveStarRating(
                    onRatingChanged: (r) => setState(() => _rating = r),
                    size: 48,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _ratingLabel,
                    style: AppTextStyles.bodyLargeSemibold.copyWith(
                      color: _rating > 0 ? AppColors.accent : AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    alignment: WrapAlignment.center,
                    children: _quickTags.map((tag) {
                      final isSelected = _selectedTags.contains(tag);
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedTags.remove(tag);
                            } else {
                              _selectedTags.add(tag);
                            }
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primarySurface
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected ? AppColors.primary : AppColors.border,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Text(
                            tag,
                            style: AppTextStyles.body.copyWith(
                              color: isSelected ? AppColors.primary : AppColors.textPrimary,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _CommentField(controller: _commentController),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                FojemButton.primary(
                  label: 'Envoyer l\'évaluation',
                  onPressed:
                      _rating > 0 && !_isSubmitting ? _submit : null,
                  isLoading: _isSubmitting,
                ),
                const SizedBox(height: AppSpacing.sm),
                FojemButton.ghost(
                  label: 'Ignorer',
                  onPressed: () => context.go('/home'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _ratingLabel {
    if (_rating == 0) return 'Appuyez pour noter';
    if (_rating == 1) return 'Très mauvais';
    if (_rating == 2) return 'Mauvais';
    if (_rating == 3) return 'Correct';
    if (_rating == 4) return 'Bien';
    return 'Excellent !';
  }
}

class _CommentField extends StatelessWidget {
  final TextEditingController controller;

  const _CommentField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: controller,
        maxLines: 4,
        maxLength: 200,
        style: AppTextStyles.body,
        decoration: InputDecoration(
          hintText:
              'Un commentaire sur ce trajet ? (optionnel)',
          hintStyle: AppTextStyles.body.copyWith(color: AppColors.textMuted),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: AppSpacing.cardPadding,
          counterStyle: AppTextStyles.caption,
        ),
      ),
    );
  }
}
