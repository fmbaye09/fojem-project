import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_passager/core/widgets/option_sheet.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('fifteen seats fit a phone screen and open on the current choice', (tester) async {
    // Pixel 7 en points logiques.
    tester.view.physicalSize = const Size(412 * 2.625, 892 * 2.625);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    int? picked;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => picked = await showOptionSheet<int>(
              context,
              title: 'Places disponibles',
              selected: 12,
              options: [for (var i = 1; i <= 15; i++) (i, '$i place${i > 1 ? 's' : ''}')],
            ),
            child: const Text('Places'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Places'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('12 places'), findsOneWidget);
    await tester.tap(find.text('12 places'));
    await tester.pumpAndSettle();
    expect(picked, 12);
  });
}
