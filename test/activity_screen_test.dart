// L · פעילות widget tests (squad A, §6.L): chips, month groups, F10 words,
// search, 500 cap, "לטיפול" chip, empty/error/offline, BE-10 search.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/inbox_api.dart';
import 'package:invoice/api/models/models.dart' show DocumentSummary;
import 'package:invoice/app_shell.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/activity/activity_screen.dart';
import 'package:invoice/screens/compose/compose_screen.dart';
import 'package:invoice/screens/document/document_screen.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/session.dart';
import 'package:invoice/ui/theme.dart';
import 'package:invoice/ui/widgets/primary_button.dart';

import 'fakes/fake_api.dart';

final today = DateTime(2026, 10, 30);

List<Map<String, dynamic>> docs() => [
  docJson(
    'open',
    number: '1043',
    customerName: 'דנה כהן',
    total: 120000,
    open: 120000,
    issueDate: '2026-10-28',
  ),
  docJson(
    'late',
    number: '1001',
    customerName: 'רון לוי',
    total: 50000,
    open: 50000,
    issueDate: '2026-09-01',
  ),
  docJson(
    'paid',
    type: 'TAX_INVOICE_RECEIPT',
    number: '1044',
    customerName: 'נועה',
    issueDate: '2026-10-29',
  ),
  docJson(
    'draft',
    status: 'DRAFT',
    customerName: 'טל',
    total: 60000,
    issueDate: null,
  ),
  docJson(
    'sent',
    number: '1045',
    customerName: 'יוסי',
    total: 30000,
    open: 30000,
    issueDate: '2026-10-27',
    sentAt: '2026-10-27T10:00:00Z',
  ),
];

void main() {
  late FakeBackend backend;
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('activity_screen_test');
    AppCache.directoryProvider = () async => tmp;
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    resetSession();
    currentTab.value = AppTab.home;
    mobileInboxAvailable = null;
    localUnfinishedProbe = () async => null;
    backend = FakeBackend()..install();
    await AppCache.clearAll();
  });

  Future<ActivityController> pumpActivity(
    WidgetTester tester, {
    Preset preset = Preset.owner,
    String? chip,
    List<Map<String, dynamic>>? documents,
    List<Map<String, dynamic>> quotes = const [],
    List<Map<String, dynamic>> approvals = const [],
    bool withCards = false,
    bool be10 = false,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    installInboxFakes(
      backend,
      documents: documents ?? docs(),
      quotes: quotes,
      approvals: approvals,
      be10: be10,
    );
    await tester.runAsync(() => signInAs(backend, preset));
    final c = ActivityController(now: () => today);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [AppRouter.instance.observer],
        locale: const Locale('he', 'IL'),
        supportedLocales: const [Locale('he', 'IL')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildTheme(Brightness.light),
        home: ActivityScreen(chip: chip, controller: c),
      ),
    );
    await tester.runAsync(() => c.load(withCards: withCards));
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('six fixed chips, month groups, F10 words, no PrimaryButton', (
    tester,
  ) async {
    await pumpActivity(tester);
    for (final chip in [
      'הכל',
      'לא שולם',
      'טיוטות',
      'הצעות',
      'שולם',
      'לטיפול',
    ]) {
      expect(
        find.descendant(
          of: find.byKey(const Key('activity-chips')),
          matching: find.text(chip),
        ),
        findsOneWidget,
      );
    }
    expect(find.byKey(const Key('activity-chips')), findsOneWidget);
    expect(find.text('אוקטובר 2026'), findsOneWidget);
    expect(find.text('ספטמבר 2026'), findsOneWidget);
    expect(find.text('ממתין לתשלום'), findsNWidgets(2));
    expect(find.text('באיחור'), findsOneWidget); // issue + 30 < today
    expect(find.text('שולם'), findsNWidgets(2)); // filter chip + paid row
    expect(find.text('טיוטה'), findsOneWidget);
    expect(find.text('נשלח'), findsOneWidget); // attribute, not status
    expect(find.byType(PrimaryButton), findsNothing);
    expect(find.byKey(const Key('activity-capped')), findsNothing);
    // One page; the 500 cap only for a server that does not page (2.5).
    expect(backend.last('GET', '/documents')!.query['limit'], '100');
  });

  testWidgets(
    'chips: לא שולם = ?unpaid=1 rows; טיוטות; הצעות with quote words',
    (tester) async {
      await pumpActivity(
        tester,
        quotes: [
          {
            'id': 'q1',
            'title': 'עיצוב',
            'status': 'SENT',
            'customer_name': 'רון',
            'totalMinor': '90000',
            'createdAt': '2026-10-01',
          },
          {
            'id': 'q2',
            'title': 'לוגו',
            'status': 'CONVERTED',
            'customerName': 'דנה',
            'totalMinor': '5000',
            'createdAt': '2026-08-01',
          },
        ],
      );
      expect(
        backend.calls('GET', '/documents').any((r) => r.query['unpaid'] == '1'),
        isTrue,
      );
      await tester.tap(find.text('לא שולם'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('doc-open')), findsOneWidget);
      expect(find.byKey(const Key('doc-paid')), findsNothing);
      expect(find.byKey(const Key('doc-draft')), findsNothing);

      await tester.tap(find.text('טיוטות'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('doc-draft')), findsOneWidget);
      expect(find.byKey(const Key('doc-open')), findsNothing);

      await tester.tap(find.text('הצעות'));
      await tester.pumpAndSettle();
      expect(find.text('אצל הלקוח'), findsOneWidget);
      expect(find.text('הפכה לחשבונית'), findsOneWidget);
      expect(find.text('אוגוסט 2026'), findsOneWidget);
      await tester.tap(find.byKey(const Key('quote-q1')));
      await tester.pumpAndSettle();
      final d = tester.widget<DocumentScreen>(find.byType(DocumentScreen));
      expect((d.id, d.isQuote), ('q1', true));
    },
  );

  testWidgets('initial chip from the route; tapping a row opens D', (
    tester,
  ) async {
    await pumpActivity(tester, chip: 'unpaid');
    expect(find.byKey(const Key('doc-paid')), findsNothing);
    await tester.tap(find.byKey(const Key('doc-late')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<DocumentScreen>(find.byType(DocumentScreen)).id,
      'late',
    );
  });

  testWidgets(
    'search: "1,200" by amount, "1043" by number, name; nothing → "לא נמצא"',
    (tester) async {
      await pumpActivity(tester);
      await tester.enterText(find.byKey(const Key('activity-search')), '1,200');
      await tester.pump();
      expect(find.byKey(const Key('doc-open')), findsOneWidget);
      expect(find.byKey(const Key('doc-late')), findsNothing);
      await tester.enterText(find.byKey(const Key('activity-search')), '1043');
      await tester.pump();
      expect(find.byKey(const Key('doc-open')), findsOneWidget);
      expect(find.byKey(const Key('doc-paid')), findsNothing);
      await tester.enterText(find.byKey(const Key('activity-search')), 'רון');
      await tester.pump();
      expect(find.byKey(const Key('doc-late')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('activity-search')),
        'אין כזה',
      );
      await tester.pump();
      expect(find.text('לא נמצא'), findsOneWidget);
      await tester.pump(
        const Duration(milliseconds: 400),
      ); // debounce (no BE-10 → local only)
      expect(
        backend
            .calls('GET', '/documents')
            .where((r) => r.query.containsKey('q')),
        isEmpty,
      );
    },
  );

  testWidgets('500 rows → "מוצגים 500 המסמכים האחרונים"', (tester) async {
    await pumpActivity(
      tester,
      documents: [
        for (var i = 0; i < 520; i++)
          docJson('d$i', number: '$i', issueDate: '2026-10-01'),
      ],
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('activity-capped')),
      3000,
      scrollable: find.descendant(
        of: find.byKey(const Key('activity-list')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('מוצגים 500 המסמכים האחרונים'), findsOneWidget);
  });

  testWidgets('"לטיפול" chip: from "עוד N" → every card, not only 3', (
    tester,
  ) async {
    await pumpActivity(
      tester,
      chip: 'inbox',
      withCards: true,
      documents: [
        ...docs(),
        docJson(
          'rej',
          status: 'DRAFT',
          submittedBy: 'u-me',
          rejection: {'reason': 'חסר פירוט'},
        ),
        docJson(
          't300',
          type: 'TRANSACTION_INVOICE',
          number: '7',
          customerId: 'c9',
          open: 0,
        ),
      ],
      approvals: [
        {
          'id': 'p1',
          'documentType': 'TAX_INVOICE',
          'totalMinor': '500000',
          'submittedBy': 'u-emp',
        },
        {
          'id': 'p2',
          'documentType': 'TAX_INVOICE',
          'totalMinor': '100000',
          'submittedBy': 'u-emp',
        },
      ],
    );
    expect(find.text('לטיפול'), findsOneWidget);
    expect(find.byKey(const Key('activity-inbox')), findsOneWidget);
    expect(find.text('2 ממתינים לאישורך'), findsOneWidget);
    expect(find.byKey(const Key('inbox-MY_REJECTED')), findsOneWidget);
    expect(find.byKey(const Key('inbox-TAX_INVOICE_DUE')), findsOneWidget);
    expect(find.byKey(const Key('inbox-UNFINISHED')), findsOneWidget);
    // many approvals → "פתח" stays on L with the inbox chip
    await tester.tap(find.byKey(const Key('inbox-TAX_INVOICE_DUE')));
    await tester.pumpAndSettle();
    final c = tester.widget<ComposeScreen>(find.byType(ComposeScreen));
    expect((c.intent, c.fromDocId), ('TYPE:305', 't300'));
  });

  testWidgets('empty: teaching action for a drafter; none for צפייה בלבד', (
    tester,
  ) async {
    await pumpActivity(tester, documents: const []);
    expect(find.text('עוד אין מסמכים'), findsOneWidget);
    await tester.tap(find.text('בקש תשלום'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ComposeScreen>(find.byType(ComposeScreen)).intent,
      'REQUEST',
    );
  });

  testWidgets('empty for צפייה בלבד has no button (F5)', (tester) async {
    await pumpActivity(tester, preset: Preset.viewer, documents: const []);
    expect(find.text('עוד אין מסמכים'), findsOneWidget);
    expect(find.text('בקש תשלום'), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets(
    'error without cache → "נסה שוב"; with cache → rows + offline banner',
    (tester) async {
      final c = await pumpActivity(tester);
      expect(find.byKey(const Key('doc-open')), findsOneWidget);
      backend.on(
        'GET',
        '/documents',
        (_) => throw const SocketException('down'),
      );
      await tester.runAsync(() => c.load());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('doc-open')), findsOneWidget);
      expect(find.text('אין חיבור – מציג נתונים אחרונים'), findsOneWidget);

      await tester.runAsync(AppCache.clearAll);
      final fresh = ActivityController(now: () => today);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('he', 'IL'),
          supportedLocales: const [Locale('he', 'IL')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: buildTheme(Brightness.light),
          home: ActivityScreen(key: UniqueKey(), controller: fresh),
        ),
      );
      backend.error('GET', '/documents', 500, 'INTERNAL');
      await tester.runAsync(() => fresh.load());
      await tester.pumpAndSettle();
      expect(find.text('נסה שוב'), findsWidgets);
    },
  );

  testWidgets('BE-10: with `offset` echoed, the search goes to the server', (
    tester,
  ) async {
    final c = await pumpActivity(tester, be10: true);
    expect(c.serverSearch, isTrue);
    await tester.enterText(find.byKey(const Key('activity-search')), 'דנה');
    await tester.runAsync(() => c.search('דנה'));
    await tester.pump(const Duration(milliseconds: 400));
    final q = backend
        .calls('GET', '/documents')
        .where((r) => r.query['q'] == 'דנה');
    expect(q, isNotEmpty);
    expect(q.last.query['limit'], '50');
    expect(find.byKey(const Key('doc-open')), findsOneWidget);
    expect(find.byKey(const Key('doc-late')), findsNothing);
  });

  testWidgets(
    'BE-10: "טען עוד" pages the list; לא שולם searches with unpaid=1',
    (tester) async {
      final many = [
        for (var i = 0; i < 520; i++)
          docJson(
            'm$i',
            number: '$i',
            customerName: 'לקוח $i',
            open: i.isEven ? 1000 : 0,
            issueDate: '2026-10-20',
          ),
      ];
      final c = await pumpActivity(tester, documents: many, be10: true);
      expect(c.all, hasLength(activityPageSize)); // first page only
      expect(
        find.byKey(const Key('activity-capped')),
        findsNothing,
      ); // BE-10: paging instead of the note
      while (c.all!.length < 520) {
        final before = c.all!.length;
        await tester.scrollUntilVisible(
          find.byKey(const Key('activity-more')),
          2000,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.byKey(const Key('activity-more')));
        await tester.runAsync(() async {
          for (var i = 0; i < 50 && c.all!.length == before; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        });
        await tester.pumpAndSettle();
        expect(c.all!.length, greaterThan(before));
      }
      expect(c.all, hasLength(520));
      expect(backend.last('GET', '/documents')!.query['offset'], '500');
      expect(find.byKey(const Key('activity-more')), findsNothing);

      await tester.tap(find.text('לא שולם'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('activity-search')),
        'לקוח 1',
      );
      await tester.runAsync(
        () => c.search('לקוח 1', chip: ActivityChip.unpaid),
      );
      await tester.pump(const Duration(milliseconds: 400));
      final q = backend
          .calls('GET', '/documents')
          .where((r) => r.query['q'] == 'לקוח 1');
      expect(q.last.query['unpaid'], '1');
      expect(
        c
            .docsFor(ActivityChip.unpaid, 'לקוח 1')
            .every((d) => (d.openMinor ?? BigInt.zero) > BigInt.zero),
        isTrue,
      );
    },
  );

  testWidgets(
    'quote rows: second line is "בתוקף עד …" (else "נוצרה …"), not "הצעת מחיר" again',
    (tester) async {
      await pumpActivity(
        tester,
        chip: 'quotes',
        quotes: [
          {
            'id': 'q1',
            'status': 'SENT',
            'totalMinor': '90000',
            'createdAt': '2026-10-01',
            'validUntil': '2026-11-15',
          },
          {
            'id': 'q2',
            'status': 'DRAFT',
            'customerName': 'דנה',
            'totalMinor': '5000',
            'createdAt': '2026-10-02',
          },
        ],
      );
      expect(
        find.text('הצעת מחיר'),
        findsOneWidget,
      ); // q1's title fallback only
      expect(find.textContaining('בתוקף עד'), findsOneWidget);
      expect(find.textContaining('15.11.2026'), findsOneWidget);
      expect(find.textContaining('נוצרה'), findsOneWidget);
    },
  );

  testWidgets(
    'a load that finishes after a business switch + dispose writes nothing and never notifies',
    (tester) async {
      installInboxFakes(backend, documents: docs());
      final gate = Completer<void>();
      backend.on('GET', '/documents', (r) async {
        await gate.future;
        return FakeResponse(200, {'documents': docs()});
      });
      await tester.runAsync(() async {
        final account = await signInAs(backend, Preset.owner, businesses: 2);
        final c = ActivityController(now: () => today);
        final pending = c.load();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        session.business =
            account.businesses[1]; // S14 → B; resetToHome disposes L
        c.dispose();
        gate.complete();
        await pending; // threw "used after being disposed" before the fix
        expect(await AppCache.read('activity_b2'), isNull);
        expect(await AppCache.read('activity_b1'), isNull);
      });
    },
  );

  testWidgets('2.5: filter by document type; title is "מסמכים"', (
    tester,
  ) async {
    await pumpActivity(tester);
    expect(find.text('מסמכים'), findsOneWidget);
    expect(find.text('פעילות'), findsNothing);
    expect(find.byKey(const Key('doc-open')), findsOneWidget);
    await tester.tap(find.byKey(const Key('activity-filter-type')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('activity-type-TAX_INVOICE_RECEIPT')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('doc-paid')), findsOneWidget);
    expect(find.byKey(const Key('doc-open')), findsNothing);
    await tester.tap(find.byKey(const Key('activity-filter-clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('doc-open')), findsOneWidget);
  });

  test(
    '2.5: date range keeps issue dates inside it (inclusive), drops drafts',
    () {
      final rows = [for (final j in docs()) DocumentSummary.fromJson(j)];
      final kept = filterDocuments(
        rows,
        range: DateTimeRange(
          start: DateTime(2026, 10, 27),
          end: DateTime(2026, 10, 28),
        ),
      );
      expect([for (final d in kept) d.id], ['open', 'sent']);
      expect(filterDocuments(rows), same(rows));
    },
  );
}
