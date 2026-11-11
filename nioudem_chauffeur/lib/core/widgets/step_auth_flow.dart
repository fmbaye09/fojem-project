import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'fojem_logo.dart';
import 'glow.dart';

/// Données saisies à l'inscription, page par page.
class SignupData {
  final String fullName;
  final String phoneNumber; // format +221XXXXXXXXX
  final String email;
  final String gender; // male | female
  final String password;

  const SignupData({
    required this.fullName,
    required this.phoneNumber,
    required this.email,
    required this.gender,
    required this.password,
  });
}

/// Échec renvoyé par le serveur ; [field] (`email`, `phone_number`…) permet
/// de revenir directement sur la page concernée.
class AuthFailure {
  final String message;
  final String? field;

  const AuthFailure(this.message, {this.field});
}

enum _Mode { welcome, login, signup }

enum _Kind { text, phone, email, password, gender, method }

class _Step {
  final String key;
  final String title;
  final String hint;
  final _Kind kind;
  final IconData? icon;
  final String? placeholder;

  /// Clé d'erreur serveur correspondant à cette page.
  final String? serverField;

  const _Step(this.key, this.title, this.hint, this.kind, {this.icon, this.placeholder, this.serverField});
}

/// Connexion / inscription page par page (template fojem-glow-flow) : une
/// information par écran, barre de progression, transitions animées.
class StepAuthFlow extends StatefulWidget {
  /// « Bienvenue chez FOJËM » / « FOJËM Pro ».
  final String welcomeTitle;
  final String welcomeSubtitle;
  final Future<AuthFailure?> Function(String login, String password) onLogin;
  final Future<AuthFailure?> Function(SignupData data) onSignup;
  final VoidCallback onDone;

  const StepAuthFlow({
    super.key,
    required this.welcomeTitle,
    required this.welcomeSubtitle,
    required this.onLogin,
    required this.onSignup,
    required this.onDone,
  });

  @override
  State<StepAuthFlow> createState() => _StepAuthFlowState();
}

class _StepAuthFlowState extends State<StepAuthFlow> {
  static const _signup = [
    _Step('name', 'Comment vous appelez-vous ?', 'Votre nom sera visible par les chauffeurs et les passagers.',
        _Kind.text, icon: Icons.person_outline_rounded, placeholder: 'Prénom et nom', serverField: 'full_name'),
    _Step('phone', 'Votre numéro de téléphone', 'Les chauffeurs et passagers pourront vous joindre pendant le trajet.',
        _Kind.phone, icon: Icons.phone_outlined, placeholder: '77 000 00 00', serverField: 'phone_number'),
    _Step('email', 'Votre adresse e-mail', 'Pour vos billets, reçus et la récupération de votre compte.',
        _Kind.email, icon: Icons.mail_outline_rounded, placeholder: 'vous@exemple.com', serverField: 'email'),
    _Step('gender', 'Vous êtes…', 'Certains trajets sont réservés aux femmes.', _Kind.gender, serverField: 'gender'),
    _Step('password', 'Créez un mot de passe', 'Au moins 8 caractères. Touchez l’œil pour vérifier votre saisie.', _Kind.password,
        icon: Icons.lock_outline_rounded, placeholder: 'Mot de passe', serverField: 'password'),
  ];

  static const _login = [
    _Step('id', '', 'Saisissez l’identifiant de votre compte.', _Kind.text),
    _Step('password', 'Votre mot de passe', 'Bon retour parmi nous !', _Kind.password,
        icon: Icons.lock_outline_rounded, placeholder: 'Mot de passe'),
  ];

  _Mode _mode = _Mode.welcome;
  int _index = 0;
  final Map<String, String> _data = {'method': 'phone', 'gender': 'male'};
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  List<_Step> get _steps => _mode == _Mode.signup ? _signup : _login;

  _Step get _step {
    final step = _steps[_index];
    if (_mode == _Mode.login && step.key == 'id') {
      return _data['method'] == 'phone'
          ? const _Step('id', 'Votre numéro de téléphone', 'Le numéro utilisé à l’inscription.', _Kind.phone,
              icon: Icons.phone_outlined, placeholder: '77 000 00 00')
          : const _Step('id', 'Votre adresse e-mail', 'L’adresse utilisée à l’inscription.', _Kind.email,
              icon: Icons.mail_outline_rounded, placeholder: 'vous@exemple.com');
    }
    return step;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(_Mode mode, int index) {
    setState(() {
      _mode = mode;
      _index = index;
      _error = null;
      _obscure = true;
      if (mode != _Mode.welcome) _controller.text = _data[_steps[index].key] ?? '';
    });
  }

  String _digits(String v) => v.replaceAll(RegExp(r'\D'), '');

  bool get _valid {
    final v = _controller.text.trim();
    switch (_step.kind) {
      case _Kind.gender:
      case _Kind.method:
        return true;
      case _Kind.password:
        return _mode == _Mode.signup ? v.length >= 8 : v.isNotEmpty;
      case _Kind.email:
        return RegExp(r'^\S+@\S+\.\S+$').hasMatch(v);
      case _Kind.phone:
        return _digits(v).length >= 9;
      case _Kind.text:
        return v.length >= 2;
    }
  }

  /// +221 + 9 derniers chiffres, quel que soit le format saisi.
  String _e164(String v) {
    final d = _digits(v);
    return '+221${d.length > 9 ? d.substring(d.length - 9) : d}';
  }

  Future<void> _next() async {
    if (!_valid || _busy) return;
    final step = _step;
    if (step.kind != _Kind.gender && step.kind != _Kind.method) {
      _data[step.key] = _controller.text.trim();
    }
    if (step.key == 'confirm' && _data['confirm'] != _data['password']) {
      setState(() => _error = 'Les mots de passe ne correspondent pas.');
      return;
    }
    if (_index < _steps.length - 1) {
      _goTo(_mode, _index + 1);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final failure = _mode == _Mode.signup
        ? await widget.onSignup(SignupData(
            fullName: _data['name']!,
            phoneNumber: _e164(_data['phone']!),
            email: _data['email']!,
            gender: _data['gender']!,
            password: _data['password']!,
          ))
        : await widget.onLogin(
            _data['method'] == 'phone' ? _e164(_data['id']!) : _data['id']!,
            _data['password']!,
          );
    if (!mounted) return;
    if (failure == null) {
      widget.onDone();
      return;
    }

    // Erreur sur un champ précis : retour à sa page, message affiché.
    final target = _steps.indexWhere((s) => s.serverField != null && s.serverField == failure.field);
    setState(() => _busy = false);
    if (target >= 0 && target != _index) _goTo(_mode, target);
    setState(() => _error = failure.message);
  }

  /// Connexion par e-mail plutôt que par téléphone (et inversement).
  void _switchLoginMethod() {
    setState(() {
      _data['method'] = _data['method'] == 'phone' ? 'email' : 'phone';
      _data.remove('id');
      _controller.clear();
      _error = null;
    });
  }

  void _back() {
    if (_index == 0) {
      _goTo(_Mode.welcome, 0);
    } else {
      _goTo(_mode, _index - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _mode == _Mode.welcome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: AppColors.sunriseGradient),
          child: SafeArea(child: _mode == _Mode.welcome ? _welcome() : _stepper()),
        ),
      ),
    );
  }

  Widget _welcome() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 64, 28, 28),
      child: Column(
        children: [
          const RiseIn(
            child: NeuBox(radius: 36, padding: EdgeInsets.all(18), child: FojemLogo.icon(size: 96)),
          ),
          const SizedBox(height: 32),
          RiseIn(
            delay: const Duration(milliseconds: 120),
            child: Text(widget.welcomeTitle,
                textAlign: TextAlign.center, style: AppTextStyles.display.copyWith(fontSize: 30)),
          ),
          const SizedBox(height: 12),
          RiseIn(
            delay: const Duration(milliseconds: 200),
            child: Text(widget.welcomeSubtitle,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary)),
          ),
          const Spacer(),
          RiseIn(
            delay: const Duration(milliseconds: 280),
            child: Column(
              children: [
                GlowButton(label: 'Créer un compte', onPressed: () => _goTo(_Mode.signup, 0)),
                const SizedBox(height: 16),
                NeuButton(label: 'Se connecter', onPressed: () => _goTo(_Mode.login, 0)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepper() {
    final step = _step;
    final isLast = _index == _steps.length - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GlassIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Retour',
                onPressed: () {
                  if (!_busy) _back();
                },
              ),
              const SizedBox(width: 16),
              Expanded(
                child: NeuInset(
                  radius: 6,
                  padding: EdgeInsets.zero,
                  child: SizedBox(
                    height: 8,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedFractionallySizedBox(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOutCubic,
                        widthFactor: (_index + 1) / _steps.length,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: AppColors.brandGradient,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text('${_index + 1}/${_steps.length}',
                  style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              child: RiseIn(
                key: ValueKey('$_mode-$_index'),
                child: Padding(
                  padding: const EdgeInsets.only(top: 44),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _mode == _Mode.signup ? 'INSCRIPTION' : 'CONNEXION',
                        style: AppTextStyles.label.copyWith(color: AppColors.primary, letterSpacing: 2),
                      ),
                      const SizedBox(height: 8),
                      Text(step.title, style: AppTextStyles.display.copyWith(fontSize: 29, height: 1.15)),
                      const SizedBox(height: 8),
                      Text(step.hint, style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 36),
                      _input(step),
                      if (_mode == _Mode.login && step.key == 'id')
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: TextButton.icon(
                            onPressed: _busy ? null : _switchLoginMethod,
                            icon: Icon(_data['method'] == 'phone' ? Icons.mail_outline_rounded : Icons.phone_outlined, size: 18),
                            label: Text(_data['method'] == 'phone' ? 'Utiliser mon e-mail' : 'Utiliser mon numéro de téléphone'),
                          ),
                        ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.danger),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(_error!,
                                  style: AppTextStyles.body.copyWith(color: AppColors.danger)),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          GlowButton(
            label: isLast ? (_mode == _Mode.signup ? 'Créer mon compte' : 'Se connecter') : 'Continuer',
            icon: Icons.arrow_forward_rounded,
            isLoading: _busy,
            onPressed: _valid ? _next : null,
          ),
          const SizedBox(height: 14),
          Center(
            child: GestureDetector(
              onTap: _busy ? null : () => _goTo(_mode == _Mode.signup ? _Mode.login : _Mode.signup, 0),
              child: Text.rich(
                TextSpan(
                  text: _mode == _Mode.signup ? 'Déjà un compte ? ' : 'Nouveau sur FOJËM ? ',
                  style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                  children: [
                    TextSpan(
                      text: _mode == _Mode.signup ? 'Se connecter' : 'Créer un compte',
                      style: AppTextStyles.bodySemibold.copyWith(color: AppColors.primary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _input(_Step step) {
    switch (step.kind) {
      case _Kind.method:
        return Row(
          children: [
            for (final (value, label, icon) in const [
              ('phone', 'Téléphone', Icons.phone_outlined),
              ('email', 'E-mail', Icons.mail_outline_rounded),
            ]) ...[
              if (value == 'email') const SizedBox(width: 16),
              Expanded(child: _choiceTile(step.key, value, label, icon, vertical: true)),
            ],
          ],
        );
      case _Kind.gender:
        return Column(
          children: [
            _choiceTile(step.key, 'male', 'Homme', Icons.man_rounded),
            const SizedBox(height: 16),
            _choiceTile(step.key, 'female', 'Femme', Icons.woman_rounded),
          ],
        );
      default:
        return NeuInset(
          radius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: Row(
            children: [
              if (step.icon != null) Icon(step.icon, color: AppColors.primary, size: 22),
              const SizedBox(width: 12),
              if (step.kind == _Kind.phone) ...[
                Text('+221', style: AppTextStyles.bodyLargeSemibold.copyWith(color: AppColors.textSecondary)),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: TextField(
                  key: ValueKey('field-$_mode-${step.key}-${step.kind}'),
                  controller: _controller,
                  autofocus: true,
                  obscureText: step.kind == _Kind.password && _obscure,
                  keyboardType: switch (step.kind) {
                    _Kind.phone => TextInputType.phone,
                    _Kind.email => TextInputType.emailAddress,
                    _Kind.text => TextInputType.name,
                    _ => TextInputType.visiblePassword,
                  },
                  textCapitalization:
                      step.kind == _Kind.text ? TextCapitalization.words : TextCapitalization.none,
                  inputFormatters: step.kind == _Kind.phone
                      ? [FilteringTextInputFormatter.allow(RegExp(r'[\d ]'))]
                      : null,
                  autofillHints: switch (step.kind) {
                    _Kind.phone => const [AutofillHints.telephoneNumberNational],
                    _Kind.email => const [AutofillHints.email],
                    _Kind.text => const [AutofillHints.name],
                    _Kind.password => [_mode == _Mode.signup ? AutofillHints.newPassword : AutofillHints.password],
                    _ => null,
                  },
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) => _next(),
                  style: AppTextStyles.bodyLargeSemibold.copyWith(fontSize: 18),
                  decoration: InputDecoration(
                    hintText: step.placeholder,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              if (step.kind == _Kind.password)
                IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  tooltip: _obscure ? 'Afficher' : 'Masquer',
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: AppColors.textSecondary),
                ),
            ],
          ),
        );
    }
  }

  /// Choix exclusif : l'option choisie est cerclée de bleu nuit et cochée.
  Widget _choiceTile(String key, String value, String label, IconData icon, {bool vertical = false}) {
    final selected = _data[key] == value;
    final iconBox = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: selected ? AppColors.ink : AppColors.muted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: selected ? Colors.white : AppColors.textPrimary),
    );
    final content = vertical
        ? Column(
            children: [
              iconBox,
              const SizedBox(height: 12),
              Text(label, style: AppTextStyles.bodyLargeSemibold),
            ],
          )
        : Row(
            children: [
              iconBox,
              const SizedBox(width: 16),
              Expanded(child: Text(label, style: AppTextStyles.bodyLargeSemibold)),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: selected ? AppColors.ink : AppColors.borderStrong,
              ),
            ],
          );
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: selected ? AppColors.ink : AppColors.border, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => setState(() => _data[key] = value),
          child: Padding(padding: EdgeInsets.all(vertical ? 20 : 14), child: content),
        ),
      ),
    );
  }
}
