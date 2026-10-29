import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glow.dart';
import '../../../core/widgets/profile_kit.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/bottom_nav_bar.dart';
import '../../../core/widgets/image_source_sheet.dart';
import '../../../providers/app_provider.dart';
import '../../../services/driver_document_repository.dart';
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

  Future<void> _editEmergencyContact() async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => const _EmergencyContactDialog(),
    );
    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contact d’urgence enregistré.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppProvider>().user;
    final (status, statusColor) = user == null
        ? ('–', AppColors.textMuted)
        : user.isApprovedDriver
            ? ('Approuvé', AppColors.success)
            : user.isRejectedDriver
                ? ('Refusé', AppColors.danger)
                : user.isPendingReview
                    ? ('En validation', AppColors.amber)
                    : ('Dossier incomplet', AppColors.amber);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: BrandHeaderLayout(
        overlap: 72,
        header: BrandHeader(
          title: 'Profil',
          overlap: 96,
          trailing: GlassIconButton(
            icon: Icons.settings_outlined,
            tooltip: 'Modifier mon nom',
            onPressed: () => _editName(user?.name ?? ''),
          ),
        ),
        children: [
          RiseIn(
            child: ProfileHeroCard(
              name: user?.name ?? 'Chauffeur',
              subtitle: user == null
                  ? null
                  : (user.phoneNumber.isNotEmpty ? user.phoneNumber : user.email),
              photoUrl: user?.photoUrl,
              isUploadingPhoto: _isUploadingPhoto,
              onEditPhoto: _changePhoto,
              stats: [
                ProfileStat(
                  icon: Icons.star_rounded,
                  color: AppColors.accent,
                  value: (user?.rating ?? 0) > 0
                      ? user!.rating.toStringAsFixed(1).replaceAll('.', ',')
                      : '–',
                  label: 'Note',
                ),
                ProfileStat(
                  icon: Icons.route_rounded,
                  color: AppColors.primary,
                  value: '${user?.totalTrips ?? 0}',
                  label: 'Trajets',
                ),
              ],
              infos: [
                ProfileInfo(
                  icon: Icons.verified_user_rounded,
                  color: statusColor,
                  label: 'Statut',
                  value: status,
                ),
                ProfileInfo(
                  icon: Icons.workspace_premium_rounded,
                  color: AppColors.accent,
                  label: 'Rôle',
                  value: 'Chauffeur',
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
                  subtitle: 'Nom affiché aux passagers',
                  onTap: () => _editName(user?.name ?? ''),
                ),
                ProfileMenuItem(
                  icon: Icons.directions_car_filled_rounded,
                  color: AppColors.primaryGlow,
                  title: 'Mon véhicule',
                  subtitle: 'Modèle, immatriculation, places',
                  onTap: () => context.push('/driver/vehicle'),
                ),
                ProfileMenuItem(
                  icon: Icons.verified_user_rounded,
                  color: statusColor,
                  title: 'Vérification d\'identité',
                  subtitle: status,
                  onTap: () => context.push('/profile/identity'),
                ),
                ProfileMenuItem(
                  icon: Icons.contact_emergency_rounded,
                  color: AppColors.danger,
                  title: 'Contact d’urgence',
                  subtitle: 'Prévenu en cas de problème',
                  onTap: _editEmergencyContact,
                ),
                ProfileMenuItem(
                  icon: Icons.notifications_rounded,
                  color: AppColors.amber,
                  title: 'Notifications',
                  subtitle: 'Réservations et messages',
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
                  subtitle: _languageLabel,
                  onTap: () => _openLanguage(context),
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
                  onTap: () => ExternalLinks.rateApp(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          ProfileLogoutButton(onTap: () => _showLogoutDialog(context)),
          const SizedBox(height: 16),
          Center(child: Text('FOJËM Pro v1.0.0', style: AppTextStyles.caption)),
        ],
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

/// Contact d'urgence (nom + téléphone) : chargé puis modifié via l'API.
class _EmergencyContactDialog extends StatefulWidget {
  const _EmergencyContactDialog();

  @override
  State<_EmergencyContactDialog> createState() => _EmergencyContactDialogState();
}

class _EmergencyContactDialogState extends State<_EmergencyContactDialog> {
  final _repository = DriverDocumentRepository();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  bool get _canSave =>
      !_isSaving &&
      !_isLoading &&
      _name.text.trim().length >= 2 &&
      _phone.text.replaceAll(RegExp(r'\D'), '').length >= 9;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final contact = (await _repository.fetch()).emergencyContact;
      _name.text = contact?.name ?? '';
      _phone.text = contact?.phone ?? '';
    } catch (_) {
      // Champs vides : le chauffeur peut quand même saisir un contact.
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await _repository.updateEmergencyContact(name: _name.text.trim(), phone: _phone.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = e is ApiException ? e.message : 'Échec de l’enregistrement. Réessayez.';
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
      ),
      title: Text('Contact d’urgence', style: AppTextStyles.title2),
      content: _isLoading
          ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Un proche à prévenir en cas de problème pendant un trajet. Visible uniquement par l’équipe FOJËM.',
                  style: AppTextStyles.caption,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _name,
                  enabled: !_isSaving,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() => _error = null),
                  decoration: const InputDecoration(labelText: 'Nom du contact'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _phone,
                  enabled: !_isSaving,
                  keyboardType: TextInputType.phone,
                  onChanged: (_) => setState(() => _error = null),
                  decoration: InputDecoration(labelText: 'Téléphone', errorText: _error),
                ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: _canSave ? _save : null,
          child: _isSaving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
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
