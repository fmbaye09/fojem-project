import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_passager/core/widgets/search_bar_widget.dart';
import 'package:fojem_passager/core/widgets/section_header.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // Écran étroit (320 pt) et noms longs : les lignes rétrécissent au lieu de déborder.
  testWidgets('long city names and titles fit a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(320 * 2.625, 640 * 2.625);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              FojemSearchBar(
                departure: 'Ma position · Keur Massar Village',
                arrival: 'Saint-Louis, gare routière de Bango',
                onTap: () {},
              ),
              const SectionHeader(
                title: 'Trajets disponibles autour de vous aujourd’hui',
                actionLabel: 'Voir tout',
              ),
            ],
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });
}
