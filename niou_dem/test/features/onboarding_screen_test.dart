import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_passager/features/onboarding/screens/onboarding_screen.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // Petits écrans (émulateur, téléphones d'entrée de gamme) et police agrandie.
  for (final (size, textScale) in [
    (const Size(360, 640), 1.0),
    (const Size(411, 731), 1.0),
    (const Size(320, 568), 1.0),
    (const Size(360, 640), 1.3),
  ]) {
    testWidgets('the three slides fit ${size.width.toInt()}×${size.height.toInt()} at text ×$textScale',
        (tester) async {
      tester.view.physicalSize = size * 2.625;
      tester.view.devicePixelRatio = 2.625;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));
      for (var slide = 0; slide < 3; slide++) {
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull, reason: 'slide ${slide + 1}');
        if (slide < 2) await tester.tap(find.text('Suivant'));
      }
      expect(find.text('Commencer'), findsOneWidget);
    });
  }
}
