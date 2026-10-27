import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/bottom_nav_bar.dart';
import '../../../core/widgets/image_source_sheet.dart';
import '../../../models/app_user.dart';
import '../../../providers/app_provider.dart';
import '../../../services/profile_repository.dart';
import '../../../core/utils/language_preference.dart';
import '../../../core/utils/external_links.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  String _languageLabel = LanguagePreference.labelFor(LanguagePreference.defaultCode);
  bool _isUploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final code = await LanguagePreference.load();
    if (!mounted) return;
    setState(() => _languageLabel = LanguagePreference.labelFor(code));
  }

  Future<void> _openLanguage(BuildContext context) async {
    await context.push('/profile/language');
    _loadLanguage();
  }

  /// Photo de profil : choix caméra/galerie, `POST /profile/photo`, puis
  /// relecture du profil complet (`refreshUser`) pour afficher la nouvelle
  /// `profile_photo_url`.
  Future<void> _changePhoto() async {
    if (_isUploadingPhoto) return;
    final picked = await pickImageWithSourceSheet(
      context,
      title: 'Photo de profil',
      maxDimension: 1024,
    );
    if (picked == null || !mounted) return;

    setState(() => _isUploadingPhoto = true);
    try {
      await ProfileRepository().uploadPhoto(bytes: picked.bytes, filename: picked.filename);
      if (!mounted) return;
      await context.read<AppProvider>().refreshUser();
      if (!mounted) return;
      setState(() => _isUploadingPhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo de profil mise à jour.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingPhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException
              ? e.message
              : 'Échec de l’envoi de la photo. Réessayez.'),
        ),
      );
    }
  }

  Future<void> _editName(String currentName) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _EditNameDialog(initialName: currentName),
    );
    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nom mis à jour.')),
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
                isUploadingPhoto: _isUploadingPhoto,
                onPhotoTap: _changePhoto,
                onEditName: () => _editName(user?.name ?? ''),
              ),
              const SizedBox(height: AppSpacing.lg),
              _SettingsSection(
                title: 'Mon compte',
                items: [
                  _SettingsItem(
                    icon: Icons.directions_car_filled_outlined,
                    label: 'Mon véhicule',
                    onTap: () => context.push('/driver/vehicle'),
                  ),
                  _SettingsItem(
                    icon: Icons.verified_user_outlined,
                    label: 'Vérification d\'identité',
                    value: user?.isApprovedDriver == true
                        ? 'Vérifié'
                        : 'Non vérifié',
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
                    value: _languageLabel,
                    onTap: () => _openLanguage(context),
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
                    icon: Icons.star_outline_rounded,
                    label: 'Noter l\'application',
                    onTap: () => ExternalLinks.rateApp(context),
                  ),
                  _SettingsItem(
                    icon: Icons.headset_mic_outlined,
                    label: 'Contacter le support',
                    onTap: () => context.push('/support'),
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
                  'FOJËM Chauffeur v1.0.0',
                  style: AppTextStyles.caption,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const DriverBottomNavBar(current: DriverTab.profile),
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
  final bool isUploadingPhoto;
  final VoidCallback onPhotoTap;
  final VoidCallback onEditName;

  const _ProfileHeader({
    required this.user,
    required this.isUploadingPhoto,
    required this.onPhotoTap,
    required this.onEditName,
  });

  String get _initials {
    final name = user?.name.trim() ?? '';
    if (name.isEmpty) return '?';
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  Widget _buildInitials() {
    return Center(
      child: Text(
        _initials,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = user?.photoUrl;
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Changer la photo de profil',
            child: GestureDetector(
              onTap: isUploadingPhoto ? null : onPhotoTap,
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
                        ? Image.network(
                            photoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildInitials(),
                          )
                        : _buildInitials(),
                  ),
                  if (isUploadingPhoto)
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.photo_camera, size: 12, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: onEditName,
                  borderRadius: BorderRadius.circular(AppSpacing.borderRadiusSm),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          user?.name.isNotEmpty == true ? user!.name : 'Utilisateur',
                          style: AppTextStyles.title2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.edit_outlined,
                          size: 16, color: AppColors.textSecondary,
                          semanticLabel: 'Modifier le nom'),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(user?.phoneNumber ?? '',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textSecondary,
                    )),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: user?.isApprovedDriver == true
                            ? AppColors.successSurface
                            : AppColors.background,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.borderRadiusSm),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            user?.isApprovedDriver == true
                                ? Icons.verified_rounded
                                : Icons.info_outline_rounded,
                            size: 13,
                            color: user?.isApprovedDriver == true
                                ? AppColors.success
                                : AppColors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            user?.isApprovedDriver == true
                                ? 'Profil vérifié'
                                : 'Non vérifié',
                            style: AppTextStyles.label.copyWith(
                              color: user?.isApprovedDriver == true
                                  ? AppColors.success
                                  : AppColors.textMuted,
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

/// Modification du nom complet (`PATCH /profile`). Le téléphone reste en
/// lecture seule : il n'est pas modifiable depuis l'app. Renvoie `true` via
/// `Navigator.pop` si l'enregistrement a réussi.
class _EditNameDialog extends StatefulWidget {
  final String initialName;

  const _EditNameDialog({required this.initialName});

  @override
  State<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<_EditNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);
  bool _isSaving = false;
  String? _error;

  String get _value => _controller.text.trim().replaceAll(RegExp(r'\s+'), ' ');

  bool get _canSave =>
      !_isSaving && _value.length >= 2 && _value != widget.initialName.trim();

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await ProfileRepository().updateFullName(_value);
      if (!mounted) return;
      await context.read<AppProvider>().refreshUser();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = e is ApiException
            ? (e.fieldErrors?['full_name']?.first ?? e.message)
            : 'Échec de l’enregistrement. Réessayez.';
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
      ),
      title: Text('Modifier mon nom', style: AppTextStyles.title2),
      content: TextField(
        controller: _controller,
        autofocus: true,
        enabled: !_isSaving,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        maxLength: 255,
        onChanged: (_) => setState(() => _error = null),
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(
          labelText: 'Nom complet',
          hintText: 'Prénom et nom',
          counterText: '',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: _canSave ? _save : null,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  'Enregistrer',
                  style: AppTextStyles.bodySemibold.copyWith(
                    color: _canSave ? AppColors.primary : AppColors.textMuted,
                  ),
                ),
        ),
      ],
    );
  }
}
