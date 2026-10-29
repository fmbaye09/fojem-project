import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_passager/core/theme/app_theme.dart';
import 'package:fojem_passager/core/widgets/bottom_nav_bar.dart';
import 'package:fojem_passager/core/widgets/profile_kit.dart';
import 'package:fojem_passager/core/widgets/step_auth_flow.dart';
import 'package:fojem_passager/core/widgets/trip_card.dart';
import 'package:fojem_passager/models/trip.dart';
import 'package:fojem_passager/features/onboarding/screens/onboarding_screen.dart';
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
        bottomNavigationBar: TravelerBottomNavBar(current: ClientTab.home),
      ),
    );

    final bar = tester.getRect(find.byType(TravelerBottomNavBar));
    final screen = tester.getRect(find.byType(Scaffold));
    // Régression : la barre occupait tout l'écran (onglets centrés étirés).
    expect(bar.height, lessThan(100));
    expect(bar.bottom, screen.bottom);
    // Barre fixe pleine largeur, plus flottante.
    expect(bar.width, screen.width);
    expect(find.text('Contenu'), findsOneWidget);
  });

  testWidgets('trip card fits a narrow phone with long stop names', (tester) async {
    tester.view.physicalSize = const Size(720, 1520); // 360 dp de large
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final trip = Trip.fromApi({
      'id': 't1',
      'status': 'open',
      'scheduled_at': '2026-11-02T08:30:00Z',
      'price_per_seat': '3000.00',
      'seats_available': 3,
      'stops': [
        {'id': 's0', 'position': 0, 'name': 'Gare routière des Baux Maraîchers', 'lat': 14.7, 'lng': -17.4, 'scheduled_at': '2026-11-02T08:30:00Z', 'price_from_origin': '0'},
        {'id': 's1', 'position': 1, 'name': 'Commune de Rufisque Est', 'lat': 14.7, 'lng': -17.2, 'scheduled_at': '2026-11-02T10:10:00Z', 'price_from_origin': '3000'},
      ],
      'match': {
        'boarding_stop': {'id': 's0', 'position': 0, 'name': 'Gare routière des Baux Maraîchers', 'lat': 14.7, 'lng': -17.4, 'scheduled_at': '2026-11-02T08:30:00Z', 'price_from_origin': '0'},
        'alighting_stop': {'id': 's1', 'position': 1, 'name': 'Commune de Rufisque Est', 'lat': 14.7, 'lng': -17.2, 'scheduled_at': '2026-11-02T10:10:00Z', 'price_from_origin': '3000'},
        'boarding_distance_m': 1240,
        'alighting_distance_m': 80,
        'segment_price': '3000.00',
      },
    });

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: TripCard(trip: trip, layout: TripCardLayout.schedule, onTap: () {}),
        ),
      ),
    ));
    await tester.pump();

    // Espaces insécables : le montant et « FCFA » restent sur une ligne.
    expect(find.text('3 000 FCFA'), findsOneWidget);
    expect(find.textContaining('Montée à 1,2 km'), findsOneWidget);
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
    await fill('motdepasse');

    // Confirmation différente : refusée, rien n'est envoyé.
    await tester.enterText(find.byType(TextField), 'autrechose');
    await tester.pump();
    await tester.tap(find.text('Créer mon compte'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Les mots de passe ne correspondent pas.'), findsOneWidget);
    expect(sent, isNull);

    await tester.enterText(find.byType(TextField), 'motdepasse');
    await tester.pump();
    await tester.tap(find.text('Créer mon compte'));
    await tester.pump(const Duration(seconds: 1));

    expect(sent?.password, 'motdepasse');
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
        bottomNavigationBar: const TravelerBottomNavBar(current: ClientTab.home),
      ),
    );

    await tester.dragUntilVisible(find.text('Ligne 39'), find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    final last = tester.getRect(find.text('Ligne 39'));
    final bar = tester.getRect(find.byType(TravelerBottomNavBar));
    expect(last.bottom, lessThanOrEqualTo(bar.top + 0.01));
  });
}
