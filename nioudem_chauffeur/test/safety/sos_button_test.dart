import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_chauffeur/core/widgets/sos.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<int Function()> pumpButton(WidgetTester tester) async {
    var triggered = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: SosButton(onTriggered: () => triggered++))),
    ));
    return () => triggered;
  }

  testWidgets('a quick tap does not trigger the SOS', (tester) async {
    final triggered = await pumpButton(tester);
    await tester.tap(find.text('SOS'));
    await tester.pump(const Duration(seconds: 3));
    expect(triggered(), 0);
  });

  testWidgets('holding the button for 2 seconds triggers the SOS once', (tester) async {
    final triggered = await pumpButton(tester);
    final gesture = await tester.startGesture(tester.getCenter(find.text('SOS')));
    Future<void> hold(int ms) async {
      for (var t = 0; t < ms; t += 100) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await hold(1500);
    expect(triggered(), 0);
    await hold(800);
    expect(triggered(), 1);
    await gesture.up();
    await tester.pump(const Duration(seconds: 1));
    expect(triggered(), 1);
  });
}
