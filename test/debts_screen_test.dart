// C1 "מי חייב לי": the screen (header = Home's server figure, the debt book
// beside it, oldest first, empty state), the WhatsApp reminder (one message
// per customer, the tone by the server's count, logged on the server), the
// debt-entry sheet, the server-synced "last reminded" and the route gate.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/debts_api.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/debts/debt_entry_sheet.dart';
import 'package:invoice/screens/debts/debts_screen.dart';
import 'package:invoice/screens/document/sheets/s6_share.dart';
import 'package:invoice/state/business_context.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/ds.dart';
import 'package:invoice/util/labels/debts_he.dart';
import 'package:invoice/util/labels/reminder_he.dart';
import 'package:invoice/util/payment_reminder.dart';

import 'fakes/fake_api.dart';

Map<String, dynamic> debtsJson({List<Map<String, dynamic>>? customers}) => {
  'today': '2026-11-16',
  'documentsOpenMinor': '118000',
  'documentsOverdueMinor': '118000',
  'debtBookOpenMinor': '60000',
  'totalMinor': '178000',
  'customers':
      customers ??
      [
        {
          'customerId': 'c-yossi',
          'customerName': 'יוסי',
          'phone': '050-1234567',
          'totalMinor': '178000',
          'documentsOpenMinor': '118000',
          'debtBookMinor': '60000',
          'oldestOverdueDays': 20,
          'oldestEntryDays': 9,
          'lastRemindedAt': '2026-11-13T09:00:00.000Z',
          'reminderCount': 1,
          'documents': [
            {
              'id': 'd1',
              'documentType': 'TAX_INVOICE',
              'documentNumber': '1024',
              'dueDate': '2026-10-27',
              'openMinor': '118000',
              'overdueDays': 20,
              'lastRemindedAt': '2026-11-13T09:00:00.000Z',
            },
          ],
          'debtEntries': [
            {
              'id': 'e1',
              'customerId': 'c-yossi',
              'amountMinor': '60000',
              'note': '3 שיעורים',
              'debtDate': '2026-11-07',
              'status': 'OPEN',
            },
          ],
        },
        {
          'customerId': 'c-dana',
          'customerName': 'דנה',
          'phone': null,
          'totalMinor': '0',
          'documentsOpenMinor': '0',
          'debtBookMinor': '0',
          'oldestOverdueDays': null,
          'oldestEntryDays': null,
          'lastRemindedAt': null,
          'reminderCount': 0,
          'documents': <Object>[],
          'debtEntries': <Object>[],
        },
      ],
};

Widget app(Widget home) => MaterialApp(
  locale: const Locale('he', 'IL'),
  supportedLocales: const [Locale('he', 'IL')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: buildTheme(Brightness.light),
  home: home,
);

void main() {
  late Directory tmp;
  late FakeBackend backend;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('debts_screen_test');
    AppCache.directoryProvider = () async => tmp;
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    resetSession();
    backend = FakeBackend()..install();
    await AppCache.clearAll();
    loadWhoOwesMe = fetchWhoOwesMe;
  });

  Future<void> pumpDebts(
    WidgetTester tester, {
    Preset preset = Preset.owner,
  }) async {
    tester.view
      ..physicalSize = const Size(1200, 4000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => signInAs(backend, preset));
    await tester.pumpWidget(
      app(DebtsScreen(now: () => DateTime(2026, 11, 16, 12))),
    );
    await tester.pumpAndSettle();
  }

  group('screen', () {
    testWidgets(
      'header = the server documents sum (Home); the debt book beside it',
      (tester) async {
        backend.json('GET', '/debts', debtsJson());
        await pumpDebts(tester);
        final header = tester.widget<MoneyCard>(
          find.byKey(const Key('debts-header')),
        );
        expect(header.amountMinor, BigInt.from(118000));
        expect(header.secondaryMinor, BigInt.from(118000));
        expect(find.byKey(const Key('debts-book-extra')), findsOneWidget);
        expect(find.textContaining(DebtsHe.bookExtraNote), findsOneWidget);
      },
    );

    testWidgets(
      'one row per customer in server order, overdue days, last reminded',
      (tester) async {
        backend.json('GET', '/debts', debtsJson());
        await pumpDebts(tester);
        final yossi = tester.getTopLeft(
          find.byKey(const Key('debtor-c-yossi')),
        );
        final dana = tester.getTopLeft(find.byKey(const Key('debtor-c-dana')));
        expect(yossi.dy, lessThan(dana.dy));
        expect(find.text(DebtsHe.overdueDays(20)), findsOneWidget);
        expect(find.text(ReminderHe.lastReminded(3)), findsOneWidget);
        expect(find.text(DebtsHe.neverReminded), findsOneWidget);
        expect(find.text(DebtsHe.nextTone(1)), findsOneWidget);
        // Expanding shows the document and the debt-book line, labelled as not a document.
        await tester.tap(find.text('יוסי'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('debt-doc-d1')), findsOneWidget);
        expect(find.byKey(const Key('debt-entry-e1')), findsOneWidget);
        expect(find.textContaining(DebtsHe.bookBadge), findsOneWidget);
        // The debt line's ⋯ sits before its amount: it hugs the same edge as
        // the document line above it (2026-11-23).
        double amountLeft(String key) => tester
            .getTopLeft(
              find.descendant(
                of: find.byKey(Key(key)),
                matching: find.byType(AmountText),
              ),
            )
            .dx;
        expect(
          amountLeft('debt-entry-e1'),
          closeTo(amountLeft('debt-doc-d1'), .1),
        );
      },
    );

    testWidgets(
      '2611 §2: "תזכורת הבאה: יום ב׳ 1.12" per customer and document; '
      '"לטיפול ידני" at the ceiling',
      (tester) async {
        final j = debtsJson();
        final yossi = (j['customers'] as List).first as Map<String, dynamic>;
        yossi['nextReminderDate'] = '2026-11-30';
        yossi['manualCount'] = 0;
        ((yossi['documents'] as List).first as Map)['nextReminder'] = {
          'state': 'SCHEDULED',
          'date': '2026-11-30',
          'count': 2,
        };
        final dana = (j['customers'] as List)[1] as Map<String, dynamic>;
        dana['manualCount'] = 1;
        backend.json('GET', '/debts', j);
        await pumpDebts(tester);
        expect(find.byKey(const Key('debtor-next-c-yossi')), findsOneWidget);
        expect(find.text('תזכורת הבאה: יום ב׳ 30.11'), findsOneWidget);
        expect(find.text('לטיפול ידני'), findsOneWidget);
        await tester.tap(find.text('יוסי'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('תזכורת הבאה: יום ב׳ 30.11', findRichText: true),
          findsNWidgets(2),
        );
      },
    );

    testWidgets('empty state', (tester) async {
      backend.json('GET', '/debts', {
        'documentsOpenMinor': '0',
        'documentsOverdueMinor': '0',
        'debtBookOpenMinor': '0',
        'totalMinor': '0',
        'customers': <Object>[],
      });
      await pumpDebts(tester);
      expect(find.text('אף אחד לא חייב לך 🎉'), findsOneWidget);
      expect(find.byKey(const Key('debts-add')), findsOneWidget);
    });

    testWidgets('a viewer without doc.send / payment gets no actions', (
      tester,
    ) async {
      backend.json('GET', '/debts', debtsJson());
      await pumpDebts(tester, preset: Preset.viewer);
      expect(find.byKey(const Key('debtor-remind-c-yossi')), findsNothing);
      expect(find.byKey(const Key('debtor-paid-c-yossi')), findsNothing);
      expect(find.byKey(const Key('debts-add')), findsNothing);
    });
  });

  group('WhatsApp reminder', () {
    testWidgets(
      'one message for the customer, 2nd-reminder tone, logged on the server',
      (tester) async {
        final launcher = FakeLauncher()..install();
        addTearDown(FakeLauncher.uninstall);
        backend
          ..json('GET', '/debts', debtsJson())
          ..json('POST', '/documents/:id/share-link', {
            'url': 'https://invoice.test/d/tok',
            'token': 'tok',
          })
          ..json('POST', '/reminders/log', {
            'sendId': 's1',
            'items': 2,
          }, status: 201);
        await pumpDebts(tester);
        await tester.tap(find.byKey(const Key('debtor-remind-c-yossi')));
        await tester.pumpAndSettle();
        final url = launcher.last.toString();
        expect(url, startsWith('https://wa.me/972501234567?text='));
        final text = Uri.parse(url).queryParameters['text']!;
        expect(text, contains('תזכורת נוספת'));
        expect(text, contains('3 שיעורים'));
        expect(text, contains('אם כבר שילמת'));
        // The local copy is written to disk (real IO) before the server log.
        for (
          var i = 0;
          i < 50 && backend.last('POST', '/reminders/log') == null;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
        final log = backend.last('POST', '/reminders/log')!;
        expect(log.body['documentIds'], ['d1']);
        expect(log.body['debtEntryIds'], ['e1']);
        expect(log.body['channel'], 'WHATSAPP');
        // The list reloads (the new count comes from the server).
        expect(backend.calls('GET', '/debts').length, greaterThanOrEqualTo(2));
      },
    );

    test('the tone escalates gently: friendly, firmer, "נא להסדיר"', () {
      String msg(int previous) => ReminderHe.message(
        customerName: 'דנה',
        documentType: 'TAX_INVOICE',
        documentNumber: '1',
        amountMinor: BigInt.from(100),
        business: 'תבל',
        link: 'https://x.test',
        previous: previous,
      );
      expect(msg(0), contains('תזכורת ידידותית'));
      expect(msg(0), isNot(contains('בהקדם')));
      expect(msg(1), contains('תזכורת נוספת'));
      expect(msg(1), contains('בהקדם'));
      expect(msg(2), contains('נא להסדיר'));
      expect(msg(5), contains('נא להסדיר'));
      for (final p in [0, 1, 2]) {
        expect(msg(p), contains('אם כבר שילמת – תודה'));
      }
    });

    test(
      'a document reminder is logged on the server with its channel',
      () async {
        final launcher = FakeLauncher()..install();
        addTearDown(FakeLauncher.uninstall);
        backend.json('POST', '/reminders/log', {'sendId': 's'}, status: 201);
        await sendPaymentReminder(
          documentId: 'd9',
          documentType: 'TAX_INVOICE',
          openMinor: BigInt.from(100),
          phone: '0501234567',
          link: () async => 'https://x.test/d',
        );
        expect(launcher.opened, hasLength(1));
        final log = backend.last('POST', '/reminders/log')!;
        expect(log.body['documentIds'], ['d9']);
        expect(log.body['channel'], 'WHATSAPP');
      },
    );
  });

  group('last reminded syncs from the server', () {
    test('the later of the server record and this device', () async {
      await ReminderLog.record('d1', at: DateTime(2026, 11, 1, 9));
      backend.json('GET', '/reminders/last', {
        'last': {'d1': '2026-11-10T08:00:00.000Z'},
      });
      expect(
        await ReminderLog.lastFor('d1'),
        DateTime.parse('2026-11-10T08:00:00.000Z').toLocal(),
      );
    });

    test('no server route / offline → this device only', () async {
      await ReminderLog.record('d2', at: DateTime(2026, 11, 2, 9));
      expect(await ReminderLog.lastFor('d2'), DateTime(2026, 11, 2, 9));
    });
  });

  group('debt-entry sheet', () {
    testWidgets('saves "X owes me ₪Y for Z" with an Idempotency-Key', (
      tester,
    ) async {
      await tester.runAsync(() => signInAs(backend, Preset.owner));
      backend.on(
        'POST',
        '/debt-entries',
        (r) => FakeResponse(201, {
          'debtEntry': {
            'id': 'e9',
            'customerId': 'c1',
            'amountMinor': r.body['amountMinor'],
            'note': r.body['note'],
            'debtDate': r.body['debtDate'],
            'status': 'OPEN',
          },
          'reused': false,
        }),
      );
      DebtEntry? saved;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async => saved = await showDebtEntrySheet(
                context,
                customer: const Customer(id: 'c1', name: 'יוסי'),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(DebtsHe.addSubtitle), findsOneWidget);
      await tester.tap(find.byKey(const Key('debt-entry-save')));
      await tester.pumpAndSettle();
      expect(find.text(DebtsHe.missingAmount), findsOneWidget);
      await tester.enterText(find.byKey(const Key('debt-entry-amount')), '600');
      await tester.enterText(
        find.byKey(const Key('debt-entry-note')),
        '3 שיעורים',
      );
      await tester.tap(find.byKey(const Key('debt-entry-save')));
      await tester.pumpAndSettle();
      final post = backend.last('POST', '/debt-entries')!;
      expect(post.body['customerId'], 'c1');
      expect(post.body['amountMinor'], '60000');
      expect(post.body['note'], '3 שיעורים');
      expect(post.idempotencyKey, isNotNull);
      expect(saved?.id, 'e9');
    });
  });

  group('route', () {
    test('/debts needs money view', () async {
      final route = AppRoute.parse('/debts')!;
      await signInAs(backend, Preset.owner);
      expect(route.allowedFor(businessContext.caps), isTrue);
      await signInAs(backend, Preset.employee);
      expect(businessContext.caps.can(Cap.moneyView), isFalse);
      expect(route.allowedFor(businessContext.caps), isFalse);
    });
  });
}
