// Tester feedback 2026-11-18 (FIXA): the Home bell (עדכונים), global search,
// customer events in "מסמכים אחרונים", payment requests in "מי חייב לי".

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/api/notifications_api.dart';
import 'package:invoice/api/search_api.dart';
import 'package:invoice/api/inbox_api.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/home/home_controller.dart';
import 'package:invoice/screens/home/home_screen.dart';
import 'package:invoice/util/labels/customer_crm_he.dart';
import 'package:invoice/util/labels/people_he.dart';
import 'package:invoice/screens/home/global_search_screen.dart';
import 'package:invoice/screens/home/notifications_screen.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/theme.dart';
import 'package:invoice/util/labels/debts_he.dart';

import 'fakes/fake_api.dart';

Widget _app(Widget home) => MaterialApp(
  navigatorKey: navigatorKey,
  scaffoldMessengerKey: messengerKey,
  navigatorObservers: [AppRouter.instance.observer],
  locale: const Locale('he', 'IL'),
  supportedLocales: const [Locale('he', 'IL')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: buildTheme(Brightness.light),
  home: home,
);

Map<String, dynamic> _item(
  String id,
  String kind,
  String title,
  String route, {
  bool read = false,
  String at = '2026-11-18T10:05:00Z',
}) => {
  'id': id,
  'kind': kind,
  'title': title,
  'route': route,
  'occurredAt': at,
  'read': read,
  'subject': null,
};

void main() {
  late FakeBackend backend;
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('fixa_feedback_test');
    AppCache.directoryProvider = () async => tmp;
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    resetSession();
    backend = FakeBackend()..install();
    notificationsUnread.value = -1;
    await AppCache.clearAll();
  });

  group('עדכונים (the Home bell list)', () {
    const a = 'aaaaaaaa-0000-4000-8000-000000000001';
    const b = 'aaaaaaaa-0000-4000-8000-000000000002';

    void feed({List<Map<String, dynamic>>? items, int unread = 2}) {
      backend.json('GET', '/mobile/notifications', {
        'items':
            items ??
            [
              _item(
                a,
                'QUOTE_ACCEPTED',
                'משה כהן אישר/ה את הצעת המחיר',
                '/quote/q1',
              ),
              _item(
                b,
                'SIGN_REQUEST_COMPLETED',
                'רונית חתם/ה על "חוזה"',
                '/sign-request/s1',
              ),
            ],
        'unreadCount': unread,
        'nextBefore': null,
      });
    }

    testWidgets('lists updates, unread dots, badge count from the server', (
      tester,
    ) async {
      feed();
      await tester.runAsync(() => signInAs(backend, Preset.owner));
      await tester.pumpWidget(
        _app(NotificationsScreen(now: () => DateTime(2026, 11, 18, 14))),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.text('עדכונים'), findsOneWidget);
      expect(find.text('משה כהן אישר/ה את הצעת המחיר'), findsOneWidget);
      expect(find.byKey(const Key('notification-unread-$a')), findsOneWidget);
      expect(notificationsUnread.value, 2);
      expect(find.byKey(const Key('notifications-mark-all')), findsOneWidget);
    });

    testWidgets('opening עדכונים clears the app icon badge (invoice#60)', (
      tester,
    ) async {
      feed();
      final calls = <String>[];
      const channel = MethodChannel('tevel/system_notices');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.runAsync(() => signInAs(backend, Preset.owner));
      await tester.pumpWidget(_app(const NotificationsScreen()));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(calls, contains('clearBadge'));
    });

    testWidgets('"סמן הכול כנקרא" posts {all:true} and clears the dots', (
      tester,
    ) async {
      feed();
      backend.json('POST', '/mobile/notifications/read', {'unreadCount': 0});
      await tester.runAsync(() => signInAs(backend, Preset.owner));
      await tester.pumpWidget(_app(const NotificationsScreen()));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notifications-mark-all')));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(backend.last('POST', '/mobile/notifications/read')!.body, {
        'all': true,
      });
      expect(find.byKey(const Key('notification-unread-$a')), findsNothing);
      expect(notificationsUnread.value, 0);
      expect(find.byKey(const Key('notifications-mark-all')), findsNothing);
    });

    testWidgets('tap marks that item read and opens its screen', (
      tester,
    ) async {
      feed();
      backend.json('POST', '/mobile/notifications/read', {'unreadCount': 1});
      await tester.runAsync(() => signInAs(backend, Preset.owner));
      await tester.pumpWidget(_app(const NotificationsScreen()));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notification-$a')));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(backend.last('POST', '/mobile/notifications/read')!.body, {
        'ids': [a],
      });
      expect(find.byKey(const Key('notification-unread-$a')), findsNothing);
      expect(find.byKey(const Key('notification-unread-$b')), findsOneWidget);
    });

    testWidgets('empty feed explains what will appear', (tester) async {
      feed(items: [], unread: 0);
      await tester.runAsync(() => signInAs(backend, Preset.owner));
      await tester.pumpWidget(_app(const NotificationsScreen()));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notifications-empty')), findsOneWidget);
    });

    testWidgets('a push (notificationsVersion) reloads the open list', (
      tester,
    ) async {
      feed(items: [], unread: 0);
      await tester.runAsync(() => signInAs(backend, Preset.owner));
      await tester.pumpWidget(_app(const NotificationsScreen()));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      feed(unread: 2);
      notifyNotificationsChanged();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.text('משה כהן אישר/ה את הצעת המחיר'), findsOneWidget);
    });
  });

  group('global search', () {
    testWidgets('groups hits by kind; amounts only when the server sends them', (
      tester,
    ) async {
      final queries = <String>[];
      await tester.pumpWidget(
        _app(
          GlobalSearchScreen(
            search: (q) async {
              queries.add(q);
              return [
                const SearchHit(
                  kind: SearchHitKind.quote,
                  id: 'q1',
                  name: 'משה כהן',
                  number: '7',
                  date: '2026-11-17',
                ),
                SearchHit(
                  kind: SearchHitKind.document,
                  id: 'd1',
                  name: 'משה כהן',
                  documentType: 'TRANSACTION_INVOICE',
                  number: '12',
                  totalMinor: BigInt.from(59000),
                ),
              ];
            },
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('global-search-field')),
        'הצעת מחיר של כהן',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(queries, ['הצעת מחיר של כהן']);
      expect(find.text('הצעות מחיר'), findsOneWidget);
      expect(find.text('מסמכים'), findsOneWidget);
      expect(find.text('הצעת מחיר 7'), findsOneWidget);
      expect(find.text('חשבון עסקה 12'), findsOneWidget);
      expect(find.textContaining('590'), findsOneWidget);
    });

    testWidgets('no results → a hint, not a blank screen', (tester) async {
      await tester.pumpWidget(
        _app(GlobalSearchScreen(search: (_) async => const [])),
      );
      await tester.enterText(
        find.byKey(const Key('global-search-field')),
        'zzz',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('global-search-empty')), findsOneWidget);
    });

    test('search hit parsing ignores unknown kinds', () {
      expect(SearchHit.fromJson({'kind': 'x', 'id': '1'}), isNull);
      final h = SearchHit.fromJson({
        'kind': 'document',
        'id': 'd',
        'totalMinor': null,
      })!;
      expect(h.totalMinor, isNull);
    });
  });

  group('"מסמכים אחרונים" carries customer events', () {
    test('recentEvents parse and round-trip through the cache', () {
      final data = HomeData.fromJson({
        'money': null,
        'cards': [],
        'recent': [],
        'recentEvents': [
          {
            'kind': 'QUOTE_ACCEPTED',
            'id': 'q1',
            'customerName': 'משה כהן',
            'label': '7',
            'at': '2026-11-18T10:00:00Z',
          },
          {'kind': 'SOMETHING_ELSE', 'id': 'x', 'at': '2026-11-18T10:00:00Z'},
        ],
      });
      expect(data.recentEvents.map((e) => e.kind), ['QUOTE_ACCEPTED']);
      final again = HomeData.fromJson(data.toJson());
      expect(again.recentEvents.single.customerName, 'משה כהן');
    });
  });

  test('"מי חייב לי" names a 300 as a payment request', () {
    expect(
      DebtsHe.documentLine('TRANSACTION_INVOICE', '12'),
      'בקשת תשלום מס׳ 12',
    );
    expect(DebtsHe.documentLine('TAX_INVOICE', null), 'חשבונית מס');
    expect(DebtsHe.headerLabel, 'יתרה לגבייה');
  });

  group('Home (H)', () {
    Future<void> pumpHome(
      WidgetTester tester, {
      Map<String, dynamic>? inbox,
      int unread = 3,
    }) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      mobileInboxAvailable = null;
      localUnfinishedProbe = () async => null;
      installInboxFakes(backend, documents: const []);
      backend
        ..json(
          'GET',
          '/mobile/inbox',
          inbox ??
              {
                'money': {'openMinor': '59000', 'overdueMinor': '0'},
                'cards': [],
                'recent': [
                  {
                    'id': 'd1',
                    'documentType': 'TRANSACTION_INVOICE',
                    'status': 'FINALIZED',
                    'documentNumber': '12',
                    'customerName': 'דנה לוי',
                    'totalMinor': '59000',
                    'openMinor': '59000',
                    'issueDate': '2026-11-17',
                    'cancelled': false,
                    'createdAt': '2026-11-17T09:00:00Z',
                  },
                ],
                'recentEvents': [
                  {
                    'kind': 'QUOTE_ACCEPTED',
                    'id': 'q1',
                    'customerName': 'משה כהן',
                    'label': '7',
                    'at': '2026-11-18T10:00:00Z',
                  },
                ],
              },
        )
        ..json('GET', '/mobile/notifications/unread-count', {
          'unreadCount': unread,
        });
      await tester.runAsync(() => signInAs(backend, Preset.owner));
      final c = HomeController(now: () => DateTime(2026, 11, 18));
      await tester.pumpWidget(_app(HomeScreen(controller: c)));
      await tester.runAsync(() async {
        await c.load();
        await refreshNotificationsUnread();
      });
      await tester.pumpAndSettle();
    }

    testWidgets('bell with unread badge in the header; tap opens עדכונים', (
      tester,
    ) async {
      await pumpHome(tester);
      expect(find.byKey(const Key('home-bell')), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      backend.json('GET', '/mobile/notifications', {
        'items': [],
        'unreadCount': 0,
        'nextBefore': null,
      });
      await tester.tap(find.byKey(const Key('home-bell')));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsScreen), findsOneWidget);
    });

    testWidgets('no badge when nothing is unread', (tester) async {
      await pumpHome(tester, unread: 0);
      expect(find.byKey(const Key('home-bell')), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('search field on Home opens the global search', (
      tester,
    ) async {
      await pumpHome(tester);
      expect(find.byKey(const Key('home-search')), findsOneWidget);
      await tester.tap(find.byKey(const Key('home-search')));
      await tester.pumpAndSettle();
      expect(find.byType(GlobalSearchScreen), findsOneWidget);
    });

    testWidgets(
      'מסמכים אחרונים: the accepted quote shows above the older document',
      (tester) async {
        await pumpHome(tester);
        final event = find.byKey(const Key('recent-event-q1'));
        final doc = find.byKey(const Key('doc-d1'));
        expect(event, findsOneWidget);
        expect(doc, findsOneWidget);
        expect(
          tester.getTopLeft(event).dy < tester.getTopLeft(doc).dy,
          isTrue,
        );
        expect(find.textContaining('אישר/ה הצעת מחיר'), findsOneWidget);
      },
    );

    testWidgets('money card says what the number is: "יתרה לגבייה"', (
      tester,
    ) async {
      await pumpHome(tester);
      expect(find.text('יתרה לגבייה'), findsOneWidget);
      expect(find.text('מגיע לך'), findsNothing);
    });
  });

  test('labels: natural CRM heading and a clear new-customer CTA', () {
    expect(CustomerCrmHe.upcomingTitle, 'משימות קרובות');
    expect(PeopleHe.addCustomer, '+ לקוח חדש');
  });
}
