import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
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

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Profil'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          child: Column(
            children: [
              _ProfileHeader(
                user: user,
                onEditPhoto: () => _pickAndUploadPhoto(context),
                onEditProfile: () => _editProfileModal(context, user),
              ),
              const SizedBox(height: AppSpacing.lg),
              _SettingsSection(
                title: 'Mon compte',
                items: [
                  _SettingsItem(
                    icon: Icons.person_outline,
                    label: 'Modifier mes informations',
                    value: user?.name,
                    onTap: () => _editProfileModal(context, user),
                  ),
                  _SettingsItem(
                    icon: Icons.confirmation_number_outlined,
                    label: 'Mes réservations',
                    onTap: () => context.push('/my-trips'),
                  ),
                  _SettingsItem(
                    icon: Icons.alt_route_outlined,
                    label: 'Mes demandes publiées',
                    onTap: () => context.push('/my-requests'),
                  ),
                  _SettingsItem(
                    icon: Icons.verified_user_outlined,
                    label: 'Vérification d\'identité',
                    value: user?.identityVerified == true
                        ? 'Vérifié'
                        : (user?.identityStatus == 'pending'
                            ? 'En vérification...'
                            : (user?.identityStatus == 'rejected' ? 'Refusé' : 'Non vérifié')),
                    onTap: () => context.push('/profile/identity'),
                  ),
                  _SettingsItem(
                    icon: Icons.notifications_outlined,
                    label: 'Notifications',
                    onTap: () => context.push('/notifications'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _SettingsSection(
                title: 'Préférences',
                items: [
                  _SettingsItem(
                    icon: Icons.language,
                    label: 'Langue',
                    value: _languageLabels[_languageCode] ?? 'Français',
                    onTap: () => _openLanguageScreen(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _SettingsSection(
                title: 'Aide et support',
                items: [
                  _SettingsItem(
                    icon: Icons.help_outline,
                    label: 'Aide et FAQ',
                    onTap: () => context.push('/support'),
                  ),
                  _SettingsItem(
                    icon: Icons.headset_mic_outlined,
                    label: 'Contacter le support',
                    onTap: () => context.push('/support'),
                  ),
                  _SettingsItem(
                    icon: Icons.description_outlined,
                    label: 'Conditions générales d\'utilisation',
                    onTap: () => context.push('/profile/terms'),
                  ),
                  _SettingsItem(
                    icon: Icons.privacy_tip_outlined,
                    label: 'Politique de confidentialité',
                    onTap: () => context.push('/profile/privacy'),
                  ),
                  _SettingsItem(
                    icon: Icons.star_outline,
                    label: 'Noter l\'application',
                    onTap: () => _rateApp(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: _LogoutButton(
                  onTap: () => _showLogoutDialog(context),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: Text(
                  'FOJËM v1.0.0',
                  style: AppTextStyles.caption,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
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

class _ProfileHeader extends StatelessWidget {
  final AppUser? user;
  final VoidCallback? onEditPhoto;
  final VoidCallback? onEditProfile;

  const _ProfileHeader({
    required this.user,
    this.onEditPhoto,
    this.onEditProfile,
  });

  String get _initials {
    final name = user?.name.trim() ?? '';
    if (name.isEmpty) return '?';
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = user?.photoUrl != null && user!.photoUrl!.isNotEmpty;

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          GestureDetector(
            onTap: onEditPhoto,
            child: Stack(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: AppColors.primarySurface,
                    shape: BoxShape.circle,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: hasPhoto
                      ? CachedNetworkImage(
                          imageUrl: user!.photoUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Center(
                            child: Text(
                              _initials,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            _initials,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.camera_alt, size: 13, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        user?.name.isNotEmpty == true ? user!.name : 'Utilisateur',
                        style: AppTextStyles.title2,
                      ),
                    ),
                    if (onEditProfile != null)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.primary),
                        tooltip: 'Modifier les informations',
                        onPressed: onEditProfile,
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  user?.phoneNumber ?? '',
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: user?.identityVerified == true
                            ? AppColors.successSurface
                            : (user?.identityStatus == 'pending'
                                ? AppColors.amber.withValues(alpha: 0.15)
                                : AppColors.background),
                        borderRadius:
                            BorderRadius.circular(AppSpacing.borderRadiusSm),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            user?.identityVerified == true
                                ? Icons.verified_rounded
                                : (user?.identityStatus == 'pending'
                                    ? Icons.hourglass_top_rounded
                                    : Icons.info_outline_rounded),
                            size: 13,
                            color: user?.identityVerified == true
                                ? AppColors.success
                                : (user?.identityStatus == 'pending'
                                    ? AppColors.amber
                                    : AppColors.textMuted),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            user?.identityVerified == true
                                ? 'Profil vérifié'
                                : (user?.identityStatus == 'pending'
                                    ? 'En vérification...'
                                    : 'Non vérifié'),
                            style: AppTextStyles.label.copyWith(
                              color: user?.identityVerified == true
                                  ? AppColors.success
                                  : (user?.identityStatus == 'pending'
                                      ? AppColors.amber
                                      : AppColors.textMuted),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<_SettingsItem> items;

  const _SettingsSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Text(
            title.toUpperCase(),
            style: AppTextStyles.label.copyWith(
              color: AppColors.textMuted,
              fontSize: 11,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Container(
          color: AppColors.surface,
          child: Column(
            children: items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isLast = index == items.length - 1;

              return Column(
                children: [
                  item,
                  if (!isLast)
                    const Divider(
                      height: 1,
                      color: AppColors.border,
                      indent: 52,
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;

  const _SettingsItem({
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 14,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(label, style: AppTextStyles.bodyLarge),
            ),
            if (value != null)
              Text(
                value!,
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            if (onTap != null) ...[
              const SizedBox(width: AppSpacing.sm),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.textMuted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  final VoidCallback onTap;

  const _LogoutButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.dangerSurface,
          borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
          border: Border.all(color: AppColors.danger.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.logout,
              size: 20,
              color: AppColors.danger,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Se déconnecter',
              style: AppTextStyles.bodyLargeSemibold.copyWith(
                color: AppColors.danger,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
