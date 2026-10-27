import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import 'package:intl/intl.dart';
import '../../../core/widgets/glow.dart';
import '../../../core/widgets/profile_kit.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/bottom_nav_bar.dart';
import '../../../core/widgets/fojem_button.dart';
import '../../../core/widgets/fojem_text_field.dart';
import '../../../core/services/language_preference.dart';
import '../../../models/app_user.dart';
import '../../../providers/app_provider.dart';
import '../../../services/profile_repository.dart';

/// Fiche Play Store de l'app — à activer une fois l'app publiée.
const _playStoreUrl =
    'https://play.google.com/store/apps/details?id=com.example.niou_dem';

const _languageLabels = {
  'fr': 'Français',
  'wo': 'Wolof',
  'en': 'English',
};

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  String _languageCode = LanguagePreference.defaultCode;

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final code = await LanguagePreference.getLanguageCode();
    if (mounted) setState(() => _languageCode = code);
  }

  Future<void> _openLanguageScreen(BuildContext context) async {
    await context.push('/profile/language');
    _loadLanguage();
  }

  Future<void> _pickAndUploadPhoto(BuildContext context) async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera, color: AppColors.primary),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.primary),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      final file = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (file == null || !context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Envoi de la photo en cours...')),
      );

      final updated = await ProfileRepository().updatePhoto(file.path);
      if (!context.mounted) return;
      context.read<AppProvider>().updateUser(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo de profil mise à jour !'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Échec de la mise à jour de la photo.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _editProfileModal(BuildContext context, AppUser? user) async {
    if (user == null) return;

    final nameController = TextEditingController(text: user.name);
    String rawPhone = user.phoneNumber;
    if (rawPhone.startsWith('+221')) {
      rawPhone = rawPhone.substring(4);
    }
    final phoneController = TextEditingController(text: rawPhone);
    bool isLoading = false;
    String? errorText;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.lg,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Modifier mon profil', style: AppTextStyles.title2),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Nom complet', style: AppTextStyles.bodySemibold),
              const SizedBox(height: AppSpacing.xs),
              FojemTextField(
                controller: nameController,
                hint: 'Votre nom complet',
                prefixIcon: Icons.person_outline,
                borderRadius: 8,
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Numéro de téléphone', style: AppTextStyles.bodySemibold),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🇸🇳 ', style: TextStyle(fontSize: 16)),
                        Text('+221', style: AppTextStyles.bodyLargeSemibold),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FojemTextField(
                      controller: phoneController,
                      hint: '77 123 45 67',
                      prefixIcon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      borderRadius: 8,
                    ),
                  ),
                ],
              ),
              if (errorText != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(errorText!, style: AppTextStyles.caption.copyWith(color: AppColors.danger)),
              ],
              const SizedBox(height: AppSpacing.xl),
              FojemButton.primary(
                label: 'Enregistrer',
                isLoading: isLoading,
                onPressed: isLoading
                    ? null
                    : () async {
                        final newName = nameController.text.trim();
                        final cleanPhone = phoneController.text.replaceAll(' ', '');
                        if (newName.isEmpty) {
                          setModalState(() => errorText = 'Le nom ne peut pas être vide.');
                          return;
                        }
                        if (cleanPhone.length < 9) {
                          setModalState(() => errorText = 'Numéro de téléphone invalide.');
                          return;
                        }

                        setModalState(() {
                          isLoading = true;
                          errorText = null;
                        });

                        final fullPhone = cleanPhone.startsWith('+') ? cleanPhone : '+221$cleanPhone';

                        try {
                          final updated = await ProfileRepository().updateProfile(
                            fullName: newName,
                            phoneNumber: fullPhone,
                          );
                          if (!context.mounted) return;
                          context.read<AppProvider>().updateUser(updated);
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Profil mis à jour avec succès.'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        } catch (e) {
                          setModalState(() {
                            isLoading = false;
                            errorText = 'Erreur lors de la mise à jour : $e';
                          });
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _rateApp(BuildContext context) async {
    final uri = Uri.parse(_playStoreUrl);
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) throw Exception('launch failed');
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bientôt disponible sur le Play Store'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppProvider>().user;
    final identity = user?.identityVerified == true
        ? 'Vérifié'
        : (user?.identityStatus == 'pending'
            ? 'En vérification'
            : (user?.identityStatus == 'rejected' ? 'Refusé' : 'Non vérifié'));
    final identityColor = user?.identityVerified == true
        ? AppColors.success
        : (user?.identityStatus == 'rejected' ? AppColors.danger : AppColors.amber);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: BrandHeaderLayout(
        overlap: 72,
        header: BrandHeader(
          title: 'Profil',
          overlap: 96,
          trailing: GlassIconButton(
            icon: Icons.settings_outlined,
            tooltip: 'Modifier mes informations',
            onPressed: () => _editProfileModal(context, user),
          ),
        ),
        children: [
          RiseIn(
            child: ProfileHeroCard(
              name: user?.name ?? 'Voyageur',
              subtitle: user == null
                  ? null
                  : 'Membre depuis ${DateFormat('MMMM yyyy', 'fr_FR').format(user.createdAt)}',
              photoUrl: user?.photoUrl,
              onEditPhoto: () => _pickAndUploadPhoto(context),
              stats: [
                ProfileStat(
                  icon: Icons.star_rounded,
                  color: AppColors.accent,
                  value: (user?.ratingCount ?? 0) > 0
                      ? user!.rating.toStringAsFixed(1).replaceAll('.', ',')
                      : '–',
                  label: 'Note',
                ),
                ProfileStat(
                  icon: Icons.directions_car_rounded,
                  color: AppColors.primary,
                  value: '${user?.totalTrips ?? 0}',
                  label: 'Trajets',
                ),
              ],
              infos: [
                ProfileInfo(
                  icon: Icons.verified_user_rounded,
                  color: identityColor,
                  label: 'Identité',
                  value: identity,
                ),
                ProfileInfo(
                  icon: Icons.phone_rounded,
                  color: AppColors.primaryGlow,
                  label: 'Téléphone',
                  value: (user?.phoneNumber.isNotEmpty ?? false) ? user!.phoneNumber : '–',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          RiseIn(
            delay: const Duration(milliseconds: 80),
            child: ProfileMenuCard(
              title: 'Mon compte',
              items: [
                ProfileMenuItem(
                  icon: Icons.person_rounded,
                  title: 'Informations personnelles',
                  subtitle: 'Nom, téléphone, e-mail',
                  onTap: () => _editProfileModal(context, user),
                ),
                ProfileMenuItem(
                  icon: Icons.alt_route_rounded,
                  color: AppColors.accent,
                  title: 'Mes demandes publiées',
                  subtitle: 'Trajets que vous recherchez',
                  onTap: () => context.push('/my-requests'),
                ),
                ProfileMenuItem(
                  icon: Icons.verified_user_rounded,
                  color: identityColor,
                  title: 'Vérification d\'identité',
                  subtitle: identity,
                  onTap: () => context.push('/profile/identity'),
                ),
                ProfileMenuItem(
                  icon: Icons.notifications_rounded,
                  color: AppColors.amber,
                  title: 'Notifications',
                  subtitle: 'Alertes de trajets et messages',
                  onTap: () => context.push('/notifications'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          RiseIn(
            delay: const Duration(milliseconds: 160),
            child: ProfileMenuCard(
              title: 'Préférences',
              items: [
                ProfileMenuItem(
                  icon: Icons.language_rounded,
                  color: AppColors.primaryGlow,
                  title: 'Langue',
                  subtitle: _languageLabels[_languageCode] ?? 'Français',
                  onTap: () => _openLanguageScreen(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          RiseIn(
            delay: const Duration(milliseconds: 240),
            child: ProfileMenuCard(
              title: 'Aide et support',
              items: [
                ProfileMenuItem(
                  icon: Icons.help_rounded,
                  title: 'Aide et FAQ',
                  subtitle: 'Réponses aux questions fréquentes',
                  onTap: () => context.push('/support'),
                ),
                ProfileMenuItem(
                  icon: Icons.headset_mic_rounded,
                  color: AppColors.primaryGlow,
                  title: 'Contacter le support',
                  subtitle: 'Nous sommes là pour vous aider',
                  onTap: () => context.push('/support'),
                ),
                ProfileMenuItem(
                  icon: Icons.description_rounded,
                  color: AppColors.textSecondary,
                  title: 'Conditions d\'utilisation',
                  onTap: () => context.push('/profile/terms'),
                ),
                ProfileMenuItem(
                  icon: Icons.privacy_tip_rounded,
                  color: AppColors.textSecondary,
                  title: 'Confidentialité',
                  onTap: () => context.push('/profile/privacy'),
                ),
                ProfileMenuItem(
                  icon: Icons.star_rounded,
                  color: AppColors.accent,
                  title: 'Noter l\'application',
                  subtitle: 'Votre avis nous fait avancer',
                  onTap: () => _rateApp(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          ProfileLogoutButton(onTap: () => _showLogoutDialog(context)),
          const SizedBox(height: 16),
          Center(child: Text('FOJËM v1.0.0', style: AppTextStyles.caption)),
        ],
      ),
      bottomNavigationBar: const TravelerBottomNavBar(current: ClientTab.profile),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
        ),
        title: Text('Se déconnecter ?', style: AppTextStyles.title2),
        content: Text(
          'Vous devrez vous reconnecter pour accéder à votre compte.',
          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<AppProvider>().signOut();
              if (context.mounted) context.go('/role-selection');
            },
            child: Text(
              'Se déconnecter',
              style: AppTextStyles.bodySemibold.copyWith(
                color: AppColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

