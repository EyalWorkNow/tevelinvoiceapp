// S1 (＋) and S3 (פרטים נוספים) widget tests (§6 sheets, §4.4, §4.7).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/screens/compose/compose_state.dart';
import 'package:invoice/screens/compose/sheets/s1_create.dart';
import 'package:invoice/screens/compose/sheets/s3_more.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/ds.dart';
import 'package:invoice/util/composer_config.dart';
import 'package:invoice/util/labels/labels.dart';

import 'fakes/fake_api.dart';

void main() {
  late FakeBackend backend;

  setUpAll(() async {
    final tmp = await Directory.systemTemp.createTemp('compose_sheets_test');
    AppCache.directoryProvider = () async => tmp;
  });

  setUp(() {
    resetSession();
    backend = FakeBackend()..install();
  });

  Future<void> host(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('he', 'IL'),
      supportedLocales: const [Locale('he', 'IL')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ));
    await tester.pump();
  }

  group('S1', () {
    testWidgets('owner מורשה: quote · expense · customer · more → ≤6 kinds + "המשך במחשב"', (tester) async {
      await tester.runAsync(() => signInAs(backend, Preset.owner));
      await host(tester, const CreateSheet());
      for (final k in ['s1-quote', 's1-expense', 's1-customer', 's1-more']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
      await tester.tap(find.byKey(const Key('s1-more')));
      await tester.pump();
      for (final code in [305, 320, 300, 400, 100, 500]) {
        expect(find.byKey(Key('s1-kind-$code')), findsOneWidget, reason: '$code');
      }
      expect(find.byKey(const Key('s1-kind-330')), findsNothing);
      expect(find.text(ComposeHe.moreOnComputer), findsOneWidget);
    });

    testWidgets('פטור: no VAT types; עמותה + §46: 405', (tester) async {
      await tester.runAsync(() => signInAs(backend, Preset.owner, businessType: 'OSEK_PATUR'));
      await host(tester, const CreateSheet());
      await tester.tap(find.byKey(const Key('s1-more')));
      await tester.pump();
      expect(find.byKey(const Key('s1-kind-305')), findsNothing);
      expect(find.byKey(const Key('s1-kind-320')), findsNothing);
      expect(find.byKey(const Key('s1-kind-300')), findsOneWidget);
      expect(find.byKey(const Key('s1-kind-405')), findsNothing);

      resetSession();
      await tester.runAsync(() => signInAs(backend, Preset.owner,
          businessType: 'NONPROFIT',
          profile: profileJson(businessType: 'NONPROFIT', section46ApprovalNumber: '46-123')));
      await host(tester, const CreateSheet(key: Key('again')));
      await tester.tap(find.byKey(const Key('s1-more')));
      await tester.pump();
      expect(find.byKey(const Key('s1-kind-405')), findsOneWidget);
    });

    for (final p in [Preset.employee, Preset.employeeIssuer]) {
      testWidgets('$p: quote · expense · customer only; no "עוד" (§4.4)', (tester) async {
        await tester.runAsync(() => signInAs(backend, p));
        await host(tester, const CreateSheet());
        for (final k in ['s1-quote', 's1-expense', 's1-customer']) {
          expect(find.byKey(Key(k)), findsOneWidget, reason: k);
        }
        expect(find.byKey(const Key('s1-more')), findsNothing);
        expect(find.byKey(const Key('s1-desktop')), findsNothing);
      });
    }

    testWidgets('viewer: no tile at all (hidden, not disabled)', (tester) async {
      await tester.runAsync(() => signInAs(backend, Preset.viewer));
      await host(tester, const CreateSheet());
      expect(find.byType(ListTile), findsNothing);
    });
  });

  group('S3', () {
    ComposeState st(DocKind k, String bt) =>
        ComposeState(kind: k, businessType: bt, vatBasisPoints: 1800)..amountText = '100';

    testWidgets('VAT business: lines, discount, VAT, type switch, allocation request', (tester) async {
      await tester.runAsync(() => signInAs(backend, Preset.owner));
      final s = st(DocKind.taxInvoice, 'OSEK_MURSHE');
      await host(tester, MoreDetailsSheet(state: s, kinds: const [DocKind.taxInvoice, DocKind.transactionInvoice]));
      expect(find.byKey(const Key('s3-vat')), findsOneWidget);
      expect(find.byKey(const Key('s3-allocation')), findsOneWidget);
      await tester.tap(find.text(ComposeHe.vatNone));
      await tester.pump();
      expect(s.vatNone, isTrue);
      await tester.tap(find.text(kindLabels[DocKind.transactionInvoice]!));
      await tester.pump();
      expect(s.kind, DocKind.transactionInvoice, reason: 'AT-14');
      expect(find.byKey(const Key('s3-allocation')), findsNothing);
      await tester.tap(find.byKey(const Key('s3-add-line')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('s3-line-0-description')), 'חלקים');
      await tester.enterText(find.byKey(const Key('s3-line-0-price')), '50');
      await tester.pump();
      expect(s.requestLines, hasLength(2));
      expect(find.byType(PrimaryButton), findsOneWidget);
    });

    testWidgets('exempt: no VAT row, no allocation row, no "מע״מ"', (tester) async {
      await tester.runAsync(() => signInAs(backend, Preset.owner, businessType: 'OSEK_PATUR'));
      await host(tester, MoreDetailsSheet(state: st(DocKind.transactionInvoice, 'OSEK_PATUR')));
      expect(find.byKey(const Key('s3-vat')), findsNothing);
      expect(find.byKey(const Key('s3-allocation')), findsNothing);
      expect(find.text('מע״מ'), findsNothing);
    });

    testWidgets('BE-07 rows: note + due date on 305; note only on 320; none on a receipt', (tester) async {
      await tester.runAsync(() => signInAs(backend, Preset.owner));
      await host(tester, MoreDetailsSheet(state: st(DocKind.taxInvoice, 'OSEK_MURSHE')..customerTerms = 'EOM'));
      expect(find.byKey(const Key('s3-notes')), findsOneWidget);
      expect(find.byKey(const Key('s3-due-date')), findsOneWidget);
      expect(find.text(formatDateHe(dueDateForTerms('EOM', DateTime.now()))), findsOneWidget);
      await host(tester, MoreDetailsSheet(state: st(DocKind.taxInvoiceReceipt, 'OSEK_MURSHE')));
      expect(find.byKey(const Key('s3-notes')), findsOneWidget);
      expect(find.byKey(const Key('s3-due-date')), findsNothing);
      await host(tester, MoreDetailsSheet(state: st(DocKind.receipt, 'OSEK_PATUR')));
      expect(find.byKey(const Key('s3-notes')), findsNothing);
    });

    testWidgets('VAT "לפי שורה": each line gets its own "ללא מע״מ"', (tester) async {
      await tester.runAsync(() => signInAs(backend, Preset.owner));
      final s = st(DocKind.taxInvoice, 'OSEK_MURSHE')..extraLines.add(ComposeLine(description: 'אגרה', priceText: '50'));
      await host(tester, MoreDetailsSheet(state: s));
      expect(find.byKey(const Key('s3-line-0-vat-none')), findsNothing);
      await tester.tap(find.text(ComposeHe.vatPerLine));
      await tester.pump();
      expect(s.vatPerLine, isTrue);
      await tester.tap(find.byKey(const Key('s3-line-0-vat-none')));
      await tester.pump();
      expect(s.requestLines[1]['taxRateBasisPoints'], 0);
      expect(s.requestLines[0]['taxRateBasisPoints'], 1800);
    });

    testWidgets('BE-15 catalog: typing suggests an item; choosing fills price + itemId', (tester) async {
      backend.json('GET', '/items', {
        'items': [
          {'id': 'i1', 'name': 'עיצוב לוגו', 'item_type': 'SERVICE', 'default_unit_price_minor': '100000',
            'currency': 'ILS', 'is_active': true}
        ]
      });
      await tester.runAsync(() => signInAs(backend, Preset.owner));
      final s = st(DocKind.taxInvoice, 'OSEK_MURSHE')..extraLines.add(ComposeLine());
      await host(tester, MoreDetailsSheet(state: s));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      expect(backend.calls('GET', '/items'), hasLength(1));
      await tester.enterText(find.byKey(const Key('s3-line-0-description')), 'לוגו');
      await tester.pumpAndSettle();
      await tester.tap(find.text('עיצוב לוגו').last);
      await tester.pumpAndSettle();
      final l = s.extraLines.single;
      expect((l.description, l.itemId, l.priceText), ('עיצוב לוגו', 'i1', '1180'),
          reason: 'net 1,000 shown with VAT (amounts include VAT by default)');
      expect(s.requestLines[1]['unitPriceMinor'], '100000');
      expect(s.requestLines[1]['itemId'], 'i1');
      expect(find.byKey(const Key('s3-line-0-save-item')), findsNothing);
    });

    testWidgets('"לשמור כפריט?" on a new valid line → POST /items (net price) → itemId', (tester) async {
      backend
        ..json('GET', '/items', {'items': []})
        ..json('POST', '/items', {'id': 'i9'}, status: 201);
      await tester.runAsync(() => signInAs(backend, Preset.owner));
      final s = st(DocKind.taxInvoice, 'OSEK_MURSHE')
        ..extraLines.add(ComposeLine(description: 'התקנה', priceText: '118'));
      await host(tester, MoreDetailsSheet(state: s));
      await tester.tap(find.byKey(const Key('s3-line-0-save-item')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(backend.last('POST', '/items')!.body['defaultUnitPriceMinor'], '10000');
      expect(s.extraLines.single.itemId, 'i9');
      expect(find.text(ComposeHe.savedAsItem), findsOneWidget);
    });

    testWidgets('quote: valid-until row, no type row', (tester) async {
      await tester.runAsync(() => signInAs(backend, Preset.owner));
      await host(tester, MoreDetailsSheet(state: st(DocKind.quote, 'OSEK_MURSHE')));
      expect(find.byKey(const Key('s3-valid-until')), findsOneWidget);
      expect(find.byKey(const Key('s3-type')), findsNothing);
    });
  });
}
