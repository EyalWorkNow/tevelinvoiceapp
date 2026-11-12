// Squad D widget tests: E · הוצאות (review + list), SPEC-v2 §6.E, §7 J4, §4.4.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:invoice/router.dart';
import 'package:invoice/screens/expense/expenses_screen.dart';
import 'package:invoice/screens/people/sheets/s2_customer.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/ds.dart';
import 'package:invoice/util/labels/people_he.dart';

import 'fakes/fake_api.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

void main() {
  late FakeBackend backend;
  late Directory tmp;
  var taps = 0;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('expenses_test');
    AppCache.directoryProvider = () async => tmp;
  });

  setUp(() async {
    resetSession();
    await AppCache.clearAll();
    // OCR consent was given (QA 3.5); the consent test clears it.
    await AppCache.writeUserData('expense_ocr_consent', true);
    backend = FakeBackend()..install();
    taps = 0;
    pickContact = () async => null;
  });

  Future<void> flush(WidgetTester tester, [int rounds = 10]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    taps++;
    await tester.ensureVisible(f);
    await tester.tap(f);
    await flush(tester);
  }

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Preset preset = Preset.owner,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => signInAs(backend, preset));
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: messengerKey,
        locale: const Locale('he', 'IL'),
        supportedLocales: const [Locale('he', 'IL')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildTheme(Brightness.light),
        home: home,
      ),
    );
    await flush(tester);
  }

  /// An OCR-read expense (AT-19 fixture: OCR succeeded).
  Map<String, dynamic> read(String id) => expenseJson(
    id,
    supplierName: 'חברת החשמל',
    total: '11800',
    vat: '1800',
    date: '2026-10-12',
    extractionSource: 'OCR',
    filename: 'r.pdf',
  );

  testWidgets(
    'J4 tail: OCR-read card → ONE tap "אשר" → approved with the remembered category',
    (tester) async {
      final s = installPeopleFakes(backend, expenses: [read('e1')]);
      // Per business: the session signs in to b1 inside pump().
      await tester.runAsync(
        () =>
            AppCache.write('expense_last_category_b1', {'חברת החשמל': 'cat-2'}),
      );
      await pump(tester, const ExpensesScreen(expenseId: 'e1'));
      expect(find.byType(PrimaryButton), findsOneWidget);
      expect(find.text(ExpenseHe.approve), findsOneWidget);
      expect(find.text(ExpenseHe.progress(1, 1)), findsOneWidget);
      await tap(tester, find.byKey(const Key('expense-primary')));
      expect(taps, 1);
      expect(s.expense('e1')!['status'], 'APPROVED');
      expect(s.expense('e1')!['category_id'], 'cat-2');
      final body = backend.last('PATCH', '/expenses/:id/draft')!.body;
      expect(body['subtotal'], {'amountMinor': '10000', 'currency': 'ILS'});
      expect(find.text(ExpenseHe.allDone), findsOneWidget);
    },
  );

  testWidgets(
    'OCR missed amount/date: highlighted "חובה", nothing sent; then typed → approved',
    (tester) async {
      final s = installPeopleFakes(
        backend,
        expenses: [
          expenseJson(
            'e1',
            supplierName: 'דלק',
            extractionSource: 'OCR',
            filename: 'a.pdf',
          ),
        ],
      );
      await pump(tester, const ExpensesScreen());
      await tap(tester, find.byKey(const Key('expense-primary')));
      expect(find.text(ExpenseHe.required), findsNWidgets(2));
      expect(backend.calls('PATCH', '/expenses/:id/draft'), isEmpty);

      await tester.enterText(find.byKey(const Key('expense-amount')), '250');
      await flush(tester);
      // Date via the platform picker: set through the draft (no picker in tests).
      await tap(tester, find.byKey(const Key('expense-date')));
      await tap(
        tester,
        find.text('OK').evaluate().isEmpty
            ? find.text('אישור')
            : find.text('OK'),
      );
      await tap(tester, find.byKey(const Key('expense-primary')));
      expect(s.expense('e1')!['status'], 'APPROVED');
      expect(s.expense('e1')!['total_minor'], '25000');
    },
  );

  testWidgets(
    'employee: "שמור" (no approve call), no ⋯ "דחה"; sees only what this device captured',
    (tester) async {
      final s = installPeopleFakes(backend, expenses: [read('e2'), read('e1')]);
      await tester.runAsync(() => AppCache.write('expenses_mine_b1', ['e1']));
      await pump(tester, const ExpensesScreen(), preset: Preset.employee);
      expect(find.text(ExpenseHe.save), findsOneWidget);
      expect(find.byIcon(Iconsax.more), findsNothing);
      expect(
        find.text(ExpenseHe.progress(1, 1)),
        findsOneWidget,
        reason: 'e2 is someone else\'s',
      );
      await tap(tester, find.byKey(const Key('expense-primary')));
      expect(s.expense('e1')!['status'], 'READY_TO_APPROVE');
      expect(backend.calls('POST', '/expenses/:id/approve'), isEmpty);
    },
  );

  testWidgets('⋯ "דחה" → one required field "למה?" → reject with the reason', (
    tester,
  ) async {
    final s = installPeopleFakes(backend, expenses: [read('e1')]);
    await pump(tester, const ExpensesScreen());
    await tap(tester, find.byIcon(Iconsax.more));
    await tap(tester, find.text(ExpenseHe.reject));
    expect(find.text(ExpenseHe.rejectTitle), findsOneWidget);
    await tap(tester, find.byKey(const Key('expense-reject-confirm')));
    expect(find.text(ExpenseHe.rejectRequired), findsOneWidget);
    expect(backend.calls('POST', '/expenses/:id/reject'), isEmpty);
    await tester.enterText(
      find.byKey(const Key('expense-reject-reason')),
      'פרטי',
    );
    await tap(tester, find.byKey(const Key('expense-reject-confirm')));
    expect(backend.last('POST', '/expenses/:id/reject')!.body, {
      'reason': 'פרטי',
    });
    expect(s.expense('e1')!['status'], 'REJECTED');
  });

  testWidgets(
    'duplicate banner: "נראה כמו הוצאה מ-12.10.2026"; "לא" → undo → form',
    (tester) async {
      installPeopleFakes(
        backend,
        expenses: [
          expenseJson(
            'e2',
            status: 'DUPLICATE',
            duplicateOf: 'e1',
            filename: 'b.pdf',
          ),
          {...read('e1'), 'status': 'APPROVED'},
        ],
      );
      await pump(tester, const ExpensesScreen());
      expect(find.text(ExpenseHe.duplicateOf('12.10.2026')), findsOneWidget);
      expect(find.byType(PrimaryButton), findsNothing);
      await tap(tester, find.byKey(const Key('expense-dup-no')));
      expect(
        backend.calls('POST', '/expenses/:id/undo-duplicate'),
        hasLength(1),
      );
      expect(find.byKey(const Key('expense-duplicate')), findsNothing);
      expect(find.byType(PrimaryButton), findsOneWidget);
    },
  );

  testWidgets(
    '"דלג" moves to the next card and keeps the skipped one for later',
    (tester) async {
      installPeopleFakes(backend, expenses: [read('e2'), read('e1')]);
      await pump(tester, const ExpensesScreen());
      expect(find.text(ExpenseHe.progress(1, 2)), findsOneWidget);
      await tap(tester, find.byKey(const Key('expense-skip')));
      expect(find.text(ExpenseHe.progress(1, 2)), findsOneWidget);
      await tap(tester, find.byKey(const Key('expense-primary')));
      expect(find.text(ExpenseHe.progress(2, 2)), findsOneWidget);
    },
  );

  testWidgets(
    'supplier field opens S2 (supplier mode); chosen supplier fills the draft',
    (tester) async {
      final s = installPeopleFakes(
        backend,
        expenses: [
          expenseJson(
            'e1',
            total: '5000',
            date: '2026-10-01',
            filename: 'x.pdf',
            extractionSource: 'OCR',
          ),
        ],
        suppliers: [
          {
            'id': 's1',
            'name': 'דלק',
            'tax_id': '514713288',
            'email': null,
            'phone': null,
            'archived_at': null,
          },
        ],
      );
      await pump(tester, const ExpensesScreen());
      await tap(tester, find.byKey(const Key('expense-supplier')));
      await tap(tester, find.byKey(const Key('s2-row-s1')));
      await tester
          .pumpAndSettle(); // Wait for the full-page picker to finish popping.
      await tap(tester, find.byKey(const Key('expense-primary')));
      expect(
        backend.last('PATCH', '/expenses/:id/draft')!.body['supplierId'],
        's1',
      );
      expect(
        backend.last('PATCH', '/expenses/:id/draft')!.body['supplierTaxId'],
        '514713288',
      );
      expect(s.expense('e1')!['status'], 'APPROVED');
    },
  );

  testWidgets('nothing read yet: OCR runs once; unavailable → manual form', (
    tester,
  ) async {
    installPeopleFakes(
      backend,
      expenses: [expenseJson('e1', filename: 'x.pdf')],
    );
    await pump(tester, const ExpensesScreen());
    expect(backend.calls('POST', '/expenses/:id/extract'), hasLength(1));
    expect(find.byKey(const Key('expense-amount')), findsOneWidget);
  });

  testWidgets(
    'QA 3.5: a failed OCR read is not re-run when the screen opens again',
    (tester) async {
      installPeopleFakes(
        backend,
        expenses: [expenseJson('e1', filename: 'x.pdf')],
      );
      await pump(tester, const ExpensesScreen());
      await pump(tester, const ExpensesScreen(key: ValueKey('reopened')));
      expect(backend.calls('POST', '/expenses/:id/extract'), hasLength(1));
    },
  );

  testWidgets(
    'QA 3.5: asks before the receipt goes to OCR; "הזנה ידנית" sends nothing',
    (tester) async {
      await tester.runAsync(AppCache.clearAll);
      installPeopleFakes(
        backend,
        expenses: [expenseJson('e1', filename: 'x.pdf')],
      );
      await pump(tester, const ExpensesScreen());
      expect(find.text(ExpenseOcrHe.consentTitle), findsOneWidget);
      await tap(tester, find.byKey(const Key('expense-ocr-manual')));
      expect(backend.calls('POST', '/expenses/:id/extract'), isEmpty);
      expect(find.byKey(const Key('expense-amount')), findsOneWidget);
    },
  );

  testWidgets(
    'AT-19: opens on the just-captured expense among older pending ones; OCR result shows '
    'even when the first re-read of the inbox fails',
    (tester) async {
      final s = installPeopleFakes(
        backend,
        expenses: [
          expenseJson('new', filename: 'n.pdf'),
          expenseJson('old2', filename: 'a.pdf'),
          expenseJson('old1', filename: 'b.pdf'),
        ],
      );
      backend.on('POST', '/expenses/:id/extract', (r) {
        s.expense(r.params['id']!)!
          ..['supplier_name'] = 'ספק קבלה'
          ..['total_minor'] = '23600'
          ..['status'] = 'READY_TO_APPROVE'
          ..['extraction_source'] = 'OCR';
        return FakeResponse(200, {'status': 'EXTRACTED'});
      });
      var inboxCalls = 0;
      backend.on('GET', '/expenses/inbox', (_) {
        inboxCalls++;
        if (inboxCalls == 2) throw http.ClientException('connection closed');
        return FakeResponse(200, {'expenses': s.expenses});
      });
      await pump(
        tester,
        const ExpensesScreen(
          expenseId: 'new',
          pollEvery: Duration(milliseconds: 30),
        ),
      );
      await flush(tester);
      expect(
        backend
            .calls('POST', '/expenses/:id/extract')
            .map((c) => c.params['id']),
        ['new'],
      );
      expect(inboxCalls, greaterThanOrEqualTo(3));
      expect(find.text('ספק קבלה'), findsOneWidget);
      expect(find.text(ExpenseHe.progress(1, 3)), findsOneWidget);
      expect(find.text(ExpenseHe.approve), findsOneWidget);
    },
  );

  testWidgets('still processing → "קורא את הקבלה…", polls until read', (
    tester,
  ) async {
    final s = installPeopleFakes(
      backend,
      expenses: [expenseJson('e1', status: 'EXTRACTING', filename: 'x.pdf')],
    );
    await pump(
      tester,
      const ExpensesScreen(pollEvery: Duration(milliseconds: 50)),
    );
    expect(find.text(ExpenseHe.reading), findsOneWidget);
    s.expenses
      ..clear()
      ..add(read('e1'));
    await tester.pump(const Duration(milliseconds: 60));
    await flush(tester);
    await flush(tester);
    expect(find.text(ExpenseHe.reading), findsNothing);
    expect(find.text('חברת החשמל'), findsOneWidget);
  });

  testWidgets(
    'list: "כל ההוצאות" shows every row with its status word; tap a reviewable one',
    (tester) async {
      installPeopleFakes(
        backend,
        expenses: [
          read('e2'),
          {...read('e1'), 'status': 'APPROVED'},
        ],
      );
      await pump(tester, const ExpensesScreen());
      await tap(tester, find.byKey(const Key('expense-mode')));
      expect(find.byKey(const Key('expense-row-e1')), findsOneWidget);
      expect(
        find.textContaining(ExpenseHe.statusLabels['APPROVED']!),
        findsOneWidget,
      );
      await tap(tester, find.byKey(const Key('expense-row-e2')));
      expect(find.byType(PrimaryButton), findsOneWidget);
    },
  );

  testWidgets('empty → "אין הוצאות לבדיקה ✓"; error → retry', (tester) async {
    installPeopleFakes(backend);
    backend.error('GET', '/expenses/inbox', 500, 'INTERNAL');
    await pump(tester, const ExpensesScreen());
    expect(find.text('נסה שוב'), findsOneWidget);
    backend.json('GET', '/expenses/inbox', {'expenses': []});
    await tap(tester, find.text('נסה שוב'));
    expect(find.text(ExpenseHe.allDone), findsOneWidget);
  });

  testWidgets(
    'BE-44 list: server search; approved row → edit "שמור" → PATCH; ⋯ "מחק" → DELETE',
    (tester) async {
      installPeopleFakes(
        backend,
        be44: true,
        expenses: [
          {...read('e1'), 'status': 'APPROVED', 'created_by': 'u-me'},
          {...read('e2'), 'supplier_name': 'דלק', 'status': 'APPROVED'},
        ],
      );
      await pump(tester, const ExpensesScreen());
      await tap(tester, find.byKey(const Key('expense-mode')));
      expect(find.byKey(const Key('expense-row-e2')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('expense-search')), 'חשמל');
      await tester.pump(const Duration(milliseconds: 350));
      await flush(tester);
      expect(backend.last('GET', '/expenses')!.query['q'], 'חשמל');
      expect(find.byKey(const Key('expense-row-e2')), findsNothing);

      await tap(tester, find.byKey(const Key('expense-row-e1')));
      expect(find.text(ExpenseHe.editTitle), findsOneWidget);
      expect(find.byType(PrimaryButton), findsOneWidget);
      expect(find.text(ExpenseHe.save), findsOneWidget);
      expect(find.byKey(const Key('expense-skip')), findsNothing);
      await tester.enterText(find.byKey(const Key('expense-amount')), '120');
      await tap(tester, find.byKey(const Key('expense-primary')));
      expect(backend.last('PATCH', '/expenses/:id')!.body['total'], {
        'amountMinor': '12000',
        'currency': 'ILS',
      });
      expect(backend.calls('POST', '/expenses/:id/approve'), isEmpty);
      expect(find.text(ExpenseHe.updated), findsOneWidget);

      await tap(tester, find.byKey(const Key('expense-row-e1')));
      await tap(tester, find.byIcon(Iconsax.more));
      await tap(tester, find.text(ExpenseHe.delete));
      await tap(tester, find.byKey(const Key('expense-delete-confirm')));
      expect(backend.calls('DELETE', '/expenses/:id'), hasLength(1));
      expect(find.text(ExpenseHe.deleted), findsOneWidget);
    },
  );

  testWidgets(
    'no BE-44: the list searches the inbox on the device; approved rows stay read-only',
    (tester) async {
      installPeopleFakes(
        backend,
        expenses: [
          {...read('e1'), 'status': 'APPROVED'},
          {...read('e2'), 'supplier_name': 'דלק'},
        ],
      );
      await pump(tester, const ExpensesScreen());
      await tap(tester, find.byKey(const Key('expense-mode')));
      await tester.enterText(find.byKey(const Key('expense-search')), 'דלק');
      await flush(tester);
      expect(find.byKey(const Key('expense-row-e1')), findsNothing);
      expect(find.byKey(const Key('expense-row-e2')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('expense-search')), '');
      await flush(tester);
      await tap(tester, find.byKey(const Key('expense-row-e1')));
      expect(find.text(ExpenseHe.editTitle), findsNothing);
    },
  );
}
