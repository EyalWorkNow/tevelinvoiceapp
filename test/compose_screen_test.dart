// C · Composer widget tests (§6.C, §7 J1/J2/J5, AT-10/10c/11/12/15/16/17/17b/41/43/98).
// Taps are counted per F3.1: the intent tap on H (+1, the test opens C
// directly), the S2 customer circle (squad D's sheet; simulated by
// [pickCustomer] = 1 tap) and every tester.tap below.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/api/signing_api.dart' as signing;
import 'package:invoice/router.dart';
import 'package:invoice/screens/compose/compose_screen.dart';
import 'package:invoice/screens/compose/compose_memory.dart';
import 'package:invoice/screens/compose/compose_submit.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/session.dart';
import 'package:invoice/ui/ds.dart';
import 'package:invoice/util/composer_config.dart' show dueDateForTerms;
import 'package:invoice/util/labels/labels.dart';

import 'fakes/fake_api.dart';

const dana = Customer(id: 'c1', name: 'דנה', phone: '050-1234567');
const walkIn = Customer(
  id: 'c2',
  name: 'לקוח מזדמן',
  vatDealerStatus: 'PRIVATE',
);
const ron = Customer(
  id: 'c3',
  name: 'רון בע״מ',
  taxId: '514000002',
  vatDealerStatus: 'UNKNOWN',
);

void main() {
  late FakeBackend backend;
  late IssueFake fake;
  late FakeLauncher launcher;
  late Directory tmp;
  late int taps;
  final routes = <String>[];

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('compose_screen_test');
    AppCache.directoryProvider = () async => tmp;
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    signing.signingBiometric = (_) async => true;
    resetSession();
    backend = FakeBackend()..install();
    fake = installIssueFakes(backend);
    launcher = FakeLauncher()..install();
    shareText = (_) async {};
    Future<void> stub(BuildContext c, String name) =>
        Navigator.of(c).pushReplacement(
          MaterialPageRoute<void>(
            settings: RouteSettings(name: name),
            builder: (_) => Scaffold(body: Text(name)),
          ),
        );
    openIssuedDocument = (c, id) => stub(c, '/doc/$id');
    openIssuedQuote = (c, id) => stub(c, '/quote/$id');
    openShareAfterIssue = (c, id) async => routes.add('S6 $id');
    taps = 0;
    routes.clear();
    await AppCache.clearAll();
  });

  tearDown(FakeLauncher.uninstall);

  /// Lets real IO (AppCache files) and the fake HTTP finish.
  Future<void> flush(WidgetTester tester) async {
    var quiet = 0;
    for (var i = 0; i < 400 && quiet < 30; i++) {
      final before = backend.requests.length;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      quiet = backend.requests.length == before ? quiet + 1 : 0;
    }
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    taps++;
    await tester.tap(f);
    await flush(tester);
  }

  Future<void> type(WidgetTester tester, String digits) async {
    for (var i = 0; i < 10 && find.byType(Keypad).evaluate().isEmpty; i++) {
      await flush(tester);
    }
    for (final d in digits.split('')) {
      await tester.tap(
        find.descendant(of: find.byType(Keypad), matching: find.text(d)).first,
      );
      await tester.pump();
    }
    // The primary ignores taps for 400ms after it appears (U1).
    await tester.pump(const Duration(milliseconds: 450));
  }

  Future<void> open(
    WidgetTester tester, {
    required String intent,
    Preset preset = Preset.owner,
    String businessType = 'OSEK_MURSHE',
    Customer? customer = dana,
    Map<String, dynamic>? approvalPolicy,
    bool offline = false,
    String? fromDocId,
    String? fromQuoteId,
    double textScale = 1,
    Size size = const Size(1170, 2532),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(
      () => signInAs(
        backend,
        preset,
        businessType: businessType,
        approvalPolicy: approvalPolicy,
      ),
    );
    session.offline = offline;
    pickCustomer = (_) async {
      taps++; // the S2 circle
      return customer;
    };
    pickSupplier = pickCustomer;
    pickPaymentCustomer = pickCustomer;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: messengerKey,
        navigatorObservers: [_Names(routes)],
        locale: const Locale('he', 'IL'),
        supportedLocales: const [Locale('he', 'IL')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => openCompose(
                c,
                intent: intent,
                fromDocId: fromDocId,
                fromQuoteId: fromQuoteId,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    taps++; // the intent button on H
    await tester.tap(find.text('open'));
    await flush(tester);
  }

  Finder primary() => find.byKey(const Key('compose-primary'));
  String primaryLabel(WidgetTester tester) =>
      (tester.widget(primary()) as PrimaryButton).label;

  testWidgets(
    'AT-10 J1 מורשה: 3 taps → 320 FINALIZED, payment allocated, wa.me/972…/d/',
    (tester) async {
      await open(tester, intent: 'PAID');
      await type(tester, '1180');
      expect(find.byKey(const Key('vat-breakdown')), findsOneWidget);
      expect(
        find.text('חשבונית מס-קבלה'),
        findsNothing,
        reason: 'F1: no type name before issuing',
      );
      expect(primaryLabel(tester), ComposeHe.issueAndWhatsApp);
      await tap(tester, primary());
      expect(taps, 3);
      final created = backend.last('POST', '/documents')!.body;
      expect(created['documentType'], 'TAX_INVOICE_RECEIPT');
      expect(created['lines'][0]['unitPriceMinor'], '100000');
      expect(created['lines'][0]['description'], ComposeHe.defaultDescription);
      expect(
        backend.last('POST', '/documents/:id/finalize')!.idempotencyKey,
        isNotEmpty,
      );
      expect(
        backend
            .last('POST', '/documents/:id/finalize')!
            .body
            .containsKey('requestAllocation'),
        isFalse,
      );
      expect(backend.last('POST', '/payments')!.body['method'], 'CASH');
      expect(
        backend.last('POST', '/documents/:id/payments')!.body['amountMinor'],
        '118000',
      );
      expect(
        launcher.last.toString(),
        startsWith('https://wa.me/972501234567'),
      );
      expect(Uri.decodeComponent(launcher.last.toString()), contains('/d/'));
      expect(routes.last, '/doc/d1');
    },
  );

  testWidgets(
    'missing delivery channel opens recipient options without requiring WhatsApp',
    (tester) async {
      backend.json('POST', '/documents/:id/dispatch', {
        'status': 'MANUAL_REQUIRED',
        'channel': 'MANUAL',
        'transport': 'manual',
      });
      await open(tester, intent: 'PAID');
      await type(tester, '1180');
      await tap(tester, primary());
      expect(routes, containsAll(['/doc/d1', 'S6 d1']));
      expect(launcher.opened, isEmpty);
      expect(
        find.text('המסמך מוכן לקבלה בסריקה, בטלפון או במייל'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'AT-11 J1 פטור: 3 taps → receipt 400, no VAT component and no "מע״מ" anywhere',
    (tester) async {
      await open(tester, intent: 'PAID', businessType: 'OSEK_PATUR');
      await type(tester, '350');
      expect(find.byKey(const Key('vat-breakdown')), findsNothing);
      expect(find.byKey(const Key('vat-toggle')), findsNothing);
      expect(find.text('מע״מ'), findsNothing);
      await tap(tester, primary());
      expect(taps, 3);
      expect(backend.calls('POST', '/documents'), isEmpty);
      expect(backend.last('POST', '/payments')!.body['amountMinor'], '35000');
      expect(backend.calls('POST', '/receipts'), hasLength(1));
      expect(launcher.last.toString(), startsWith('https://wa.me/972'));
    },
  );

  testWidgets('AT-12 J2: REQUEST → 305 in 3 taps, link contains /d/', (
    tester,
  ) async {
    await open(tester, intent: 'REQUEST');
    await type(tester, '590');
    await tap(tester, primary());
    expect(taps, 3);
    expect(
      backend.last('POST', '/documents')!.body['documentType'],
      'TAX_INVOICE',
    );
    expect(backend.calls('POST', '/payments'), isEmpty);
    expect(Uri.decodeComponent(launcher.last.toString()), contains('/d/'));
  });

  testWidgets('tap on the VAT line toggles כולל ↔ לפני מע״מ', (tester) async {
    await open(tester, intent: 'REQUEST');
    await type(tester, '1000');
    expect(find.text(vatModeLabel(true)), findsOneWidget);
    await tester.tap(find.byKey(const Key('vat-breakdown')));
    await tester.pump();
    expect(find.text(vatModeLabel(false)), findsOneWidget);
    await tap(tester, primary());
    expect(
      backend.last('POST', '/documents')!.body['lines'][0]['unitPriceMinor'],
      '100000',
    );
  });

  testWidgets(
    'AT-15 defaults: last description for the customer, last payment method',
    (tester) async {
      await tester.runAsync(() async {
        await AppCache.write('nd_desc_by_customer_b1', {'c1': 'תיקון דוד'});
        await AppCache.write('nd_last_method_b1', 'BANK_TRANSFER');
      });
      await open(tester, intent: 'PAID');
      await type(tester, '100');
      expect(find.text('תיקון דוד'), findsOneWidget);
      final chips = tester.widget<ChipRow<String>>(
        find.byKey(const Key('compose-methods')),
      );
      expect(chips.selected, 'BANK_TRANSFER');
    },
  );

  testWidgets('AT-16: ≥ ₪50,000 → one confirmation dialog', (tester) async {
    await open(tester, intent: 'REQUEST');
    await type(tester, '50000');
    await tap(tester, primary());
    expect(find.byKey(const Key('big-amount-dialog')), findsOneWidget);
    expect(backend.calls('POST', '/documents'), isEmpty);
    await tap(tester, find.text(CommonHe.issue).last);
    expect(backend.calls('POST', '/documents'), hasLength(1));
  });

  testWidgets(
    'AT-17: walk-in, 320 ₪6,000 before VAT → no block, no requestAllocation',
    (tester) async {
      await open(tester, intent: 'PAID', customer: walkIn);
      await type(tester, '7080');
      expect(primaryLabel(tester), ComposeHe.issue, reason: 'no phone → "הפק"');
      await tap(tester, primary());
      expect(backend.last('POST', '/documents/:id/finalize')!.body, {
        'scopeKey': 'default',
      });
      expect(
        routes,
        containsAll(['/doc/d1', 'S6 d1']),
        reason: '"הפק" → D, where S6 opens',
      );
    },
  );

  testWidgets('AT-17b: unknown dealer status → "עוסק מורשה?" → כן → finalize', (
    tester,
  ) async {
    fake.evaluateAnswers.add({
      'state': 'REQUIRES_USER_INPUT',
      'evaluation': {'reasonCode': 'CUSTOMER_VAT_STATUS_UNKNOWN'},
    });
    await open(tester, intent: 'REQUEST', customer: ron);
    await type(tester, '7080');
    await tap(tester, primary());
    expect(find.byKey(const Key('vat-dealer-dialog')), findsOneWidget);
    expect(find.text(ComposeHe.vatDealerQuestion('רון בע״מ')), findsOneWidget);
    await tap(tester, find.byKey(const Key('vat-dealer-yes')));
    expect(
      backend.last('PATCH', '/customers/:id')!.body['vatDealerStatus'],
      'AUTHORIZED_DEALER',
    );
    expect(backend.calls('POST', '/documents/:id/finalize'), hasLength(1));
  });

  testWidgets('AT-41: employee → "שלח לאישור" → POST /submit, never finalize', (
    tester,
  ) async {
    await open(tester, intent: 'PAID', preset: Preset.employee);
    await type(tester, '100');
    expect(primaryLabel(tester), ComposeHe.submit);
    await tap(tester, primary());
    expect(backend.calls('POST', '/documents/:id/submit'), hasLength(1));
    expect(backend.calls('POST', '/documents/:id/finalize'), isEmpty);
    expect(launcher.opened, isEmpty);
  });

  testWidgets('AT-43: threshold ₪5,000 incl. VAT, `>=`, note line', (
    tester,
  ) async {
    await open(
      tester,
      intent: 'REQUEST',
      approvalPolicy: {
        'mode': 'THRESHOLD',
        'thresholdMinor': '500000',
        'includesVat': true,
        'selfApprovalAllowed': false,
        'otherApproverExists': true,
      },
    );
    await type(tester, '4999.99');
    expect(primaryLabel(tester), ComposeHe.issueAndWhatsApp);
    for (var i = 0; i < 7; i++) {
      await tester.tap(
        find
            .descendant(
              of: find.byType(Keypad),
              matching: find.bySemanticsLabel('מחק'),
            )
            .first,
      );
      await tester.pump();
    }
    await type(tester, '5000');
    expect(primaryLabel(tester), ComposeHe.submit);
    expect(find.text(approvalNote(BigInt.from(500000))), findsOneWidget);
  });

  testWidgets('AT-98 offline: the primary shows "אין חיבור"', (tester) async {
    await open(tester, intent: 'REQUEST', offline: true);
    await type(tester, '100');
    final b = tester.widget<PrimaryButton>(primary());
    expect(b.offline, isTrue);
    expect(find.text(CommonHe.offlineButton), findsOneWidget);
  });

  testWidgets('amount 0 → no primary button (F2/F5: absent, not grey)', (
    tester,
  ) async {
    await open(tester, intent: 'REQUEST');
    expect(primary(), findsNothing);
    expect(find.byKey(const Key('compose-description')), findsNothing);
  });

  testWidgets(
    'AT-10c J1 first time: signing LOCKED → passphrase dialog → "שמור עם Face ID" ≤5 taps',
    (tester) async {
      fake.artifactSigning = 'LOCKED';
      await open(tester, intent: 'PAID');
      await type(tester, '1180');
      await tap(tester, primary());
      // A quiet HTTP log does not mean the disk-backed issue flow has finished.
      // Wait for its actual UI result before asserting the signing contract.
      for (
        var i = 0;
        i < 10 && find.byKey(const Key('signing-dialog')).evaluate().isEmpty;
        i++
      ) {
        await flush(tester);
      }
      expect(find.byKey(const Key('signing-dialog')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('signing-passphrase')),
        'secret',
      );
      await tap(tester, find.byKey(const Key('signing-save')));
      taps++; // the Face ID confirmation of "שמור עם Face ID" (signingBiometric)
      expect(taps, lessThanOrEqualTo(5));
      expect(backend.last('POST', '/settings/signing/unlock')!.body, {
        'passphrase': 'secret',
      });
      expect(backend.calls('POST', '/payments'), hasLength(1));
      expect(Uri.decodeComponent(launcher.last.toString()), contains('/d/'));
    },
  );

  testWidgets(
    'J5 quote: "שלח הצעה בווטסאפ" → POST /quotes (net lines) → status {to:SENT} → /quote/q1',
    (tester) async {
      await open(tester, intent: 'QUOTE');
      await type(tester, '1180');
      expect(primaryLabel(tester), ComposeHe.sendQuoteWhatsApp);
      await tap(tester, primary());
      expect(
        taps,
        3,
        reason: '+1 for ＋ and +1 for "הצעת מחיר" in S1 = J5 creation 4',
      );
      expect(
        backend.last('POST', '/quotes')!.body['lines'][0]['unitPriceMinor'],
        '100000',
      );
      expect(backend.last('POST', '/quotes/:id/status')!.body, {'to': 'SENT'});
      expect(launcher.last.toString(), startsWith('https://wa.me/972'));
      expect(routes.last, '/quote/q1');
    },
  );

  testWidgets(
    'quote to a customer without a phone → "שלח הצעה" → system share',
    (tester) async {
      String? shared;
      shareText = (t) async => shared = t;
      await open(tester, intent: 'QUOTE', customer: walkIn);
      await type(tester, '100');
      expect(primaryLabel(tester), ComposeHe.sendQuote);
      await tap(tester, primary());
      expect(shared, contains('הצעת מחיר'));
      expect(launcher.opened, isEmpty);
    },
  );

  testWidgets(
    'AT-20: from a SENT quote → ACCEPTED, convert, prefilled 305 → issue',
    (tester) async {
      backend.json('GET', '/quotes', {
        'quotes': [
          {
            'id': 'q5',
            'status': 'SENT',
            'customerId': 'c1',
            'totalMinor': '100000',
          },
        ],
      });
      tester.view.physicalSize = const Size(1170, 2532);
      await open(tester, intent: 'REQUEST');
      // re-open with fromQuoteId through the router helper
      final ctx = tester.element(find.byType(ComposeScreen));
      Navigator.of(ctx).pop();
      await flush(tester);
      unawaited(
        openCompose(
          tester.element(find.text('open')),
          intent: 'REQUEST',
          fromQuoteId: 'q5',
        ),
      );
      await flush(tester);
      // Opening converts nothing: backing out leaves the quote as it was.
      expect(backend.calls('POST', '/quotes/:id/status'), isEmpty);
      expect(backend.calls('POST', '/quotes/:id/convert'), isEmpty);
      await type(tester, '1000');
      expect(primaryLabel(tester), ComposeHe.issueAndWhatsApp);
      await tap(tester, primary());
      expect(backend.last('POST', '/quotes/:id/status')!.body, {
        'to': 'ACCEPTED',
      });
      expect(backend.last('POST', '/quotes/:id/convert')!.body, {
        'documentType': 'TAX_INVOICE',
        'taxRateBasisPoints': 1800,
      });
      expect(
        backend.calls('POST', '/documents'),
        isEmpty,
        reason: 'the converted draft is issued',
      );
      expect(backend.calls('POST', '/documents/:id/finalize'), hasLength(1));
    },
  );

  group('P1', () {
    testWidgets(
      'J5 with BE-06: the WhatsApp text carries the quote link (page + PDF), then SENT',
      (tester) async {
        await open(tester, intent: 'QUOTE');
        await type(tester, '1180');
        await tap(tester, primary());
        expect(taps, 3, reason: 'J5 creation = 4 with ＋ and "הצעת מחיר"');
        expect(backend.calls('POST', '/quotes/:id/share-link'), hasLength(1));
        final text = Uri.decodeComponent(launcher.last.toString());
        expect(text, contains('/q/qtok-q1'));
        expect(
          text,
          contains('₪1,180'),
          reason: 'the quote total includes VAT (per-line rate, BE-06)',
        );
        expect(
          backend
              .last('POST', '/quotes')!
              .body['lines'][0]['taxRateBasisPoints'],
          1800,
        );
        expect(fake.quoteStatus['q1'], 'SENT');
      },
    );

    testWidgets(
      'edit a SENT quote (QUOTE + fromQuoteId): prefilled, PUT /quotes/:id, no new quote',
      (tester) async {
        fake
          ..quotes['q7'] = {
            'customerId': 'c1',
            'validUntil': '2026-12-31',
            'notes': 'כולל התקנה',
            'lines': [
              {
                'description': 'מזגן',
                'quantityMicros': '1000000',
                'unitPriceMinor': '200000',
                'taxRateBasisPoints': 1800,
              },
            ],
          }
          ..quoteStatus['q7'] = 'SENT';
        await open(tester, intent: 'QUOTE', fromQuoteId: 'q7');
        expect(taps, 1, reason: 'the customer is known: no S2');
        await type(tester, '0'); // 2000 → 20000 before VAT
        await tap(tester, primary());
        expect(backend.calls('POST', '/quotes'), isEmpty);
        final put = backend.last('PUT', '/quotes/:id')!;
        expect(put.params['id'], 'q7');
        expect(put.body['validUntil'], '2026-12-31');
        expect(put.body['notes'], 'כולל התקנה');
        expect(put.body['lines'][0]['unitPriceMinor'], '2000000');
        expect(fake.quoteStatus['q7'], 'SENT');
      },
    );

    testWidgets(
      'BE-03 hidden amounts: someone else\'s SENT quote → no ₪0 lines, never PUT over it',
      (tester) async {
        fake
          ..quotes['q8'] = {
            'customerId': 'c1',
            'lines': [
              {
                'description': 'מזגן',
                'quantityMicros': '1000000',
                'unitPriceMinor': '200000',
                'taxRateBasisPoints': 1800,
              },
            ],
          }
          ..quoteStatus['q8'] = 'SENT';
        Object? nullMoney(Object? v) => switch (v) {
          final Map<String, dynamic> m => {
            for (final e in m.entries)
              e.key: e.key.toLowerCase().endsWith('minor')
                  ? null
                  : nullMoney(e.value),
          },
          final List<dynamic> l => [for (final x in l) nullMoney(x)],
          _ => v,
        };
        backend.on(
          'GET',
          '/quotes/:id',
          (r) =>
              FakeResponse(200, nullMoney(fake.quoteDetail(r.params['id']!))!),
        );
        await open(
          tester,
          intent: 'QUOTE',
          fromQuoteId: 'q8',
          preset: Preset.employee,
        );
        expect(primary(), findsNothing, reason: 'no ₪0 amount loaded');
        await type(tester, '500');
        await tap(tester, primary());
        expect(backend.calls('PUT', '/quotes/:id'), isEmpty);
        expect(
          backend.last('POST', '/quotes')!.body['lines'][0]['unitPriceMinor'],
          isNot('0'),
        );
      },
    );

    testWidgets(
      'TAX_INVOICE_DUE (BE-08): TYPE:305 from the paid 300 → linked clone, no POST /documents',
      (tester) async {
        final source = fake.seedIssued('TRANSACTION_INVOICE', 'c1', [
          {
            'description': 'תיקון',
            'quantityMicros': '1000000',
            'unitPriceMinor': '100000',
            'taxRateBasisPoints': 1800,
          },
        ]);
        await open(tester, intent: 'TYPE:305', fromDocId: source);
        expect(primaryLabel(tester), ComposeHe.issueAndWhatsApp);
        await tap(tester, primary());
        expect(taps, 2, reason: 'the card "הפק" + the primary');
        expect(backend.last('POST', '/documents/:id/clone')!.body, {
          'documentType': 'TAX_INVOICE',
          'link': true,
        });
        expect(backend.calls('POST', '/documents'), isEmpty);
        final id = backend
            .last('POST', '/documents/:id/finalize')!
            .params['id']!;
        expect(fake.docs[id]!['converted_from_document_id'], source);
        expect(fake.docs[id]!['total_minor'], '118000');
      },
    );

    testWidgets(
      'BE-07/09: the due date follows the customer terms; S3 shows it',
      (tester) async {
        fake.paymentTerms['c1'] = 'EOM';
        await open(tester, intent: 'REQUEST');
        await type(tester, '1180');
        await tap(tester, find.byKey(const Key('compose-more-details')));
        expect(find.byKey(const Key('s3-due-date')), findsOneWidget);
        expect(find.byKey(const Key('s3-notes')), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('s3-notes')),
          'לפי הזמנה 17',
        );
        Navigator.of(tester.element(find.byKey(const Key('s3-notes')))).pop();
        await flush(tester);
        await tap(tester, primary());
        final body = backend.last('POST', '/documents')!.body;
        expect(body['dueDate'], dueDateForTerms('EOM', DateTime.now()));
        expect(body['notes'], 'לפי הזמנה 17');
      },
    );

    testWidgets(
      'BE-09: no description on this device → the customer\'s last line on the server',
      (tester) async {
        await open(
          tester,
          intent: 'PAID',
          customer: const Customer(
            id: 'c1',
            name: 'דנה',
            phone: '050-1234567',
            lastLineDescription: 'ניקוי מזגן',
          ),
        );
        await type(tester, '100');
        await tap(tester, primary());
        expect(
          backend.last('POST', '/documents')!.body['lines'][0]['description'],
          'ניקוי מזגן',
        );
      },
    );

    testWidgets(
      '500 purchase order: S2 in supplier mode → supplierId, "הפק" → D + S6',
      (tester) async {
        await open(
          tester,
          intent: 'TYPE:500',
          customer: const Customer(id: 's9', name: 'ספק הברגים'),
        );
        await type(tester, '500');
        expect(primaryLabel(tester), ComposeHe.issue);
        await tap(tester, primary());
        final body = backend.last('POST', '/documents')!.body;
        expect(
          (
            body['documentType'],
            body['supplierId'],
            body.containsKey('customerId'),
          ),
          ('PURCHASE_ORDER', 's9', false),
        );
        expect(
          routes,
          contains(
            'S6 ${backend.last('POST', '/documents/:id/finalize')!.params['id']}',
          ),
        );
      },
    );
  });

  testWidgets(
    'AT-70: 200% text on a 375×667 phone — no overflow; amount and primary visible',
    (tester) async {
      await open(
        tester,
        intent: 'PAID',
        textScale: 2,
        size: const Size(1125, 2001),
      );
      expect(tester.takeException(), isNull);
      await type(tester, '1180');
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('compose-amount')).hitTestable(),
        findsOneWidget,
      );
      expect(primary().hitTestable(), findsOneWidget);
      for (final d in ['1', '0', '9']) {
        final key = find.descendant(
          of: find.byType(Keypad),
          matching: find.text(d),
        );
        expect(key.hitTestable(), findsOneWidget);
        final para = tester.renderObject<RenderParagraph>(key);
        expect(
          para.getMaxIntrinsicHeight(double.infinity),
          lessThanOrEqualTo(Hit.keypad),
          reason: 'the digit fits its 64pt key',
        );
      }
    },
  );

  testWidgets(
    'reference header shows the chosen customer and keeps editing accessible',
    (tester) async {
      await open(tester, intent: 'PAID');
      expect(find.byKey(const Key('compose-customer')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('compose-customer')),
          matching: find.text(dana.name),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('compose-close')), findsOneWidget);
    },
  );

  testWidgets('title: REQUEST → "בקש תשלום", QUOTE → "הצעת מחיר"', (
    tester,
  ) async {
    expect(ComposeHe.titleFor('REQUEST'), 'בקש תשלום');
    expect(ComposeHe.titleFor('QUOTE'), 'הצעת מחיר');
    expect(ComposeHe.titleFor('TYPE:320'), ComposeHe.titleNew);
  });

  testWidgets('a type not allowed for the business → message, no button', (
    tester,
  ) async {
    await open(tester, intent: 'TYPE:305', businessType: 'OSEK_PATUR');
    expect(find.text(ComposeHe.notAvailable), findsOneWidget);
    expect(primary(), findsNothing);
  });

  group('QA 2026-11-12', () {
    testWidgets(
      'U0: ✕ with an amount → "לשמור טיוטה?" → מחק closes, no draft kept',
      (tester) async {
        await open(tester, intent: 'PAID');
        await type(tester, '50');
        await tester.tap(find.byKey(const Key('compose-close')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('save-draft-dialog')), findsOneWidget);
        await tester.tap(find.byKey(const Key('save-draft-discard')));
        await flush(tester);
        await tester.pumpAndSettle();
        expect(
          find.byType(ComposeScreen),
          findsNothing,
          reason: 'one tap out, no loop back to S2',
        );
        final draft = await tester.runAsync(() => loadLocalDraft('PAID'));
        expect(draft, isNull);
      },
    );

    testWidgets('U1: the primary ignores taps for 400ms after it appears', (
      tester,
    ) async {
      await open(tester, intent: 'PAID');
      await tester.tap(
        find
            .descendant(of: find.byType(Keypad), matching: find.text('5'))
            .first,
      );
      await tester.pump();
      await tester.tap(primary()); // where the 0 key used to be
      await flush(tester);
      expect(backend.calls('POST', '/documents'), isEmpty);
      await tester.pump(const Duration(milliseconds: 450));
      await tap(tester, primary());
      expect(backend.calls('POST', '/documents'), hasLength(1));
    });

    testWidgets('U1: the keypad does not move when the primary appears', (
      tester,
    ) async {
      await open(tester, intent: 'PAID');
      final zero = find.descendant(
        of: find.byType(Keypad),
        matching: find.text('0'),
      );
      final before = tester.getCenter(zero);
      await type(tester, '1');
      expect(primary(), findsOneWidget);
      expect(tester.getCenter(zero), before);
    });

    testWidgets(
      '1.3: share fails after issue → "הופק, השיתוף נכשל", D + S6 open',
      (tester) async {
        backend.error('POST', '/documents/:id/share-link', 500, 'INTERNAL');
        await open(tester, intent: 'PAID');
        await type(tester, '100');
        expect(primaryLabel(tester), ComposeHe.issueAndWhatsApp);
        await tap(tester, primary());
        expect(backend.calls('POST', '/documents/:id/finalize'), hasLength(1));
        expect(routes, contains('/doc/d1'));
        await tester.pump();
        expect(routes, contains('S6 d1'));
        expect(find.text(ComposeHe.issuedShareFailed), findsOneWidget);
      },
    );

    testWidgets('1.3: quote share sheet dismissed → not marked SENT', (
      tester,
    ) async {
      shareText = (_) async => throw const ShareDismissed();
      await open(tester, intent: 'QUOTE', customer: walkIn);
      await type(tester, '100');
      await tap(tester, primary());
      expect(backend.calls('POST', '/quotes'), hasLength(1));
      expect(backend.calls('POST', '/quotes/:id/status'), isEmpty);
      expect(find.text(ComposeHe.quoteNotSent), findsOneWidget);
    });

    testWidgets(
      'U5: a local draft is offered ("המשך טיוטה"), not restored silently',
      (tester) async {
        await tester.runAsync(() => signInAs(backend, Preset.owner));
        await tester.runAsync(
          () => saveLocalDraft('PAID', {
            'kind': 'taxInvoiceReceipt',
            'customer': dana.toJson(),
            'amountText': '77',
            'description': 'ייעוץ',
          }),
        );
        await open(tester, intent: 'PAID', customer: null);
        expect(find.byKey(const Key('resume-draft-dialog')), findsOneWidget);
        expect(find.byType(Keypad), findsNothing);
        await tester.tap(find.byKey(const Key('resume-draft-continue')));
        await flush(tester);
        expect(
          find.descendant(
            of: find.byKey(const Key('compose-customer')),
            matching: find.text(dana.name),
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('compose-amount')), findsOneWidget);
        final amount = tester.widget<AmountDisplay>(
          find.byKey(const Key('compose-amount')),
        );
        expect(amount.keypadText, '77');
      },
    );
  });
}

void unawaited(Future<void> f) {}

class _Names extends NavigatorObserver {
  _Names(this.names);
  final List<String> names;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final n = route.settings.name;
    if (n != null) names.add(n);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final n = newRoute?.settings.name;
    if (n != null) names.add(n);
  }
}
