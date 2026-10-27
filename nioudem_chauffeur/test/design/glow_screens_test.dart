import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_chauffeur/core/theme/app_theme.dart';
import 'package:fojem_chauffeur/core/widgets/bottom_nav_bar.dart';
import 'package:fojem_chauffeur/core/widgets/profile_kit.dart';
import 'package:fojem_chauffeur/core/widgets/step_auth_flow.dart';
import 'package:fojem_chauffeur/features/onboarding/screens/onboarding_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Rendu des écrans « Glow Flow » sur un téléphone de taille courante :
/// aucune erreur de mise en page (débordement, contraintes) à l'affichage.
void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('fr_FR');
  });

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: screen));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('bottom tab bar stays a compact bar at the bottom', (tester) async {
    await pump(
      tester,
      const Scaffold(
        body: Center(child: Text('Contenu')),
        bottomNavigationBar: DriverBottomNavBar(current: DriverTab.home),
      ),
    );

    final bar = tester.getRect(find.byType(DriverBottomNavBar));
    final screen = tester.getRect(find.byType(Scaffold));
    // Régression : la barre occupait tout l'écran (onglets centrés étirés).
    expect(bar.height, lessThan(100));
    expect(bar.bottom, screen.bottom);
    // Barre fixe pleine largeur, plus flottante.
    expect(bar.width, screen.width);
    expect(find.text('Contenu'), findsOneWidget);
  });


  testWidgets('onboarding renders its three slides', (tester) async {
    await pump(tester, const OnboardingScreen());
    expect(find.text('Suivant'), findsOneWidget);
    await tester.tap(find.text('Suivant'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Suivant'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Commencer'), findsOneWidget);
  });

  testWidgets('signup walks through every page', (tester) async {
    SignupData? sent;
    await pump(
      tester,
      StepAuthFlow(
        welcomeTitle: 'Bienvenue chez FOJËM',
        welcomeSubtitle: 'Test',
        onLogin: (_, __) async => null,
        onSignup: (data) async {
          sent = data;
          return null;
        },
        onDone: () {},
      ),
    );

    await tester.tap(find.text('Créer un compte'));
    await tester.pump(const Duration(seconds: 1));

    Future<void> fill(String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump();
      await tester.tap(find.text('Continuer'));
      await tester.pump(const Duration(seconds: 1));
    }

    await fill('Awa Ndiaye');
    await fill('77 123 45 67');
    await fill('awa@exemple.com');
    // Genre : choix par défaut.
    await tester.tap(find.text('Continuer'));
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(find.byType(TextField), 'motdepasse');
    await tester.pump();
    await tester.tap(find.text('Créer mon compte'));
    await tester.pump(const Duration(seconds: 1));

    expect(sent?.fullName, 'Awa Ndiaye');
    expect(sent?.phoneNumber, '+221771234567');
    expect(sent?.email, 'awa@exemple.com');
    expect(sent?.gender, 'male');
  });

  testWidgets('a server error on the email sends the user back to that page', (tester) async {
    await pump(
      tester,
      StepAuthFlow(
        welcomeTitle: 'Bienvenue',
        welcomeSubtitle: 'Test',
        onLogin: (_, __) async => null,
        onSignup: (_) async => const AuthFailure('Cet e-mail est déjà utilisé.', field: 'email'),
        onDone: () {},
      ),
    );
    await tester.tap(find.text('Créer un compte'));
    await tester.pump(const Duration(seconds: 1));
    for (final value in ['Awa Ndiaye', '771234567', 'awa@exemple.com']) {
      await tester.enterText(find.byType(TextField), value);
      await tester.pump();
      await tester.tap(find.text('Continuer'));
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.tap(find.text('Continuer'));
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(find.byType(TextField), 'motdepasse');
    await tester.pump();
    await tester.tap(find.text('Créer mon compte'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Votre adresse e-mail'), findsOneWidget);
    expect(find.text('Cet e-mail est déjà utilisé.'), findsOneWidget);
  });

  testWidgets('profile card and menu fit a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(720, 1520); // 360 dp de large
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await pump(
      tester,
      Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ProfileHeroCard(
              name: 'Aminata Ndiaye Diop Sarr',
              subtitle: 'Membre depuis septembre 2026',
              onEditPhoto: () {},
              stats: const [
                ProfileStat(icon: Icons.star_rounded, color: Colors.orange, value: '4,9', label: 'Note'),
                ProfileStat(icon: Icons.route_rounded, color: Colors.teal, value: '128', label: 'Trajets'),
              ],
              infos: const [
                ProfileInfo(icon: Icons.verified_user_rounded, color: Colors.green, label: 'Statut', value: 'Dossier incomplet'),
                ProfileInfo(icon: Icons.phone_rounded, color: Colors.blue, label: 'Téléphone', value: '+221 77 123 45 67'),
              ],
            ),
            ProfileMenuCard(title: 'Mon compte', items: [
              ProfileMenuItem(icon: Icons.person_rounded, title: 'Informations personnelles', subtitle: 'Nom, téléphone, e-mail', onTap: () {}),
            ]),
            ProfileLogoutButton(onTap: () {}),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('AS'), findsOneWidget);
    expect(find.text('Informations personnelles'), findsOneWidget);
  });

  testWidgets('the last list item is not hidden behind the tab bar', (tester) async {
    await pump(
      tester,
      Scaffold(
        body: ListView(
          children: [
            for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('Ligne $i')),
          ],
        ),
        bottomNavigationBar: const DriverBottomNavBar(current: DriverTab.home),
      ),
    );

    await tester.dragUntilVisible(find.text('Ligne 39'), find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    final last = tester.getRect(find.text('Ligne 39'));
    final bar = tester.getRect(find.byType(DriverBottomNavBar));
    expect(last.bottom, lessThanOrEqualTo(bar.top + 0.01));
  });
}
