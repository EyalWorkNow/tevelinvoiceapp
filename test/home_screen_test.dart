// H · בית widget tests (squad A, §6.H): blocks per preset, cache-first,
// states, taps into L / C / D, J10 (1 tap), 200% text.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/inbox_api.dart';
import 'package:invoice/app_shell.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/activity/activity_screen.dart';
import 'package:invoice/screens/compose/compose_screen.dart';
import 'package:invoice/screens/document/document_screen.dart';
import 'package:invoice/screens/home/home_controller.dart';
import 'package:invoice/screens/home/home_screen.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/session.dart';
import 'package:invoice/ui/theme.dart';
import 'package:invoice/ui/widgets/primary_button.dart';

import 'fakes/fake_api.dart';

final today = DateTime(2026, 10, 30);

List<Map<String, dynamic>> manyDocs() => [
  docJson(
    'r1',
    number: '101',
    customerName: 'דנה כהן',
    open: 118000,
    issueDate: '2026-10-28',
  ),
  docJson(
    'r2',
    number: '102',
    customerName: 'רון לוי',
    open: 50000,
    issueDate: '2026-09-01',
  ),
  docJson(
    'r3',
    type: 'TAX_INVOICE_RECEIPT',
    number: '103',
    customerName: 'נועה',
  ),
  docJson('r4', type: 'RECEIPT', number: '104', customerName: 'יוסי'),
  docJson('r5', status: 'DRAFT', customerName: 'טל', total: 60000),
  docJson('r6', number: '106', customerName: 'שישי'),
  docJson(
    'rej',
    status: 'DRAFT',
    submittedBy: 'u-me',
    rejection: {'reason': 'חסר פירוט'},
  ),
];

void main() {
  late FakeBackend backend;
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('home_screen_test');
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

  Future<HomeController> pumpHome(
    WidgetTester tester,
    Preset preset, {
    List<Map<String, dynamic>>? documents,
    Map<String, dynamic>? dashboard,
    List<Map<String, dynamic>> approvals = const [],
    Map<String, dynamic>? mobileInbox,
    int businesses = 1,
    bool load = true,
    double textScale = 1,
    Size size = const Size(1170, 2532),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    installInboxFakes(
      backend,
      documents: documents ?? manyDocs(),
      dashboard:
          dashboard ??
          dashboardJson(unpaid: 1240000, overdue: 320000, overdueCount: 3),
      approvals: approvals,
      mobileInbox: mobileInbox,
    );
    await tester.runAsync(
      () => signInAs(backend, preset, businesses: businesses),
    );
    final c = HomeController(now: () => today);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: messengerKey,
        navigatorObservers: [AppRouter.instance.observer],
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
        home: HomeScreen(controller: c),
      ),
    );
    if (load) {
      await tester.runAsync(() => c.load());
      await tester.pumpAndSettle();
    }
    return c;
  }

  testWidgets(
    'load still in flight when H is disposed (sign-out) → no notify after dispose',
    (tester) async {
      installInboxFakes(
        backend,
        documents: manyDocs(),
        dashboard: dashboardJson(unpaid: 1000),
      );
      await tester.runAsync(() => signInAs(backend, Preset.owner));
      final c = HomeController(now: () => today);
      await tester.runAsync(() async {
        final pending = c.load();
        c.dispose();
        await pending; // threw "used after being disposed" before the fix
      });
    },
  );

  testWidgets(
    'owner: money card, both intents, ≤3 cards + "עוד N", 5 recent, no PrimaryButton',
    (tester) async {
      await pumpHome(
        tester,
        Preset.owner,
        approvals: [
          {
            'id': 'p1',
            'documentType': 'TAX_INVOICE',
            'totalMinor': '500000',
            'submittedBy': 'u-emp',
          },
        ],
      );
      expect(find.text('שלום, דנה'), findsOneWidget);
      expect(find.byKey(const Key('home-role-tag')), findsNothing);
      expect(find.text('מגיע לך'), findsOneWidget);
      expect(find.text('מתוכם באיחור'), findsOneWidget);
      expect(find.byKey(const Key('intent-paid')), findsOneWidget);
      expect(find.byKey(const Key('intent-request')), findsOneWidget);
      // RTL: "קיבלתי תשלום" on the right.
      expect(
        tester.getCenter(find.byKey(const Key('intent-paid'))).dx,
        greaterThan(
          tester.getCenter(find.byKey(const Key('intent-request'))).dx,
        ),
      );
      // approval, rejected, unfinished, overdue → 3 shown + "עוד 1 ›".
      expect(find.byKey(const Key('inbox-APPROVAL_NEEDED')), findsOneWidget);
      expect(find.text('מסמך אחד ממתין לאישורך'), findsOneWidget);
      expect(find.byKey(const Key('inbox-MY_REJECTED')), findsOneWidget);
      expect(find.text('המסמך לדנה כהן נדחה: חסר פירוט'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('home-more-cards')),
        200,
      );
      expect(find.text('עוד 1 ›'), findsOneWidget);
      expect(find.byKey(const Key('inbox-OVERDUE')), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const Key('home-all-activity')),
        200,
      );
      expect(find.byKey(const Key('doc-r1')), findsOneWidget);
      expect(find.byKey(const Key('doc-r5')), findsOneWidget);
      expect(find.byKey(const Key('doc-r6')), findsNothing); // 5 rows only
      expect(find.byType(PrimaryButton), findsNothing); // AT-90: read screen
      expect(find.textContaining('אין הרשאה'), findsNothing);
    },
  );

  testWidgets('recent activity search opens inline and stays on home', (
    tester,
  ) async {
    await pumpHome(tester, Preset.owner);
    await tester.scrollUntilVisible(
      find.byKey(const Key('home-recent-search')),
      240,
    );
    await tester.tap(find.byKey(const Key('home-recent-search')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-recent-search-field')), findsOneWidget);
    expect(find.byType(ActivityScreen), findsNothing);
    expect(find.text('פעילות אחרונה'), findsNothing);
  });

  testWidgets(
    'money card → L "לא שולם"; "עוד N" → L "לטיפול"; row → D; intents → C',
    (tester) async {
      await pumpHome(
        tester,
        Preset.owner,
        approvals: [
          {
            'id': 'p1',
            'documentType': 'TAX_INVOICE',
            'totalMinor': '500000',
            'submittedBy': 'u-emp',
          },
        ],
      );
      Future<void> back() async {
        navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byKey(const Key('home-money')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ActivityScreen>(find.byType(ActivityScreen)).chip,
        'unpaid',
      );
      await back();

      await tester.tap(find.byKey(const Key('intent-paid')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ComposeScreen>(find.byType(ComposeScreen)).intent,
        'PAID',
      );
      await back();
      await tester.tap(find.byKey(const Key('intent-request')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ComposeScreen>(find.byType(ComposeScreen)).intent,
        'REQUEST',
      );
      await back();

      // J7 first tap: the single approval card opens D on that document.
      await tester.tap(find.byKey(const Key('inbox-APPROVAL_NEEDED')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<DocumentScreen>(find.byType(DocumentScreen)).id,
        'p1',
      );
      await back();

      await tester.tap(find.byKey(const Key('inbox-MY_REJECTED')));
      await tester.pumpAndSettle();
      final compose = tester.widget<ComposeScreen>(find.byType(ComposeScreen));
      expect(compose.draftId, 'rej');
      expect(compose.intent, 'TYPE:305');
      await back();

      await tester.scrollUntilVisible(
        find.byKey(const Key('home-more-cards')),
        150,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-more-cards')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ActivityScreen>(find.byType(ActivityScreen)).chip,
        'inbox',
      );
      await back();

      await tester.ensureVisible(find.byKey(const Key('doc-r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('doc-r1')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<DocumentScreen>(find.byType(DocumentScreen)).id,
        'r1',
      );
    },
  );

  testWidgets(
    'employee: no money card, only "בקש תשלום", greeting, own cards',
    (tester) async {
      await pumpHome(tester, Preset.employee);
      expect(find.byKey(const Key('home-money')), findsNothing);
      expect(find.byKey(const Key('intent-paid')), findsNothing); // §19 q7
      expect(find.byKey(const Key('intent-request')), findsOneWidget);
      expect(find.byKey(const Key('home-greeting-name')), findsOneWidget);
      expect(find.byKey(const Key('inbox-OVERDUE')), findsNothing);
      expect(find.byKey(const Key('inbox-MY_REJECTED')), findsOneWidget);
      expect(
        find.textContaining('₪'),
        findsWidgets,
      ); // rows keep amounts (P0, §12.5)
    },
  );

  testWidgets('employee + מפיק בעצמו gets "קיבלתי תשלום"', (tester) async {
    await pumpHome(tester, Preset.employeeIssuer);
    expect(find.byKey(const Key('intent-paid')), findsOneWidget);
    expect(find.byKey(const Key('home-money')), findsNothing);
  });

  testWidgets('צפייה בלבד: money card, no intents, no "לטיפול"', (
    tester,
  ) async {
    await pumpHome(tester, Preset.viewer);
    expect(find.byKey(const Key('home-money')), findsOneWidget);
    expect(find.byKey(const Key('intent-paid')), findsNothing);
    expect(find.byKey(const Key('intent-request')), findsNothing);
    expect(find.text('לטיפול'), findsNothing);
    expect(find.byKey(const Key('home-greeting-name')), findsOneWidget);
  });

  testWidgets(
    'new business: the first-document hint above the buttons; "הכל מטופל ✓"',
    (tester) async {
      await pumpHome(
        tester,
        Preset.owner,
        documents: const [],
        dashboard: dashboardJson(),
      );
      expect(find.text('הפק את הראשונה בפחות מדקה'), findsOneWidget);
      expect(
        tester.getCenter(find.text('הפק את הראשונה בפחות מדקה')).dy,
        lessThan(tester.getCenter(find.byKey(const Key('intent-paid'))).dy),
      );
      expect(find.text('הכל מטופל ✓'), findsOneWidget);
      expect(find.text('אחרונים'), findsNothing);
    },
  );

  testWidgets('J10: "שלח תזכורות" is ONE tap → e-mails sent + toast', (
    tester,
  ) async {
    await pumpHome(
      tester,
      Preset.owner,
      documents: [
        docJson(
          'late',
          open: 118000,
          number: '1',
          customerId: 'c1',
          issueDate: '2026-01-01',
        ),
      ],
    );
    backend.json('GET', '/customers', {
      'customers': [
        {
          'id': 'c1',
          'name': 'דנה כהן',
          'email': 'dana@example.test',
          'phone': '0501234567',
        },
      ],
    });
    expect(find.byKey(const Key('inbox-OVERDUE')), findsOneWidget);
    expect(find.text('3 חשבוניות באיחור'), findsOneWidget);
    await tester.tap(find.byKey(const Key('inbox-OVERDUE')));
    await tester.runAsync(() async {
      for (
        var i = 0;
        i < 20 && backend.calls('POST', '/deliveries/:id/process').isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    expect(backend.calls('POST', '/documents/:id/send'), hasLength(1));
    expect(backend.calls('POST', '/deliveries/:id/process'), hasLength(1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('נשלחה תזכורת אחת במייל'), findsOneWidget);
  });

  testWidgets(
    'cache first: a later network failure keeps the cached H + offline banner',
    (tester) async {
      final c = await pumpHome(tester, Preset.owner);
      expect(find.text('מגיע לך'), findsOneWidget);
      backend.on(
        'GET',
        '/dashboard',
        (_) => throw const SocketException('down'),
      );
      final fresh = HomeController(now: () => today);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('he', 'IL'),
          supportedLocales: const [Locale('he', 'IL')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: buildTheme(Brightness.light),
          home: HomeScreen(key: UniqueKey(), controller: fresh),
        ),
      );
      await tester.runAsync(() => fresh.load());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // banner grows in
      expect(fresh.error?.isNetwork, isTrue);
      expect(find.text('מגיע לך'), findsOneWidget); // painted from the cache
      expect(find.text('אין חיבור – מציג נתונים אחרונים'), findsOneWidget);
      expect(c.data, isNotNull);
    },
  );

  testWidgets('loading = skeleton; error without cache = message + "נסה שוב"', (
    tester,
  ) async {
    final c = await pumpHome(tester, Preset.owner, load: false);
    expect(
      find.byKey(const Key('intent-paid')),
      findsOneWidget,
    ); // buttons never wait
    expect(find.byType(ListView), findsOneWidget);
    backend.error('GET', '/dashboard', 500, 'INTERNAL');
    await tester.runAsync(() => c.load());
    await tester.pumpAndSettle();
    expect(find.text('נסה שוב'), findsWidgets);
  });

  testWidgets('more than one business: the header is a button (→ S14)', (
    tester,
  ) async {
    await pumpHome(tester, Preset.owner, businesses: 2);
    expect(find.byKey(const Key('home-switch-business')), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const Key('home-switch-business'))),
      matchesSemantics(
        isButton: true,
        isHeader: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
        label: 'סטודיו תבל',
        hint: 'נגיעה להחלפת עסק',
      ),
    );
  });

  testWidgets('one business: the header does nothing', (tester) async {
    await pumpHome(tester, Preset.owner);
    expect(find.byKey(const Key('home-switch-business')), findsNothing);
  });

  testWidgets('AT-70: 200% text on a 320pt phone — no overflow', (
    tester,
  ) async {
    await pumpHome(
      tester,
      Preset.owner,
      textScale: 2,
      size: const Size(960, 2079),
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const Key('home-all-activity')),
      300,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('intent buttons and cards speak Hebrew to VoiceOver', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpHome(tester, Preset.owner);
    expect(find.bySemanticsLabel(RegExp('קיבלתי תשלום')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('בקש תשלום')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('מגיע לך')), findsWidgets);
    handle.dispose();
  });

  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 50 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
  }

  testWidgets(
    'BE-05: H reads /mobile/inbox only; card words from `detail`; "עד dd/mm"',
    (tester) async {
      await pumpHome(
        tester,
        Preset.owner,
        mobileInbox: mobileInboxJson(
          open: 1240000,
          overdue: 320000,
          cards: [
            inboxCardJson(
              'TAX_INVOICE_DUE',
              amount: '118000',
              documentIds: ['t300'],
              action: 'ISSUE_TAX_INVOICE',
              detail: {
                'documentType': 'TRANSACTION_INVOICE',
                'customerName': 'רון',
                'dueBy': '2026-11-13',
              },
            ),
          ],
          recent: [recentJson('r1', number: '101', open: 118000)],
        ),
      );
      expect(backend.calls('GET', '/dashboard'), isEmpty);
      expect(backend.calls('GET', '/documents'), isEmpty);
      expect(
        find.text('רון שילם על חשבון עסקה – הפק חשבונית מס עד 13/11'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('doc-r1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('inbox-TAX_INVOICE_DUE')));
      await tester.pumpAndSettle();
      final c = tester.widget<ComposeScreen>(find.byType(ComposeScreen));
      expect((c.intent, c.fromDocId), ('TYPE:305', 't300'));
    },
  );

  testWidgets('SIGNING_LOCKED "חתום" signs in place: one tap, no D', (
    tester,
  ) async {
    await pumpHome(
      tester,
      Preset.owner,
      mobileInbox: mobileInboxJson(
        open: 0,
        cards: [
          inboxCardJson(
            'SIGNING_LOCKED',
            count: 2,
            documentIds: ['ap1', 'ap2'],
            action: 'SIGN',
          ),
        ],
      ),
    );
    backend.json('POST', '/documents/:id/sign', {'signed': true});
    await tester.tap(find.byKey(const Key('inbox-SIGNING_LOCKED')));
    await waitFor(
      tester,
      () => backend.calls('POST', '/documents/:id/sign').length >= 2,
    );
    expect(
      [for (final r in backend.calls('POST', '/documents/:id/sign')) r.path],
      ['/documents/ap1/sign', '/documents/ap2/sign'],
    );
    expect(find.byType(DocumentScreen), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('2 מסמכים נחתמו'), findsOneWidget);
  });

  testWidgets('SHAAM_RENEW "המשך במחשב" e-mails the link (BE-35) in one tap', (
    tester,
  ) async {
    await pumpHome(
      tester,
      Preset.owner,
      mobileInbox: mobileInboxJson(
        open: 0,
        cards: [
          inboxCardJson(
            'SHAAM_RENEW',
            action: 'RENEW_SHAAM',
            detail: {
              'shaamStatus': 'CONNECTED',
              'refreshTokenExpiresAt': '2026-11-04T12:00:00Z',
            },
          ),
        ],
      ),
    );
    backend.on(
      'POST',
      '/mobile/web-handoff',
      (_) => const FakeResponse(202, {'sent': true}),
    );
    expect(find.text('החיבור לרשות המסים יפוג בעוד 5 ימים'), findsOneWidget);
    await tester.tap(find.byKey(const Key('inbox-SHAAM_RENEW')));
    await waitFor(
      tester,
      () => backend.calls('POST', '/mobile/web-handoff').isNotEmpty,
    );
    expect(backend.last('POST', '/mobile/web-handoff')!.body, {
      'topic': 'TAX_AUTHORITY',
    });
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('שלחנו לך קישור במייל – פתח אותו במחשב'), findsOneWidget);
  });

  testWidgets(
    '§4.6 live role change צפייה בלבד → עובד: money card goes at once, intents appear',
    (tester) async {
      await pumpHome(tester, Preset.viewer);
      expect(find.byKey(const Key('home-money')), findsOneWidget);
      backend.json('GET', '/me', meJson(Preset.employee));
      await tester.runAsync(() async {
        await session.refreshBusiness(); // foreground refresh of /me
        await Future<void>.delayed(
          const Duration(milliseconds: 50),
        ); // the reload H starts
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('intent-request')), findsOneWidget);
      expect(find.byKey(const Key('home-money')), findsNothing);
    },
  );
}
