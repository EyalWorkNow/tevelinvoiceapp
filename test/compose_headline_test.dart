// A1 (QA 2026-11-16, owner/045): the Composer's big number is the document
// total – extra lines and the discount included – always with agorot.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/screens/compose/compose_state.dart';
import 'package:invoice/screens/compose/fields/amount_field.dart';
import 'package:invoice/ui/ds.dart';
import 'package:invoice/util/composer_config.dart';
import 'package:invoice/util/money.dart';

ComposeState _state({String business = 'OSEK_MURSHE', DocKind? kind}) =>
    ComposeState(
      kind: kind ?? DocKind.taxInvoiceReceipt,
      businessType: business,
      vatBasisPoints: 1800,
    );

Future<void> _pump(WidgetTester tester, ComposeState s) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he', 'IL'),
      supportedLocales: const [Locale('he', 'IL')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: SingleChildScrollView(child: AmountField(state: s)),
      ),
    ),
  );
  await tester.pump();
}

String _headline(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('compose-amount')))
    .textSpan!
    .toPlainText();

void main() {
  testWidgets('typing 350.9 shows ₪350.90 (agorot always), no caption', (
    tester,
  ) async {
    final s = _state()..amountText = '350.9';
    await _pump(tester, s);
    expect(_headline(tester), '₪350.90');
    expect(find.byKey(const Key('compose-amount-caption')), findsNothing);
    // The VAT line also carries agorot on every part.
    expect(
      find.textContaining('₪297.37 + ₪53.53', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('whole amount and a lone dot pad the agorot: ₪35.00, ₪35.00', (
    tester,
  ) async {
    final s = _state()..amountText = '35';
    await _pump(tester, s);
    expect(_headline(tester), '₪35.00');
    s.amountText = '35.';
    await _pump(tester, s);
    expect(_headline(tester), '₪35.00');
  });

  testWidgets(
    'owner/045: extra line + discount → headline = document total, caption names the main line',
    (tester) async {
      final s = _state()
        ..amountText = '350.9'
        ..discountText = '10';
      s.extraLines.add(ComposeLine(description: 'שעת עבודה', priceText: '120'));
      await _pump(tester, s);
      final total = s.totalMinor;
      expect(total, isNot(s.amountMinor));
      expect(_headline(tester), formatMoney(total));
      expect(_headline(tester), '₪460.89'); // exactly the screenshot's total
      final caption = tester
          .widget<Text>(find.byKey(const Key('compose-amount-caption')))
          .data!;
      expect(caption, contains('שורה ראשית'));
      expect(caption, contains('₪350.90'));
      expect(caption, contains('שורה נוספת'));
      expect(caption, contains('הנחה'));
      // The VAT line ends with the same total as the headline.
      expect(
        find.textContaining('= ${formatMoney(total)}', findRichText: true),
        findsOneWidget,
      );
    },
  );

  testWidgets('"לפני מע״מ": headline is the total incl. VAT, caption says so', (
    tester,
  ) async {
    final s = _state()
      ..amountText = '1000'
      ..inclusive = false;
    await _pump(tester, s);
    expect(_headline(tester), '₪1,180.00');
    expect(
      tester.widget<Text>(find.byKey(const Key('compose-amount-caption'))).data,
      contains('לפני מע״מ'),
    );
  });

  testWidgets('עוסק פטור: two lines → the sum, "כולל 2 שורות נוספות"', (
    tester,
  ) async {
    final s = _state(business: 'OSEK_PATUR', kind: DocKind.receipt)
      ..amountText = '200';
    s.extraLines
      ..add(ComposeLine(description: 'שיעור', priceText: '200'))
      ..add(
        ComposeLine(description: 'שיעור', quantityText: '2', priceText: '200'),
      );
    await _pump(tester, s);
    expect(_headline(tester), '₪800.00');
    expect(
      tester.widget<Text>(find.byKey(const Key('compose-amount-caption'))).data,
      contains('2 שורות נוספות'),
    );
  });
}
