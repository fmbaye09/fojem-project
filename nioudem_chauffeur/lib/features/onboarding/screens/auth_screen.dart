import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/fojem_button.dart';
import '../../../core/widgets/fojem_logo.dart';
import '../../../core/widgets/fojem_text_field.dart';
import '../../../providers/app_provider.dart';

enum _AuthCard { login, register }

/// Carte blanche centralisée qui porte les champs de chaque état — fidèle à
/// la maquette (bordure + ombre légère, coins bien arrondis), pas un simple
/// empilement de champs à même le fond de l'écran.
final BoxDecoration _authCardDecoration = AppColors.cardDecoration.copyWith(
  borderRadius: BorderRadius.zero,
  border: Border.all(color: AppColors.border),
);

/// Écran d'authentification email/mot de passe contre l'API Laravel — la
/// carte Connexion appelle `AppProvider.login`, la carte Inscription appelle
/// `AppProvider.register` (qui crée le compte puis le profil chauffeur via
/// `/auth/become-driver` automatiquement, cette app étant réservée aux
/// chauffeurs).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  _AuthCard _card = _AuthCard.login;

  void _switchTo(_AuthCard card) => setState(() => _card = card);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _card == _AuthCard.login,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _card != _AuthCard.login) _switchTo(_AuthCard.login);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.sm),
                const _AuthHeader(),
                const SizedBox(height: AppSpacing.xl),
                Text('FOJËM Chauffeur', style: AppTextStyles.display, textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Publiez vos trajets et gérez vos passagers.',
                  style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xl),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: _authCardDecoration,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.04),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: switch (_card) {
                        _AuthCard.login => const _LoginCard(key: ValueKey('login')),
                        _AuthCard.register => const _RegisterCard(key: ValueKey('register')),
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.lg),
                  child: _card == _AuthCard.login
                      ? _LoginFootnote(onRegister: () => _switchTo(_AuthCard.register))
                      : _RegisterFootnote(onLogin: () => _switchTo(_AuthCard.login)),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginCard extends StatefulWidget {
  const _LoginCard({super.key});

  @override
  State<_LoginCard> createState() => _LoginCardState();
}

class _LoginCardState extends State<_LoginCard> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _emailController.text.trim().contains('@') && _passwordController.text.isNotEmpty;

  Future<void> _submit() async {
    if (!_isValid || _isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final ok = await context.read<AppProvider>().login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (ok) {
      context.go('/home');
    } else {
      setState(() => _error = context.read<AppProvider>().lastError ?? 'Connexion impossible.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Adresse e-mail', style: AppTextStyles.bodyLargeSemibold),
        const SizedBox(height: AppSpacing.sm),
        FojemTextField(
          controller: _emailController,
          hint: 'vous@exemple.com',
          prefixIcon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          borderRadius: 0,
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Mot de passe', style: AppTextStyles.bodyLargeSemibold),
        const SizedBox(height: AppSpacing.sm),
        FojemTextField(
          controller: _passwordController,
          hint: 'Votre mot de passe',
          prefixIcon: Icons.lock_outline,
          obscureText: true,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onFieldSubmitted: (_) => _submit(),
          borderRadius: 0,
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const Icon(Icons.error_outline, size: 16, color: AppColors.danger),
              const SizedBox(width: 6),
              Expanded(
                child: Text(_error!, style: AppTextStyles.caption.copyWith(color: AppColors.danger)),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        FojemButton.primary(
          label: 'Se connecter',
          suffixIcon: Icons.arrow_forward,
          isLoading: _isLoading,
          onPressed: _isValid && !_isLoading ? _submit : null,
        ),
      ],
    );
  }
}

/// Bloc logo affiché en tête de l'écran d'auth.
class _AuthHeader extends StatelessWidget {
  const _AuthHeader();

  @override
  Widget build(BuildContext context) {
    return const Center(child: FojemLogo(width: 180));
  }
}

class _LoginFootnote extends StatelessWidget {
  final VoidCallback onRegister;

  const _LoginFootnote({required this.onRegister});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        children: [
          Text(
            'Nouveau sur FOJËM ? ',
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          GestureDetector(
            onTap: onRegister,
            child: Text(
              'Créer un compte',
              style: AppTextStyles.bodySemibold.copyWith(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegisterFootnote extends StatelessWidget {
  final VoidCallback onLogin;

  const _RegisterFootnote({required this.onLogin});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        children: [
          Text(
            'Déjà un compte ? ',
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          GestureDetector(
            onTap: onLogin,
            child: Text(
              'Se connecter',
              style: AppTextStyles.bodySemibold.copyWith(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegisterCard extends StatefulWidget {
  const _RegisterCard({super.key});

  @override
  State<_RegisterCard> createState() => _RegisterCardState();
}

enum _Gender { male, female }

class _RegisterCardState extends State<_RegisterCard> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  _Gender _gender = _Gender.male;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _isPhoneValid {
    final cleaned = _phoneController.text.replaceAll(' ', '');
    return cleaned.length >= 9 && cleaned.length <= 12;
  }

  bool get _isFormValid =>
      _nameController.text.trim().isNotEmpty &&
      _emailController.text.trim().contains('@') &&
      _isPhoneValid &&
      _passwordController.text.length >= 8 &&
      _confirmController.text == _passwordController.text;

  Future<void> _submit() async {
    if (!_isFormValid || _isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final localNumber = _phoneController.text.replaceAll(' ', '');
    final ok = await context.read<AppProvider>().register(
          fullName: _nameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
          phoneNumber: '+221$localNumber',
          gender: _gender == _Gender.male ? 'male' : 'female',
        );
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (ok) {
      context.go('/home');
    } else {
      setState(() => _error = context.read<AppProvider>().lastError ?? 'Inscription impossible.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Nom complet', style: AppTextStyles.bodyLargeSemibold),
        const SizedBox(height: AppSpacing.sm),
        FojemTextField(
          controller: _nameController,
          hint: 'Awa Ndiaye',
          prefixIcon: Icons.person_outline,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          borderRadius: 0,
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Adresse e-mail', style: AppTextStyles.bodyLargeSemibold),
        const SizedBox(height: AppSpacing.sm),
        FojemTextField(
          controller: _emailController,
          hint: 'vous@exemple.com',
          prefixIcon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          borderRadius: 0,
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Numéro de téléphone', style: AppTextStyles.bodyLargeSemibold),
        const SizedBox(height: AppSpacing.sm),
        _PhoneField(
          controller: _phoneController,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Genre', style: AppTextStyles.bodyLargeSemibold),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _GenderChip(
                label: 'Homme',
                selected: _gender == _Gender.male,
                onTap: () => setState(() => _gender = _Gender.male),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _GenderChip(
                label: 'Femme',
                selected: _gender == _Gender.female,
                onTap: () => setState(() => _gender = _Gender.female),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Mot de passe', style: AppTextStyles.bodyLargeSemibold),
        const SizedBox(height: AppSpacing.sm),
        FojemTextField(
          controller: _passwordController,
          hint: '8 caractères minimum',
          prefixIcon: Icons.lock_outline,
          obscureText: true,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          borderRadius: 0,
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Confirmer le mot de passe', style: AppTextStyles.bodyLargeSemibold),
        const SizedBox(height: AppSpacing.sm),
        FojemTextField(
          controller: _confirmController,
          hint: 'Répétez votre mot de passe',
          prefixIcon: Icons.lock_outline,
          obscureText: true,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onFieldSubmitted: (_) {
            if (_isFormValid) _submit();
          },
          borderRadius: 0,
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const Icon(Icons.error_outline, size: 16, color: AppColors.danger),
              const SizedBox(width: 6),
              Expanded(
                child: Text(_error!, style: AppTextStyles.caption.copyWith(color: AppColors.danger)),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        FojemButton.primary(
          label: 'Créer mon compte',
          suffixIcon: Icons.arrow_forward,
          isLoading: _isLoading,
          onPressed: _isLoading || !_isFormValid ? null : _submit,
        ),
      ],
    );
  }
}

class _GenderChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GenderChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySurface : AppColors.surface,
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodySemibold.copyWith(
            color: selected ? AppColors.primary : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _PhoneField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  const _PhoneField({required this.controller, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.call_outlined, size: 18, color: AppColors.textSecondary),
                SizedBox(width: 6),
                Text('+221', style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              onChanged: onChanged,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              style: AppTextStyles.bodyLarge,
              decoration: const InputDecoration(
                hintText: '77 000 00 00',
                hintStyle: TextStyle(color: AppColors.textMuted),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.md,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
