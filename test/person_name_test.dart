// owner/025: contact names were cut at the START ("…QA-C 612") in S2 – the
// phone took 2/3 of the row and a Latin name was laid out RTL.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/ui/theme.dart';
import 'package:invoice/ui/widgets/person_row.dart';

void main() {
  test('nameDirection: first strong letter decides', () {
    expect(nameDirection('QA-C 6123456789'), TextDirection.ltr);
    expect(nameDirection('123 דנה'), TextDirection.rtl);
    expect(nameDirection('דנה Levi'), TextDirection.rtl);
    expect(nameDirection('  '), TextDirection.rtl);
  });

  testWidgets('a Latin name keeps its start; the phone does not eat the row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: PersonRow(
              name: 'QA-C 6123456789 בדיקה ארוכה מאוד מאוד',
              subtitle: '0568562198',
              subtitleOnLeft: true,
            ),
          ),
        ),
      ),
    );
    final name = tester.widget<Text>(
      find.descendant(of: find.byType(PersonName), matching: find.byType(Text)),
    );
    expect(name.textDirection, TextDirection.ltr);
    final nameBox = tester.getSize(find.byType(PersonName));
    expect(nameBox.width, greaterThan(390 * 0.4));
  });
}
