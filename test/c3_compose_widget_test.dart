// C3 Composer widget tests (QA 2026-11-16): "פיצול תשלום" with "נותר: ₪X",
// and "כמו בפעם הקודמת" = two taps for a regular client.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/api/signing_api.dart' as signing;
import 'package:invoice/router.dart';
import 'package:invoice/screens/compose/compose_screen.dart';
import 'package:invoice/screens/compose/compose_submit.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/ds.dart';
import 'package:invoice/util/labels/labels.dart';

import 'fakes/fake_api.dart';

const dana = Customer(id: 'c1', name: 'דנה', phone: '050-1234567');

void main() {
  late FakeBackend backend;
  late IssueFake fake;
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('c3_compose_widget_test');
    AppCache.directoryProvider = () async => tmp;
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    signing.signingBiometric = (_) async => true;
    resetSession();
    backend = FakeBackend()..install();
    fake = installIssueFakes(backend);
    FakeLauncher().install();
    shareText = (_) async {};
    Future<void> stub(BuildContext c, String name) =>
        Navigator.of(c).pushReplacement(
          MaterialPageRoute<void>(
            settings: RouteSettings(name: name),
            builder: (_) => Scaffold(body: Text(name)),
          ),
        );
    openIssuedDocument = (c, id) => stub(c, '/doc/$id');
    openShareAfterIssue = (c, id) async {};
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
    await tester.pump(const Duration(milliseconds: 450));
  }

  Future<void> open(WidgetTester tester, {required String intent}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => signInAs(backend, Preset.owner));
    pickCustomer = (_) async => dana;
    pickPaymentCustomer = pickCustomer;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: messengerKey,
        locale: const Locale('he', 'IL'),
        supportedLocales: const [Locale('he', 'IL')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildTheme(Brightness.light),
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => openCompose(c, intent: intent),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await flush(tester);
  }

  Finder primary() => find.byKey(const Key('compose-primary'));
  Finder key(String k) => find.byKey(Key(k));

  Future<void> tapKey(WidgetTester tester, String k) async {
    await tester.ensureVisible(key(k));
    await tester.pump();
    await tester.tap(key(k));
    await flush(tester);
  }

  /// A C3 server: finalize records the split with the issue.
  void recordSplitOnFinalize() {
    backend.on('POST', '/documents/:id/finalize', (r) {
      final id = r.params['id']!;
      final d = fake.docs[id]!
        ..['status'] = 'FINALIZED'
        ..['document_number'] = '51';
      final record = r.body['recordPendingPayments'] == true;
      if (record) {
        d
          ..['paid_total_minor'] = d['total_minor']
          ..['balance_minor'] = '0';
      }
      return FakeResponse(200, {
        'status': 'FINALIZED',
        'documentNumber': '51',
        if (record) 'paymentRecorded': true,
      });
    });
  }

  testWidgets(
    'persona 02: half transfer + half cheque from the Composer, blocked until it adds up',
    (tester) async {
      recordSplitOnFinalize();
      await open(tester, intent: 'PAID');
      await type(tester, '1180');
      expect(primary(), findsOneWidget, reason: 'one method: as fast as today');
      await tapKey(tester, 'compose-split');
      expect(key('compose-splits'), findsOneWidget);
      expect(primary(), findsNothing, reason: 'a split needs two lines');

      await tester.enterText(key('split-amount-0'), '590');
      await tester.pump();
      expect(
        find.text(ComposeHe.splitRemaining(BigInt.from(59000))),
        findsOneWidget,
      );
      await tapKey(tester, 'split-add');
      expect(find.text(ComposeHe.splitFull), findsOneWidget);

      // Line 2 → cheque: the issue waits for its details.
      await tester.ensureVisible(key('split-methods-1'));
      await tester.tap(
        find.descendant(
          of: key('split-methods-1'),
          matching: find.text(paymentMethodLabels['CHECK']!),
        ),
      );
      await tester.pump();
      expect(primary(), findsNothing);
      for (final (k, v) in [
        ('split-check-bank-1', '12'),
        ('split-check-branch-1', '600'),
        ('split-check-account-1', '123456'),
        ('split-check-number-1', '1001'),
      ]) {
        await tester.ensureVisible(key(k));
        await tester.enterText(key(k), v);
      }
      await tester.pump(const Duration(milliseconds: 450));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 450));
      expect(primary(), findsOneWidget);

      await tester.tap(primary());
      await flush(tester);
      final fin = backend.last('POST', '/documents/:id/finalize')!.body;
      expect(fin['recordPendingPayments'], isTrue);
      final list = fin['pendingPayments'] as List;
      expect(list.map((p) => (p as Map)['method']), ['CASH', 'CHECK']);
      expect(list.first['amountMinor'], '59000');
      expect(list.last['reference'], '1001');
      expect(backend.calls('POST', '/payments'), isEmpty);
      expect(find.text('/doc/d1'), findsOneWidget);
    },
  );

  testWidgets(
    'persona 04: "כמו בפעם הקודמת" → the same amount and method → issue (2 taps)',
    (tester) async {
      await open(tester, intent: 'PAID');
      await type(tester, '350');
      await tester.tap(
        find.descendant(
          of: key('compose-methods'),
          matching: find.text(paymentMethodLabels['CREDIT_CARD']!),
        ),
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.tap(primary());
      await flush(tester);
      expect(backend.last('POST', '/payments')!.body['method'], 'CREDIT_CARD');
      final before = backend.calls('POST', '/payments').length;

      // Next visit: the method default would be the last one used anyway, so
      // make it differ — the repeat brings back this customer's own.
      await tester.runAsync(() => AppCache.write('nd_last_method_b1', 'CASH'));
      navigatorKey.currentState!.pop(); // D → H
      await flush(tester);
      await tester.tap(find.text('open'));
      await flush(tester);
      final repeat = key('compose-repeat');
      expect(repeat, findsOneWidget);
      expect(
        find.text(ComposeHe.repeatLastAmount(BigInt.from(35000))),
        findsOneWidget,
      );
      await tester.tap(repeat); // tap 1
      await tester.pump(const Duration(milliseconds: 450));
      expect(primary(), findsOneWidget);
      await tester.tap(primary()); // tap 2
      await flush(tester);
      final pays = backend.calls('POST', '/payments');
      expect(pays.length, before + 1);
      expect(pays.last.body['method'], 'CREDIT_CARD');
      expect(pays.last.body['amountMinor'], '35000');
    },
  );
}
