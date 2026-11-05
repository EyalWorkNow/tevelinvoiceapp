import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/ui/theme.dart';
import 'package:invoice/ui/widgets/amount_display.dart';
import 'package:invoice/ui/widgets/big_button.dart';
import 'package:invoice/ui/widgets/doc_row.dart';
import 'package:invoice/ui/widgets/status_pill.dart';
import 'package:invoice/util/status_map.dart';
import 'package:invoice/ui/widgets/keypad.dart';
import 'package:invoice/util/money.dart';

Widget app(Widget child, {Brightness brightness = Brightness.light}) => MaterialApp(
      locale: const Locale('he', 'IL'),
      supportedLocales: const [Locale('he', 'IL')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(brightness),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('keypad + amount display typing flow', (tester) async {
    var text = '';
    await tester.pumpWidget(app(StatefulBuilder(
      builder: (context, setState) => Column(children: [
        AmountDisplay(keypadText: text),
        Keypad(onKey: (k) => setState(() => text = keypadApply(text, k))),
      ]),
    )));
    for (final k in ['1', '1', '8', '0', '.', '5']) {
      await tester.tap(find.text(k));
      await tester.pump();
    }
    expect(text, '1180.5');
    await tester.pumpAndSettle();
    expect(find.text('₪1,180.5'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('מחק'));
    expect(text, '1180.');
    await tester.longPress(find.bySemanticsLabel('מחק'));
    expect(text, '');
  });

  testWidgets('RTL locale, buttons render in light + dark', (tester) async {
    for (final brightness in Brightness.values) {
      var taps = 0;
      await tester.pumpWidget(app(
        Column(children: [
          BigButton(label: 'הפק חשבונית', onPressed: () => taps++),
          const BigButton(label: 'טוען', onPressed: null, loading: true),
        ]),
        brightness: brightness,
      ));
      expect(Directionality.of(tester.element(find.byType(BigButton).first)), TextDirection.rtl);
      await tester.tap(find.text('הפק חשבונית'));
      expect(taps, 1);
    }
  });


  testWidgets('DocRow without an amount (read gating) draws and speaks no ₪', (tester) async {
    await tester.pumpWidget(app(DocRow(
      title: 'דנה כהן',
      subtitle: 'חשבונית מס · 51',
      amountMinor: null,
      status: StatusPill.doc(DocStatus.issued),
    )));
    expect(find.textContaining('₪'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('שקל')), findsNothing);
  });
}
