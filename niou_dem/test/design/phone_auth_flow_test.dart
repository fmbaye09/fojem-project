import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_passager/core/theme/app_theme.dart';
import 'package:fojem_passager/core/widgets/phone_auth_flow.dart';
import 'package:google_fonts/google_fonts.dart';

/// Connexion / inscription client par numéro + code, sur un téléphone de
/// taille courante.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late List<String> sends;
  late List<String> checks;
  late List<String> accounts;
  late int done;

  setUp(() {
    sends = [];
    checks = [];
    accounts = [];
    done = 0;
  });

  Future<void> open(
    WidgetTester tester, {
    CheckCodeResult Function(String code)? check,
    SendCodeResult send = const SendCodeResult.sent(),
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: PhoneAuthFlow(
        onSendCode: (phone, channel) async {
          sends.add('$phone|${channel.name}');
          return send;
        },
        onCheckCode: (phone, code) async {
          checks.add('$phone|$code');
          return check?.call(code) ?? const CheckCodeResult.signedIn();
        },
        onCreateAccount: (token, firstName, lastName) async {
          accounts.add('$token|$firstName|$lastName');
          return null;
        },
        onDone: () => done++,
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> enterPhone(WidgetTester tester, String number) async {
    await tester.enterText(find.byKey(const ValueKey('phone')), number);
    await tester.pump();
    await tester.tap(find.text('Recevoir le code'));
    await tester.pump(const Duration(seconds: 1));
  }

  const shownNumber = '+221 77 123 45 67';

  Future<void> enterCode(WidgetTester tester, String code) async {
    await tester.enterText(find.byKey(const ValueKey('code')), code);
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('a new customer gives the number, the code, then the first and last name', (tester) async {
    await open(tester, check: (_) => const CheckCodeResult.newCustomer('tok'));

    expect(find.text('Entrez votre numéro'), findsOneWidget);
    await enterPhone(tester, '771234567');
    expect(sends, ['+221771234567|whatsapp']);
    expect(find.text('Entrez le code'), findsOneWidget);
    // Numéro en espaces insécables : il ne se coupe pas en fin de ligne.
    expect(find.text('Envoyé par WhatsApp au $shownNumber.'), findsOneWidget);

    // Le 6e chiffre valide le code sans autre geste.
    await enterCode(tester, '123456');
    expect(checks, ['+221771234567|123456']);
    expect(find.text('Votre nom'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('first-name')), '  Awa ');
    await tester.enterText(find.byKey(const ValueKey('last-name')), 'Ndiaye');
    await tester.pump();
    await tester.tap(find.text('Créer mon compte'));
    await tester.pump(const Duration(seconds: 1));

    expect(accounts, ['tok|Awa|Ndiaye']);
    expect(done, 1);
  });

  testWidgets('an existing customer is signed in by the code alone', (tester) async {
    await open(tester);

    await enterPhone(tester, '78 111 22 33');
    await enterCode(tester, '654321');

    expect(done, 1);
    expect(find.text('Votre nom'), findsNothing);
  });

  testWidgets('the number is grouped as typed and the country code is dropped when pasted', (tester) async {
    await open(tester);

    await tester.enterText(find.byKey(const ValueKey('phone')), '+221771234567');
    await tester.pump();
    final field = tester.widget<TextField>(find.byKey(const ValueKey('phone')));
    expect(field.controller!.text, '77 123 45 67');
  });

  testWidgets('a landline is refused before any code is sent', (tester) async {
    await open(tester);

    await enterPhone(tester, '338210000');

    expect(sends, isEmpty);
    expect(find.text('Entrez un numéro de mobile : il commence par 7.'), findsOneWidget);
  });

  testWidgets('a wrong code shows the reason and empties the boxes', (tester) async {
    await open(tester,
        check: (_) => const CheckCodeResult.failed(AuthFailure('Code incorrect. Il vous reste 4 essais.')));

    await enterPhone(tester, '771234567');
    await enterCode(tester, '000000');

    expect(find.text('Code incorrect. Il vous reste 4 essais.'), findsOneWidget);
    final field = tester.widget<TextField>(find.byKey(const ValueKey('code')));
    expect(field.controller!.text, isEmpty);
    expect(done, 0);
  });

  testWidgets('a new code can be asked after a minute, by SMS too', (tester) async {
    await open(tester, check: (_) => const CheckCodeResult.failed(AuthFailure('Code incorrect.')));

    await enterPhone(tester, '771234567'); // une seconde s'écoule
    expect(find.text('Renvoyer le code dans 0:59'), findsOneWidget);
    expect(find.text('Recevoir par SMS'), findsNothing);

    await tester.pump(const Duration(seconds: 29));
    expect(find.text('Renvoyer le code dans 0:30'), findsOneWidget);

    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Renvoyer le code dans 0:00'), findsNothing);
    await tester.tap(find.text('Recevoir par SMS'));
    await tester.pump(const Duration(seconds: 1));
    expect(sends, ['+221771234567|whatsapp', '+221771234567|sms']);
    expect(find.text('Envoyé par SMS au $shownNumber.'), findsOneWidget);
  });

  testWidgets('going back to fix the number does not send a second code for the same number', (tester) async {
    await open(tester);

    await enterPhone(tester, '771234567');
    await tester.tap(find.text('Modifier le numéro'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Entrez votre numéro'), findsOneWidget);

    await tester.tap(find.text('Recevoir le code'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Entrez le code'), findsOneWidget);
    expect(sends, hasLength(1));

    // Un autre numéro, lui, reçoit son propre code.
    await tester.tap(find.text('Modifier le numéro'));
    await tester.pump(const Duration(seconds: 1));
    await enterPhone(tester, '781112233');
    expect(sends, ['+221771234567|whatsapp', '+221781112233|whatsapp']);
  });

  testWidgets('in development the code shown by the server fills the boxes', (tester) async {
    await open(tester, send: const SendCodeResult.sent(devCode: '246810'));

    await enterPhone(tester, '771234567');
    await tester.tap(find.textContaining('Code de test : 246810'));
    await tester.pump(const Duration(seconds: 1));

    expect(checks, ['+221771234567|246810']);
    expect(done, 1);
  });

  testWidgets('a server refusal to send stays on the number with its reason', (tester) async {
    await open(tester,
        send: const SendCodeResult.failed(AuthFailure('Patientez 42 s avant de demander un nouveau code.')));

    await enterPhone(tester, '771234567');

    expect(find.text('Entrez votre numéro'), findsOneWidget);
    expect(find.text('Patientez 42 s avant de demander un nouveau code.'), findsOneWidget);
  });
}
