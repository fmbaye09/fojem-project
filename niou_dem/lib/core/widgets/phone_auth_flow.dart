import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'fojem_logo.dart';
import 'glow.dart';

/// Échec renvoyé par le serveur, affiché sous le champ.
class AuthFailure {
  final String message;

  const AuthFailure(this.message);
}

/// Canal d'envoi du code.
enum CodeChannel { whatsapp, sms }

/// Résultat d'une demande de code.
class SendCodeResult {
  final AuthFailure? failure;

  /// Secondes avant de pouvoir redemander un code.
  final int resendIn;

  /// Code renvoyé par un serveur de développement (aucun envoi réel).
  final String? devCode;

  const SendCodeResult.sent({this.resendIn = 60, this.devCode}) : failure = null;

  const SendCodeResult.failed(AuthFailure this.failure)
      : resendIn = 0,
        devCode = null;
}

/// Résultat de la vérification du code.
class CheckCodeResult {
  final AuthFailure? failure;

  /// Nouveau client : jeton qui permet de créer son compte une fois son nom donné.
  final String? signupToken;

  const CheckCodeResult.signedIn()
      : failure = null,
        signupToken = null;

  const CheckCodeResult.newCustomer(String this.signupToken) : failure = null;

  const CheckCodeResult.failed(AuthFailure this.failure) : signupToken = null;
}

enum _Stage { phone, code, name }

/// Connexion et inscription des clients en un seul parcours : numéro de
/// téléphone, code reçu par WhatsApp (ou SMS), puis prénom et nom pour un
/// nouveau client seulement. Ni e-mail, ni mot de passe.
class PhoneAuthFlow extends StatefulWidget {
  final Future<SendCodeResult> Function(String phoneNumber, CodeChannel channel) onSendCode;
  final Future<CheckCodeResult> Function(String phoneNumber, String code) onCheckCode;
  final Future<AuthFailure?> Function(String signupToken, String firstName, String lastName) onCreateAccount;
  final VoidCallback onDone;
  final VoidCallback? onOpenTerms;
  final VoidCallback? onOpenPrivacy;

  const PhoneAuthFlow({
    super.key,
    required this.onSendCode,
    required this.onCheckCode,
    required this.onCreateAccount,
    required this.onDone,
    this.onOpenTerms,
    this.onOpenPrivacy,
  });

  @override
  State<PhoneAuthFlow> createState() => _PhoneAuthFlowState();
}

class _PhoneAuthFlowState extends State<PhoneAuthFlow> {
  static const _codeLength = 6;

  _Stage _stage = _Stage.phone;
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _codeFocus = FocusNode();
  final _lastNameFocus = FocusNode();
  late final _termsTap = TapGestureRecognizer()..onTap = widget.onOpenTerms;
  late final _privacyTap = TapGestureRecognizer()..onTap = widget.onOpenPrivacy;

  CodeChannel _channel = CodeChannel.whatsapp;

  /// Numéro auquel le dernier code est parti : revenir le corriger puis
  /// repartir sans le changer ne renvoie pas de code.
  String? _sentTo;
  String? _devCode;
  String? _signupToken;
  bool _busy = false;
  String? _error;
  int _resendIn = 0;
  Timer? _ticker;

  String get _digits => _phone.text.replaceAll(RegExp(r'\D'), '');
  String get _e164 => '+221$_digits';
  bool get _phoneComplete => _digits.length == 9;
  bool get _nameComplete => _clean(_firstName.text).length >= 2 && _clean(_lastName.text).length >= 2;

  @override
  void dispose() {
    _ticker?.cancel();
    _phone.dispose();
    _code.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _codeFocus.dispose();
    _lastNameFocus.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  static String _clean(String v) => v.trim().replaceAll(RegExp(r'\s+'), ' ');

  Future<void> _sendCode({CodeChannel? channel}) async {
    if (_busy || !_phoneComplete) return;
    if (!_digits.startsWith('7')) {
      setState(() => _error = 'Entrez un numéro de mobile : il commence par 7.');
      return;
    }
    // Le code déjà envoyé à ce numéro est encore valable.
    if (channel == null && _sentTo == _e164 && _resendIn > 0) {
      setState(() {
        _stage = _Stage.code;
        _error = null;
      });
      return;
    }

    final via = channel ?? _channel;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.onSendCode(_e164, via);
    if (!mounted) return;
    final failure = result.failure;
    setState(() {
      _busy = false;
      if (failure != null) {
        _error = failure.message;
        return;
      }
      _channel = via;
      _sentTo = _e164;
      _devCode = result.devCode;
      _stage = _Stage.code;
      _code.clear();
    });
    if (failure == null) _startCountdown(result.resendIn);
  }

  void _startCountdown(int seconds) {
    _ticker?.cancel();
    setState(() => _resendIn = seconds);
    if (seconds <= 0) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendIn <= 1) timer.cancel();
      if (mounted) setState(() => _resendIn = _resendIn > 0 ? _resendIn - 1 : 0);
    });
  }

  Future<void> _checkCode() async {
    final code = _code.text;
    if (_busy || code.length != _codeLength) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.onCheckCode(_e164, code);
    if (!mounted) return;
    final failure = result.failure;
    if (failure != null) {
      setState(() {
        _busy = false;
        _error = failure.message;
        _code.clear();
      });
      _codeFocus.requestFocus();
      return;
    }
    final token = result.signupToken;
    if (token != null) {
      _ticker?.cancel();
      setState(() {
        _busy = false;
        _signupToken = token;
        _sentTo = null; // code utilisé
        _resendIn = 0;
        _stage = _Stage.name;
      });
      return;
    }
    widget.onDone();
  }

  Future<void> _createAccount() async {
    final token = _signupToken;
    if (_busy || token == null || !_nameComplete) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final failure = await widget.onCreateAccount(token, _clean(_firstName.text), _clean(_lastName.text));
    if (!mounted) return;
    if (failure == null) {
      widget.onDone();
      return;
    }
    setState(() {
      _busy = false;
      _error = failure.message;
    });
  }

  void _back() {
    if (_busy) return;
    setState(() {
      if (_stage == _Stage.name) _signupToken = null;
      _stage = _Stage.phone;
      _error = null;
      _code.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _stage == _Stage.phone,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_stage != _Stage.phone)
                  Row(
                    children: [
                      GlassIconButton(icon: Icons.arrow_back_rounded, tooltip: 'Retour', onPressed: _back),
                      const Spacer(),
                      if (_stage == _Stage.code)
                        TextButton(
                          onPressed: _busy ? null : _back,
                          style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                          child: const Text('Modifier le numéro'),
                        ),
                    ],
                  ),
                // Clavier ouvert sur un petit écran : le haut défile, le champ
                // et le bouton restent visibles.
                Expanded(
                  child: SingleChildScrollView(
                    child: RiseIn(
                      key: ValueKey(_stage),
                      child: Padding(
                        padding: EdgeInsets.only(top: _stage == _Stage.phone ? 8 : 20, bottom: 16),
                        child: switch (_stage) {
                          _Stage.phone => _phoneStage(),
                          _Stage.code => _codeStage(),
                          _Stage.name => _nameStage(),
                        },
                      ),
                    ),
                  ),
                ),
                ..._footer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _title(String title, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(title, style: AppTextStyles.display.copyWith(fontSize: 29))),
        const SizedBox(height: 8),
        Text(hint, style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _phoneStage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FojemLogo.icon(size: 48),
        const SizedBox(height: 20),
        _title(
          'Entrez votre numéro',
          'Vous recevrez un code par WhatsApp pour vous connecter ou créer votre compte.',
        ),
        const SizedBox(height: 28),
        NeuInset(
          radius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: Row(
            children: [
              Text('+221', style: AppTextStyles.bodyLargeSemibold.copyWith(fontSize: 18, color: AppColors.textSecondary)),
              Container(width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 14), color: AppColors.borderStrong),
              Expanded(
                child: TextField(
                  key: const ValueKey('phone'),
                  controller: _phone,
                  autofocus: true,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [_SenegalPhoneFormatter()],
                  autofillHints: const [AutofillHints.telephoneNumberNational],
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) => _sendCode(),
                  style: AppTextStyles.bodyLargeSemibold.copyWith(fontSize: 20, letterSpacing: 0.5),
                  decoration: const InputDecoration(
                    hintText: '77 123 45 67',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
        _errorLine(),
        const SizedBox(height: 16),
        _legal(),
      ],
    );
  }

  Widget _legal() {
    const link = TextStyle(decoration: TextDecoration.underline, fontWeight: FontWeight.w700);
    return Text.rich(
      TextSpan(
        style: AppTextStyles.caption,
        children: [
          const TextSpan(text: 'En continuant, vous acceptez les '),
          // Espaces insécables : chaque lien reste d'un seul tenant, plus facile à toucher.
          TextSpan(
            text: 'conditions d’utilisation',
            style: link,
            recognizer: widget.onOpenTerms == null ? null : _termsTap,
          ),
          const TextSpan(text: ' et la '),
          TextSpan(
            text: 'politique de confidentialité',
            style: link,
            recognizer: widget.onOpenPrivacy == null ? null : _privacyTap,
          ),
          const TextSpan(text: ' de FOJËM.'),
        ],
      ),
    );
  }

  Widget _codeStage() {
    final via = _channel == CodeChannel.whatsapp ? 'WhatsApp' : 'SMS';
    final devCode = _devCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Espaces insécables : le numéro ne se coupe pas en fin de ligne.
        _title('Entrez le code', 'Envoyé par $via au ${'+221 ${_phone.text}'.replaceAll(' ', ' ')}.'),
        const SizedBox(height: 24),
        _CodeField(
          controller: _code,
          focusNode: _codeFocus,
          length: _codeLength,
          hasError: _error != null,
          onChanged: (value) {
            setState(() => _error = null);
            if (value.length == _codeLength) _checkCode();
          },
        ),
        _errorLine(),
        if (devCode != null) ...[
          const SizedBox(height: 14),
          Material(
            color: AppColors.muted,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _busy
                  ? null
                  : () {
                      _code.text = devCode;
                      _checkCode();
                    },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.science_outlined, size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Code de test : $devCode · toucher pour remplir',
                          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        _resend(),
      ],
    );
  }

  /// Sous les cases : vérification en cours, compte à rebours, ou renvoi.
  Widget _resend() {
    if (_busy) {
      return Row(
        children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text('Vérification…', style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
        ],
      );
    }
    if (_resendIn > 0) {
      final s = _resendIn;
      return Text(
        'Renvoyer le code dans ${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}',
        style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Vous n’avez rien reçu ?', style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: _busy ? null : () => _sendCode(channel: CodeChannel.whatsapp),
              icon: const Icon(Icons.chat_rounded, size: 18),
              label: const Text('Renvoyer par WhatsApp'),
            ),
            TextButton.icon(
              onPressed: _busy ? null : () => _sendCode(channel: CodeChannel.sms),
              icon: const Icon(Icons.sms_rounded, size: 18),
              label: const Text('Recevoir par SMS'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _nameStage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Votre nom', 'Il sera visible par les chauffeurs.'),
        const SizedBox(height: 24),
        // Côte à côte : les deux champs restent visibles au-dessus du clavier.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _nameField(
                label: 'Prénom',
                controller: _firstName,
                fieldKey: const ValueKey('first-name'),
                autofocus: true,
                hints: const [AutofillHints.givenName],
                action: TextInputAction.next,
                onSubmitted: () => _lastNameFocus.requestFocus(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _nameField(
                label: 'Nom',
                controller: _lastName,
                fieldKey: const ValueKey('last-name'),
                focusNode: _lastNameFocus,
                hints: const [AutofillHints.familyName],
                action: TextInputAction.done,
                onSubmitted: _createAccount,
              ),
            ),
          ],
        ),
        _errorLine(),
      ],
    );
  }

  Widget _nameField({
    required String label,
    required TextEditingController controller,
    required Key fieldKey,
    required List<String> hints,
    required TextInputAction action,
    required VoidCallback onSubmitted,
    FocusNode? focusNode,
    bool autofocus = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.label.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        NeuInset(
          radius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: TextField(
            key: fieldKey,
            controller: controller,
            focusNode: focusNode,
            autofocus: autofocus,
            keyboardType: TextInputType.name,
            textCapitalization: TextCapitalization.words,
            autofillHints: hints,
            textInputAction: action,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => onSubmitted(),
            style: AppTextStyles.bodyLargeSemibold.copyWith(fontSize: 18),
            decoration: const InputDecoration(
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorLine() {
    final error = _error;
    if (error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.danger),
            const SizedBox(width: 6),
            Expanded(child: Text(error, style: AppTextStyles.body.copyWith(color: AppColors.danger))),
          ],
        ),
      ),
    );
  }

  List<Widget> _footer() {
    switch (_stage) {
      case _Stage.phone:
        return [
          GlowButton(
            label: 'Recevoir le code',
            icon: Icons.arrow_forward_rounded,
            isLoading: _busy,
            onPressed: _phoneComplete ? _sendCode : null,
          ),
        ];
      case _Stage.code:
        // Le 6e chiffre valide le code : pas de bouton.
        return const [];
      case _Stage.name:
        return [
          GlowButton(
            label: 'Créer mon compte',
            icon: Icons.arrow_forward_rounded,
            isLoading: _busy,
            onPressed: _nameComplete ? _createAccount : null,
          ),
        ];
    }
  }
}

/// Six cases, une par chiffre. Un vrai champ texte (transparent) est posé
/// dessus : clavier, collage et remplissage automatique fonctionnent.
class _CodeField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final int length;
  final bool hasError;
  final ValueChanged<String> onChanged;

  const _CodeField({
    required this.controller,
    required this.focusNode,
    required this.length,
    required this.hasError,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, focusNode]),
      builder: (context, _) {
        final code = controller.text;
        return SizedBox(
          height: 60,
          child: Stack(
            children: [
              Row(
                children: [
                  for (var i = 0; i < length; i++) ...[
                    if (i > 0) SizedBox(width: i == length ~/ 2 ? 14 : 8),
                    Expanded(child: _box(i, code)),
                  ],
                ],
              ),
              Positioned.fill(
                child: Semantics(
                  label: 'Code à $length chiffres',
                  child: TextField(
                    key: const ValueKey('code'),
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(length),
                    ],
                    showCursor: false,
                    expands: true,
                    maxLines: null,
                    style: const TextStyle(color: Colors.transparent),
                    decoration: const InputDecoration(
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      counterText: '',
                    ),
                    onChanged: onChanged,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _box(int i, String code) {
    final filled = i < code.length;
    final current = focusNode.hasFocus && (i == code.length || (i == length - 1 && code.length == length));
    final Color border = hasError
        ? AppColors.danger
        : current
            ? AppColors.ink
            : (filled ? AppColors.borderStrong : AppColors.border);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: current || hasError ? 2 : 1),
      ),
      child: Text(filled ? code[i] : '', style: AppTextStyles.display.copyWith(fontSize: 26)),
    );
  }
}

/// Garde les 9 chiffres du numéro national et les groupe « 77 123 45 67 ».
/// Un numéro collé avec l'indicatif (+221, 00221) est ramené au national.
class _SenegalPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 9 && digits.startsWith('00221')) digits = digits.substring(5);
    if (digits.length > 9 && digits.startsWith('221')) digits = digits.substring(3);
    if (digits.length > 9) digits = digits.substring(0, 9);

    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 2 || i == 5 || i == 7) out.write(' ');
      out.write(digits[i]);
    }
    final text = out.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
