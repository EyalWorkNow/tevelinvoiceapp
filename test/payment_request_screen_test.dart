// בקשת תשלום — the short payment-request screen (owner 2026-11-18): a form
// that is not the Composer, issuing the same 300 through the same API.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/api/signing_api.dart' as signing;
import 'package:invoice/router.dart';
import 'package:invoice/screens/business/business_screen.dart';
import 'package:invoice/screens/compose/compose_screen.dart';
import 'package:invoice/screens/compose/compose_submit.dart';
import 'package:invoice/screens/compose/payment_request_screen.dart';
import 'package:invoice/screens/compose/sheets/s1_create.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/session.dart';
import 'package:invoice/ui/ds.dart';
import 'package:invoice/util/labels/labels.dart';
import 'package:invoice/util/labels/payment_request_he.dart';

import 'fakes/fake_api.dart';

const dana = Customer(id: 'c1', name: 'דנה', phone: '050-1234567');

void main() {
  late FakeBackend backend;
  late FakeLauncher launcher;
  late Directory tmp;
  final routes = <String>[];

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('payment_request_test');
    AppCache.directoryProvider = () async => tmp;
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    signing.signingBiometric = (_) async => true;
    resetSession();
    backend = FakeBackend()..install();
    installIssueFakes(backend);
    launcher = FakeLauncher()..install();
    shareText = (_) async {};
    openIssuedDocument = (c, id) => Navigator.of(c).pushReplacement(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: '/doc/$id'),
        builder: (_) => Scaffold(body: Text('/doc/$id')),
      ),
    );
    openShareAfterIssue = (c, id) async => routes.add('S6 $id');
    pickRequestCustomer = (_) async => dana;
    routes.clear();
    await AppCache.clearAll();
  });

  tearDown(FakeLauncher.uninstall);

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

  Future<void> signIn(
    WidgetTester tester, {
    Preset preset = Preset.owner,
    String businessType = 'OSEK_MURSHE',
    Map<String, dynamic>? approvalPolicy,
    bool agreedTotals = true,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await signInAs(
        backend,
        preset,
        businessType: businessType,
        approvalPolicy: approvalPolicy,
      );
      // GET /me `lineAgreedTotal`: the server keeps a typed total exactly.
      backend.json('GET', '/me', {
        ...meJson(
          preset,
          businessType: businessType,
          approvalPolicy: approvalPolicy,
        ),
        'lineAgreedTotal': agreedTotals,
      });
      await session.refreshBusiness();
    });
  }

  Future<void> pumpHome(WidgetTester tester, Widget home) async {
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

  Future<void> open(
    WidgetTester tester, {
    String? customerId,
    Preset preset = Preset.owner,
    String businessType = 'OSEK_MURSHE',
    Map<String, dynamic>? approvalPolicy,
    bool offline = false,
  }) async {
    await signIn(
      tester,
      preset: preset,
      businessType: businessType,
      approvalPolicy: approvalPolicy,
    );
    session.offline = offline;
    await pumpHome(
      tester,
      Builder(
        builder: (c) => Scaffold(
          body: TextButton(
            onPressed: () => openPaymentRequest(c, customerId: customerId),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await flush(tester);
  }

  Finder send() => find.byKey(const Key('payment-request-send'));

  Future<void> fill(
    WidgetTester tester, {
    String amount = '2',
    String description = 'שיעור פרטי',
    String note = '',
  }) async {
    await tester.tap(find.byKey(const Key('payment-request-customer')));
    await flush(tester);
    await tester.enterText(
      find.byKey(const Key('payment-request-amount')),
      amount,
    );
    await tester.enterText(
      find.byKey(const Key('payment-request-description')),
      description,
    );
    if (note.isNotEmpty) {
      await tester.enterText(
        find.byKey(const Key('payment-request-note')),
        note,
      );
    }
    await tester.pump();
  }

  testWidgets('a short form — none of the Composer', (tester) async {
    await open(tester);
    expect(find.byType(PaymentRequestScreen), findsOneWidget);
    expect(find.text(PaymentRequestHe.title), findsOneWidget);
    for (final k in [
      'payment-request-customer',
      'payment-request-amount',
      'payment-request-description',
      'payment-request-due',
      'payment-request-note',
      'payment-request-advanced',
    ]) {
      expect(find.byKey(Key(k)), findsOneWidget, reason: k);
    }
    expect(find.text(PaymentRequestHe.send), findsOneWidget);
    expect(find.byType(ComposeScreen), findsNothing);
    expect(find.byType(Keypad), findsNothing);
    expect(find.byKey(const Key('compose-primary')), findsNothing);
    expect(find.byKey(const Key('compose-kind-request')), findsNothing);
    // Due date: שוטף+30 when nothing else is known (the Composer's default).
    expect(
      find.descendant(
        of: find.byKey(const Key('payment-request-due')),
        matching: find.text(PaymentRequestHe.dueDate),
      ),
      findsOneWidget,
    );
  });

  testWidgets('validation: customer, amount > 0 and description required', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(send());
    await flush(tester);
    expect(find.text(PaymentRequestHe.needCustomer), findsOneWidget);
    expect(find.text(PaymentRequestHe.needAmount), findsOneWidget);
    expect(find.text(PaymentRequestHe.needDescription), findsOneWidget);
    expect(backend.calls('POST', '/documents'), isEmpty);

    await fill(tester, amount: '0', description: '   ');
    await tester.tap(send());
    await flush(tester);
    expect(find.text(PaymentRequestHe.needCustomer), findsNothing);
    expect(find.text(PaymentRequestHe.needAmount), findsOneWidget);
    expect(find.text(PaymentRequestHe.needDescription), findsOneWidget);
    expect(backend.calls('POST', '/documents'), isEmpty);
  });

  testWidgets(
    'מורשה: ONE line, agreedTotalMinor = the typed ₪2.00, draft 300 → finalize → WhatsApp',
    (tester) async {
      await open(tester);
      await fill(tester, note: 'תודה!');
      await tester.tap(send());
      await flush(tester);
      final body = backend.last('POST', '/documents')!.body;
      expect(body['documentType'], 'TRANSACTION_INVOICE');
      expect(body['customerId'], 'c1');
      expect(body['notes'], 'תודה!');
      expect(body['dueDate'], isA<String>());
      final lines = (body['lines'] as List).cast<Map<String, dynamic>>();
      expect(lines, hasLength(1));
      expect(lines.single['description'], 'שיעור פרטי');
      expect(lines.single['quantityMicros'], '1000000');
      expect(lines.single['taxRateBasisPoints'], greaterThan(0));
      expect(lines.single['agreedTotalMinor'], '200');
      expect(backend.calls('POST', '/documents/:id/finalize'), hasLength(1));
      expect(backend.calls('POST', '/documents/:id/submit'), isEmpty);
      expect(backend.calls('POST', '/payments'), isEmpty);
      // The customer has a phone: WhatsApp opens with the document link.
      expect(launcher.last.toString(), startsWith('https://wa.me/972'));
      expect(find.byType(PaymentRequestScreen), findsNothing);
      expect(find.textContaining('/doc/'), findsOneWidget);
    },
  );

  testWidgets('פטור: the 300 has no VAT — the typed amount is the price', (
    tester,
  ) async {
    await open(tester, businessType: 'OSEK_PATUR');
    expect(find.text(PaymentRequestHe.amountExact), findsOneWidget);
    await fill(tester, amount: '590');
    await tester.tap(send());
    await flush(tester);
    final body = backend.last('POST', '/documents')!.body;
    expect(body['documentType'], 'TRANSACTION_INVOICE');
    final line = (body['lines'] as List).single as Map<String, dynamic>;
    expect(line['taxRateBasisPoints'], 0);
    expect(line['unitPriceMinor'], '59000');
    expect(line.containsKey('agreedTotalMinor'), isFalse);
    expect(backend.calls('POST', '/documents/:id/finalize'), hasLength(1));
  });

  testWidgets('approval policy: "שלח לאישור" submits instead of finalizing', (
    tester,
  ) async {
    await open(
      tester,
      approvalPolicy: {
        'mode': 'THRESHOLD',
        'thresholdMinor': '500000',
        'includesVat': true,
        'selfApprovalAllowed': false,
        'otherApproverExists': true,
      },
    );
    await fill(tester, amount: '5000');
    expect(find.text(ComposeHe.submit), findsOneWidget);
    expect(find.text(approvalNote(BigInt.from(500000))), findsOneWidget);
    await tester.tap(send());
    await flush(tester);
    expect(backend.calls('POST', '/documents/:id/submit'), hasLength(1));
    expect(backend.calls('POST', '/documents/:id/finalize'), isEmpty);
    expect(launcher.opened, isEmpty);
  });

  testWidgets('offline: the button says "אין חיבור" and issues nothing', (
    tester,
  ) async {
    await open(tester, offline: true);
    final b = tester.widget<PrimaryButton>(send());
    expect(b.offline, isTrue);
    expect(find.text(CommonHe.offlineButton), findsOneWidget);
  });

  testWidgets('viewer: not available (mirrors the Composer)', (tester) async {
    await open(tester, preset: Preset.viewer);
    expect(find.text(PaymentRequestHe.notAvailable), findsOneWidget);
    expect(send(), findsNothing);
  });

  testWidgets('customerId: the customer is already chosen', (tester) async {
    await open(tester, customerId: 'c1');
    expect(
      find.descendant(
        of: find.byKey(const Key('payment-request-customer')),
        matching: find.text('דנה'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('"עריכה מתקדמת" opens the Composer with what was typed', (
    tester,
  ) async {
    await open(tester);
    await fill(tester, amount: '350', description: 'תיקון');
    await tester.tap(find.byKey(const Key('payment-request-advanced')));
    await flush(tester);
    expect(find.byType(PaymentRequestScreen), findsNothing);
    final c = tester.widget<ComposeScreen>(find.byType(ComposeScreen));
    expect(c.intent, 'REQUEST');
    expect(c.customerId, 'c1');
    expect(c.prefillAmountMinor, BigInt.from(35000));
    expect(c.prefillDescription, 'תיקון');
    expect(c.prefillNotes, isNull);
  });

  testWidgets('"עריכה מתקדמת" keeps the typed note', (tester) async {
    await open(tester);
    await fill(tester, amount: '350', description: 'תיקון');
    await tester.enterText(
      find.byKey(const Key('payment-request-note')),
      '  לתשלום עד סוף החודש  ',
    );
    await tester.tap(find.byKey(const Key('payment-request-advanced')));
    await flush(tester);
    final c = tester.widget<ComposeScreen>(find.byType(ComposeScreen));
    expect(c.prefillNotes, 'לתשלום עד סוף החודש');
    expect(c.prefillDescription, 'תיקון');
  });

  group('route', () {
    test('/payment-request is a C route that needs doc.draft', () {
      final r = AppRoute.parse('tevel://payment-request?customerId=c1')!;
      expect(r.pattern, '/payment-request');
      expect(r.requiredCap, Cap.docDraft);
      final screen = screenFor(r);
      expect(screen, isA<PaymentRequestScreen>());
      expect((screen! as PaymentRequestScreen).customerId, 'c1');
    });
  });

  group('entry points open the short form', () {
    testWidgets('S1 "בקשת תשלום"', (tester) async {
      await signIn(tester);
      await pumpHome(
        tester,
        Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => showCreateSheet(c),
              child: const Text('plus'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('plus'));
      await flush(tester);
      await tester.tap(find.byKey(const Key('s1-request')));
      await flush(tester);
      expect(find.byType(PaymentRequestScreen), findsOneWidget);
      expect(find.byType(ComposeScreen), findsNothing);
    });

    testWidgets('ניהול "בקשת תשלום"', (tester) async {
      await signIn(tester);
      await pumpHome(tester, const BusinessScreen());
      final action = find.byKey(const Key('management-action-payment-request'));
      await tester.ensureVisible(action);
      await tester.tap(action);
      await flush(tester);
      expect(find.byType(PaymentRequestScreen), findsOneWidget);
      expect(find.byType(ComposeScreen), findsNothing);
    });
  });
}
