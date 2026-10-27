import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/network/api_exception.dart';
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

/// Écran d'authentification — email + mot de passe contre le backend
/// Laravel (`POST /api/auth/login` / `POST /api/auth/register`), plus
/// aucune auth téléphone/OTP Firebase.
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
                Text('Bienvenue chez FOJËM', style: AppTextStyles.display, textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Trouvez ou proposez un trajet entre villes.',
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
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: _card == _AuthCard.login
                      ? Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.lg),
                          child: _LoginFootnote(onRegister: () => _switchTo(_AuthCard.register)),
                        )
                      : Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.lg),
                          child: _RegisterFootnote(onLogin: () => _switchTo(_AuthCard.login)),
                        ),
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

enum _LoginMode { email, phone }

class _LoginCard extends StatefulWidget {
  const _LoginCard({super.key});

  @override
  State<_LoginCard> createState() => _LoginCardState();
}

class _LoginCardState extends State<_LoginCard> {
  static final _emailRegex = RegExp(
    r'^[a-zA-Z0-9.!#$%&’*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+$',
  );

  _LoginMode _mode = _LoginMode.email;
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _isEmailValid => _emailRegex.hasMatch(_emailController.text.trim());

  bool get _isPhoneValid {
    final cleaned = _phoneController.text.replaceAll(' ', '');
    return cleaned.length >= 9 && cleaned.length <= 12;
  }

  bool get _isValid {
    if (_passwordController.text.isEmpty) return false;
    return _mode == _LoginMode.email ? _isEmailValid : _isPhoneValid;
  }

  Future<void> _submit() async {
    if (!_isValid) {
      if (_mode == _LoginMode.email && !_isEmailValid) {
        setState(() => _errorMessage = 'Format d\'e-mail invalide (ex: vous@exemple.com).');
      } else if (_mode == _LoginMode.phone && !_isPhoneValid) {
        setState(() => _errorMessage = 'Numéro de téléphone invalide (9 chiffres min.).');
      } else {
        setState(() => _errorMessage = 'Veuillez saisir votre mot de passe.');
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_mode == _LoginMode.email) {
        await context.read<AppProvider>().login(
              email: _emailController.text.trim(),
              password: _passwordController.text,
            );
      } else {
        final localNumber = _phoneController.text.replaceAll(' ', '');
        final fullPhone = localNumber.startsWith('+') ? localNumber : '+221$localNumber';
        await context.read<AppProvider>().login(
              phoneNumber: fullPhone,
              password: _passwordController.text,
            );
      }

      if (!mounted) return;
      context.go('/home');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Connexion impossible. Réessayez.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Sélecteur E-mail / Téléphone
        Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _mode = _LoginMode.email;
                    _errorMessage = null;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _mode == _LoginMode.email ? AppColors.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: _mode == _LoginMode.email
                          ? [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      'Par E-mail',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySemibold.copyWith(
                        color: _mode == _LoginMode.email ? AppColors.textPrimary : AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _mode = _LoginMode.phone;
                    _errorMessage = null;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _mode == _LoginMode.phone ? AppColors.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: _mode == _LoginMode.phone
                          ? [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      'Par Téléphone',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySemibold.copyWith(
                        color: _mode == _LoginMode.phone ? AppColors.textPrimary : AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_mode == _LoginMode.email) ...[
          Text('E-mail', style: AppTextStyles.bodyLargeSemibold),
          const SizedBox(height: AppSpacing.sm),
          FojemTextField(
            controller: _emailController,
            hint: 'vous@exemple.com',
            prefixIcon: Icons.mail_outline,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() => _errorMessage = null),
            borderRadius: 0,
          ),
        ] else ...[
          Text('Numéro de téléphone', style: AppTextStyles.bodyLargeSemibold),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.background,
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
                  controller: _phoneController,
                  hint: '77 123 45 67',
                  prefixIcon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() => _errorMessage = null),
                  borderRadius: 0,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Text('Mot de passe', style: AppTextStyles.bodyLargeSemibold),
        const SizedBox(height: AppSpacing.sm),
        FojemTextField(
          controller: _passwordController,
          hint: 'Votre mot de passe',
          prefixIcon: Icons.lock_outline,
          obscureText: true,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() => _errorMessage = null),
          onFieldSubmitted: (_) => _submit(),
          borderRadius: 0,
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const Icon(Icons.error_outline, size: 16, color: AppColors.danger),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(_errorMessage!, style: AppTextStyles.caption.copyWith(color: AppColors.danger)),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        FojemButton.primary(
          label: 'Se connecter',
          suffixIcon: Icons.arrow_forward,
          isLoading: _isLoading,
          onPressed: _isLoading ? null : _submit,
        ),
      ],
    );
  }
}

/// Bloc logo affiché en tête de l'écran d'auth — plus grand que le
/// FojemLogo.icon compact utilisé dans les app bars (home, etc.).
class _AuthHeader extends StatelessWidget {
  const _AuthHeader();

  @override
  Widget build(BuildContext context) {
    return const Center(child: FojemLogo(width: 180));
  }
}

/// Lien d'inscription affiché sous la carte Connexion (hors carte).
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
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  static final _emailRegex = RegExp(
    r'^[a-zA-Z0-9.!#$%&’*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+$',
  );

  bool get _isEmailValid => _emailRegex.hasMatch(_emailController.text.trim());

  bool get _isPhoneValid {
    final cleaned = _phoneController.text.replaceAll(' ', '');
    return cleaned.length >= 9 && cleaned.length <= 12;
  }

  bool get _isFormValid =>
      _nameController.text.trim().isNotEmpty &&
      _isEmailValid &&
      _isPhoneValid &&
      _passwordController.text.length >= 8 &&
      _confirmController.text == _passwordController.text;

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Veuillez saisir votre nom complet.');
      return;
    }
    if (!_isEmailValid) {
      setState(() => _errorMessage = 'Format d\'e-mail invalide (ex: nom@domaine.com).');
      return;
    }
    if (!_isPhoneValid) {
      setState(() => _errorMessage = 'Numéro de téléphone invalide (9 chiffres min.).');
      return;
    }
    if (_passwordController.text.length < 8) {
      setState(() => _errorMessage = 'Le mot de passe doit comporter au moins 8 caractères.');
      return;
    }
    if (_confirmController.text != _passwordController.text) {
      setState(() => _errorMessage = 'Les mots de passe ne correspondent pas.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final localNumber = _phoneController.text.replaceAll(' ', '');
    final e164Phone = '+221$localNumber';

    try {
      await context.read<AppProvider>().register(
            fullName: _nameController.text.trim(),
            email: _emailController.text.trim(),
            password: _passwordController.text,
            phoneNumber: e164Phone,
            gender: _gender == _Gender.male ? 'male' : 'female',
          );
      if (!mounted) return;
      context.go('/home');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Inscription impossible. Réessayez.';
      });
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
        Text('E-mail', style: AppTextStyles.bodyLargeSemibold),
        const SizedBox(height: AppSpacing.sm),
        FojemTextField(
          controller: _emailController,
          hint: 'vous@exemple.com',
          prefixIcon: Icons.mail_outline,
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
        if (_errorMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const Icon(Icons.error_outline, size: 16, color: AppColors.danger),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(_errorMessage!, style: AppTextStyles.caption.copyWith(color: AppColors.danger)),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySurface : AppColors.surface,
          border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodySemibold.copyWith(color: selected ? AppColors.primary : AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _PhoneField extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  const _PhoneField({
    required this.controller,
    this.onChanged,
  });

  @override
  State<_PhoneField> createState() => _PhoneFieldState();
}

class _PhoneFieldState extends State<_PhoneField> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border, width: 1),
          ),
          child: Row(
            children: [
              const _CountryCode(),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  onChanged: widget.onChanged,
                  style: AppTextStyles.bodyLarge,
                  decoration: InputDecoration(
                    hintText: '77 000 00 00',
                    hintStyle: AppTextStyles.bodyLarge.copyWith(color: AppColors.textMuted),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.md,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CountryCode extends StatelessWidget {
  const _CountryCode();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.call_outlined, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text('+221', style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
