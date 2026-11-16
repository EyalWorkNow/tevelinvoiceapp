// Automatic collection reminders (server 0111): the API layer, the daily
// WhatsApp batch (one tap → wa.me with the server's wording + the phone's
// share link, recorded on the server; skip), the "מי חייב לי" banner and the
// push deep link, the ladder settings screen (partial PUTs), and the
// customer opt-out / document pause switch (owner / partner only).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/collection_reminders_api.dart';
import 'package:invoice/api/debts_api.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/business/collection_settings_screen.dart';
import 'package:invoice/screens/debts/collection_batch_screen.dart';
import 'package:invoice/screens/debts/debts_screen.dart';
import 'package:invoice/screens/debts/reminder_hold_tile.dart';
import 'package:invoice/screens/document/sheets/s6_share.dart' show textSharer;
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/ds.dart';
import 'package:invoice/util/labels/collection_he.dart';

import 'fakes/fake_api.dart';

Widget app(Widget home) => MaterialApp(
  locale: const Locale('he', 'IL'),
  supportedLocales: const [Locale('he', 'IL')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: buildTheme(Brightness.light),
  home: home,
);

Map<String, dynamic> readyJson() => {
  'count': 2,
  'reminders': [
    {
      'id': 'r1',
      'customerId': 'c-yossi',
      'customerName': 'יוסי לוי',
      'documentId': 'd1',
      'documentType': 'TAX_INVOICE',
      'documentNumber': '1024',
      'offsetDays': 7,
      'dueDate': '2026-11-10',
      'channel': 'WHATSAPP',
      'status': 'READY',
      'phone': '050-1234567',
      'openMinor': '118000',
      'paymentUrl': null,
      'messageText':
          'שלום יוסי,\nמועד התשלום של חשבונית מס 1024 עבר.\nלצפייה ולתשלום: {קישור}\nתודה',
    },
    {
      'id': 'r2',
      'customerId': 'c-rina',
      'customerName': 'רינה',
      'debtEntryId': 'e1',
      'offsetDays': -3,
      'dueDate': '2026-11-20',
      'channel': 'WHATSAPP',
      'status': 'READY',
      'phone': '052-7654321',
      'openMinor': '60000',
      'paymentUrl': null,
      'messageText': 'שלום רינה,\n3 שיעורים.\nלתשלום: {קישור}',
    },
  ],
};

Map<String, dynamic> settingsJson({bool enabled = true}) => {
  'enabled': enabled,
  'steps': [
    {'offsetDays': -3, 'enabled': true, 'template': null},
    {'offsetDays': 0, 'enabled': true, 'template': null},
    {'offsetDays': 7, 'enabled': true, 'template': 'שלום {לקוח}'},
  ],
  'maxPerDocument': 3,
  'channels': {'email': true, 'whatsapp': true},
  'dailySummary': true,
  'defaultTemplates': {
    'before': 'לפני {תאריך}',
    'onDue': 'היום {תאריך}',
    'after': 'עבר {תאריך}',
  },
};

void main() {
  late Directory tmp;
  late FakeBackend backend;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('collection_reminders_test');
    AppCache.directoryProvider = () async => tmp;
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    resetSession();
    backend = FakeBackend()..install();
    await AppCache.clearAll();
    loadReadyReminders = fetchReadyReminders;
    loadCollectionSettings = fetchCollectionSettings;
    loadReminderHold = fetchReminderHold;
    loadWhoOwesMe = fetchWhoOwesMe;
  });

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Preset preset = Preset.owner,
  }) async {
    tester.view
      ..physicalSize = const Size(1200, 3000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => signInAs(backend, preset));
    await tester.pumpWidget(app(home));
    await tester.pumpAndSettle();
  }

  group('api', () {
    test('settings parse; a save sends only what changed', () async {
      backend.json('GET', '/settings/reminders', settingsJson());
      backend.on(
        'PUT',
        '/settings/reminders',
        (r) => FakeResponse(200, settingsJson()),
      );
      final s = (await fetchCollectionSettings())!;
      expect(s.steps.map((x) => x.offsetDays), [-3, 0, 7]);
      expect(s.steps[2].template, 'שלום {לקוח}');
      expect(s.defaultFor(-3), 'לפני {תאריך}');
      await saveCollectionSettings(whatsapp: false);
      expect(backend.last('PUT', '/settings/reminders')!.body, {
        'channels': {'whatsapp': false},
      });
      await saveCollectionSettings(maxPerDocument: 2);
      expect(backend.last('PUT', '/settings/reminders')!.body, {
        'maxPerDocument': 2,
      });
    });

    test('an older server (404) → null / empty, never an error', () async {
      expect(await fetchCollectionSettings(), isNull);
      expect(await fetchReadyReminders(), isEmpty);
      expect(await fetchReminderHold(customerId: 'c1'), isNull);
    });

    test('{קישור} → the link; no link → that line is dropped', () {
      const t = 'שלום\nלתשלום: {קישור}\nתודה';
      expect(fillReminderLink(t, 'https://x.test/d/1'), contains('https://'));
      expect(fillReminderLink(t, null), 'שלום\nתודה');
    });
  });

  group('the daily batch', () {
    testWidgets(
      'one tap → WhatsApp with the wording + share link; recorded; skip',
      (tester) async {
        final launcher = FakeLauncher()..install();
        addTearDown(FakeLauncher.uninstall);
        backend
          ..json('GET', '/collection-reminders/ready', readyJson())
          ..json('POST', '/documents/:id/share-link', {
            'url': 'https://invoice.test/d/tok',
            'token': 'tok',
          })
          ..on(
            'POST',
            '/collection-reminders/:id/sent',
            (r) => const FakeResponse(200, {'reminder': {}}),
          )
          ..on(
            'POST',
            '/collection-reminders/:id/dismiss',
            (r) => const FakeResponse(200, {'reminder': {}}),
          );
        await pump(tester, const CollectionBatchScreen());
        expect(find.text('יוסי לוי'), findsOneWidget);
        expect(find.text('רינה'), findsOneWidget);
        expect(find.textContaining(CollectionHe.stepLabel(7)), findsOneWidget);

        await tester.tap(find.byKey(const Key('collection-send-r1')));
        await tester.pumpAndSettle();
        final url = launcher.last.toString();
        expect(url, startsWith('https://wa.me/972501234567?text='));
        final text = Uri.parse(url).queryParameters['text']!;
        expect(text, contains('https://invoice.test/d/tok'));
        expect(text, isNot(contains('{קישור}')));
        final sent = backend.last('POST', '/collection-reminders/:id/sent')!;
        expect(sent.params['id'], 'r1');
        expect(sent.body['channel'], 'WHATSAPP');
        expect(find.byKey(const Key('collection-item-r1')), findsNothing);

        // A debt-book line has no document link: the link line is dropped.
        await tester.tap(find.byKey(const Key('collection-skip-r2')));
        await tester.pumpAndSettle();
        expect(
          backend
              .last('POST', '/collection-reminders/:id/dismiss')!
              .params['id'],
          'r2',
        );
        expect(find.byKey(const Key('collection-batch-empty')), findsOneWidget);
      },
    );

    testWidgets('no WhatsApp → the share sheet, recorded as SHARE', (
      tester,
    ) async {
      final launcher = FakeLauncher()
        ..result = false
        ..install();
      addTearDown(FakeLauncher.uninstall);
      final shared = <String>[];
      final before = textSharer;
      textSharer = (t) async => shared.add(t);
      addTearDown(() => textSharer = before);
      backend
        ..json('GET', '/collection-reminders/ready', {
          'reminders': [readyJson()['reminders'][1]],
        })
        ..on(
          'POST',
          '/collection-reminders/:id/sent',
          (r) => const FakeResponse(200, {'reminder': {}}),
        );
      await pump(tester, const CollectionBatchScreen());
      await tester.tap(find.byKey(const Key('collection-send-r2')));
      await tester.pumpAndSettle();
      expect(launcher.opened, hasLength(1));
      expect(shared.single, isNot(contains('{קישור}')));
      expect(shared.single, isNot(contains('לתשלום:')));
      expect(
        backend.last('POST', '/collection-reminders/:id/sent')!.body['channel'],
        'SHARE',
      );
    });
  });

  group('"מי חייב לי" banner + the push deep link', () {
    Map<String, dynamic> debts() => {
      'documentsOpenMinor': '118000',
      'documentsOverdueMinor': '118000',
      'debtBookOpenMinor': '0',
      'totalMinor': '118000',
      'customers': <Object>[],
    };

    testWidgets('N ready → a banner that opens the batch', (tester) async {
      backend
        ..json('GET', '/debts', debts())
        ..json('GET', '/collection-reminders/ready', readyJson());
      await pump(tester, DebtsScreen(now: () => DateTime(2026, 11, 17, 10)));
      expect(find.text(CollectionHe.batchBanner(2)), findsOneWidget);
      await tester.tap(find.byKey(const Key('debts-ready-banner')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('collection-batch')), findsOneWidget);
    });

    testWidgets('nothing waiting / no money view → no banner', (tester) async {
      backend
        ..json('GET', '/debts', debts())
        ..json('GET', '/collection-reminders/ready', {'reminders': <Object>[]});
      await pump(tester, DebtsScreen(now: () => DateTime(2026, 11, 17, 10)));
      expect(find.byKey(const Key('debts-ready-banner')), findsNothing);
    });

    test('the summary push opens /debts?batch=1', () {
      final route = AppRoute.parse('/debts?batch=1')!;
      expect(route.pattern, '/debts');
      expect(route.query['batch'], '1');
      final page = screenFor(route);
      expect(page, isA<DebtsScreen>());
      expect((page! as DebtsScreen).openBatch, isTrue);
    });
  });

  group('settings screen', () {
    testWidgets('steps, wording badge, toggles save partial changes', (
      tester,
    ) async {
      backend
        ..json('GET', '/settings/reminders', settingsJson())
        ..on(
          'PUT',
          '/settings/reminders',
          (r) => FakeResponse(200, settingsJson()),
        );
      await pump(tester, const CollectionSettingsScreen());
      expect(find.text(CollectionHe.stepLabel(-3)), findsOneWidget);
      expect(find.text(CollectionHe.stepLabel(0)), findsOneWidget);
      expect(find.text(CollectionHe.stepLabel(7)), findsOneWidget);
      expect(find.text(CollectionHe.stepCustomText), findsOneWidget);
      expect(find.byKey(const Key('collection-quiet')), findsOneWidget);

      await tester.tap(find.byKey(const Key('collection-step-switch-1')));
      await tester.pumpAndSettle();
      final steps =
          backend.last('PUT', '/settings/reminders')!.body['steps'] as List;
      expect(steps.map((s) => (s as Map)['enabled']), [true, false, true]);

      await tester.tap(find.byKey(const Key('collection-summary-switch')));
      await tester.pumpAndSettle();
      expect(backend.last('PUT', '/settings/reminders')!.body, {
        'dailySummary': false,
      });
    });

    testWidgets('edit a step: days + wording with a placeholder chip', (
      tester,
    ) async {
      backend
        ..json('GET', '/settings/reminders', settingsJson())
        ..on(
          'PUT',
          '/settings/reminders',
          (r) => FakeResponse(200, settingsJson()),
        );
      await pump(tester, const CollectionSettingsScreen());
      await tester.tap(find.byKey(const Key('collection-step-edit-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('step-days-plus')));
      await tester.pump();
      expect(find.text('4 ${CollectionHe.days}'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('step-text')), 'שלום ');
      await tester.tap(find.byKey(const Key('step-ph-{לקוח}')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('step-save')));
      await tester.pumpAndSettle();
      final step =
          (backend.last('PUT', '/settings/reminders')!.body['steps'] as List)
                  .first
              as Map;
      expect(step['offsetDays'], -4);
      expect(step['template'], 'שלום {לקוח}');
    });

    testWidgets('turning on asks first', (tester) async {
      backend
        ..json('GET', '/settings/reminders', settingsJson(enabled: false))
        ..on(
          'PUT',
          '/settings/reminders',
          (r) => FakeResponse(200, settingsJson()),
        );
      await pump(tester, const CollectionSettingsScreen());
      await tester.tap(find.byKey(const Key('collection-master-switch')));
      await tester.pumpAndSettle();
      expect(backend.calls('PUT', '/settings/reminders'), isEmpty);
      await tester.tap(find.byKey(const Key('collection-confirm')));
      await tester.pumpAndSettle();
      expect(backend.last('PUT', '/settings/reminders')!.body, {
        'enabled': true,
      });
    });
  });

  group('opt-out / pause', () {
    testWidgets('owner: the switch saves the hold', (tester) async {
      backend
        ..json('GET', '/collection-reminders/holds', {'onHold': false})
        ..on(
          'PUT',
          '/collection-reminders/holds',
          (r) => const FakeResponse(200, {'onHold': true}),
        );
      await pump(
        tester,
        const Scaffold(body: ReminderHoldTile(customerId: 'c-yossi')),
      );
      expect(find.text(CollectionHe.holdCustomer), findsOneWidget);
      await tester.tap(find.byKey(const Key('reminder-hold-switch')));
      await tester.pumpAndSettle();
      expect(backend.last('PUT', '/collection-reminders/holds')!.body, {
        'customerId': 'c-yossi',
        'onHold': true,
      });
    });

    testWidgets('an employee never sees it', (tester) async {
      backend.json('GET', '/collection-reminders/holds', {'onHold': false});
      await pump(
        tester,
        const Scaffold(body: ReminderHoldTile(documentId: 'd1')),
        preset: Preset.employee,
      );
      expect(find.byKey(const Key('reminder-hold-document')), findsNothing);
      expect(backend.calls('GET', '/collection-reminders/holds'), isEmpty);
    });
  });
}
