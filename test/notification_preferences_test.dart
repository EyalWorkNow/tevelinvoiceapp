// "סוגי התראות" (owner 2026-11-18): per-category on/off over the server's
// GET /mobile/push/catalogue + GET/PUT /mobile/push/preferences, reachable
// from B → התראות and from the bell's "עדכונים" screen (gear).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:invoice/api/notifications_api.dart';
import 'package:invoice/api/push_preferences_api.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/business/notification_preferences_screen.dart';
import 'package:invoice/screens/business/system_notice_settings.dart';
import 'package:invoice/screens/home/notifications_screen.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/system_notices.dart';
import 'package:invoice/util/labels/notifications_he.dart';

import 'business/e_harness.dart';
import 'fakes/fake_api.dart';

const _catalogue = {
  'categories': [
    {
      'id': 'PAYMENTS',
      'label': 'תשלומים',
      'description': 'לקוח שילם',
      'canDisable': true,
    },
    {
      'id': 'CUSTOMERS',
      'label': 'לקוחות',
      'description': 'לקוח אישר הצעת מחיר',
      'canDisable': true,
    },
    {
      'id': 'SECURITY',
      'label': 'אבטחה',
      'description': 'כניסה מטלפון חדש',
      'canDisable': false,
    },
  ],
  'kinds': [],
};

bool _switchOn(WidgetTester tester, String id) => tester
    .widget<SwitchListTile>(find.byKey(Key('notification-pref-$id')))
    .value;

void main() {
  late FakeBackend backend;

  setUp(() async {
    backend = await eSetUp();
    backend
      ..json('GET', '/mobile/push/catalogue', _catalogue)
      ..json('GET', '/mobile/push/preferences', {
        'disabledCategories': ['CUSTOMERS'],
        'enabledKinds': ['QUOTE_VIEWED'],
        'quietHours': false,
      })
      ..on('PUT', '/mobile/push/preferences', (r) => FakeResponse(200, r.body));
  });

  test('preferences round-trip keeps kinds and quiet hours', () {
    final p = PushPreferences.fromJson({
      'disabledCategories': ['CUSTOMERS'],
      'enabledKinds': ['QUOTE_VIEWED'],
      'quietHours': false,
    });
    expect(p.withCategory('CUSTOMERS', true).toJson(), {
      'disabledCategories': <String>[],
      'enabledKinds': ['QUOTE_VIEWED'],
      'quietHours': false,
    });
    expect(p.withCategory('PAYMENTS', false).toJson()['disabledCategories'], [
      'CUSTOMERS',
      'PAYMENTS',
    ]);
  });

  testWidgets('shows each category with its saved state; security is locked', (
    tester,
  ) async {
    await pumpAs(
      tester,
      backend,
      Preset.employee,
      const NotificationPreferencesScreen(),
    );
    expect(find.text(NotificationPrefsHe.title), findsWidgets);
    expect(_switchOn(tester, 'PAYMENTS'), isTrue);
    expect(_switchOn(tester, 'CUSTOMERS'), isFalse);
    expect(_switchOn(tester, 'SECURITY'), isTrue);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('notification-pref-SECURITY')),
          )
          .onChanged,
      isNull,
    );
  });

  testWidgets('a toggle PUTs the whole record (kinds + quiet hours kept)', (
    tester,
  ) async {
    await pumpAs(
      tester,
      backend,
      Preset.owner,
      const NotificationPreferencesScreen(),
    );
    await tester.tap(find.byKey(const Key('notification-pref-PAYMENTS')));
    await settle(tester);
    expect(backend.last('PUT', '/mobile/push/preferences')!.body, {
      'disabledCategories': ['CUSTOMERS', 'PAYMENTS'],
      'enabledKinds': ['QUOTE_VIEWED'],
      'quietHours': false,
    });
    expect(_switchOn(tester, 'PAYMENTS'), isFalse);
    expect(
      backend
          .last('GET', '/mobile/push/preferences')!
          .headers
          .keys
          .map((k) => k.toLowerCase())
          .contains('x-business-id'),
      isFalse,
    );
  });

  testWidgets('a failed save puts the switch back', (tester) async {
    backend.error('PUT', '/mobile/push/preferences', 422, 'VALIDATION_FAILED');
    await pumpAs(
      tester,
      backend,
      Preset.owner,
      const NotificationPreferencesScreen(),
    );
    await tester.tap(find.byKey(const Key('notification-pref-CUSTOMERS')));
    await settle(tester);
    expect(_switchOn(tester, 'CUSTOMERS'), isFalse);
  });

  testWidgets('B → התראות has a "סוגי התראות" row that opens the screen', (
    tester,
  ) async {
    await pumpAs(tester, backend, Preset.owner, const SystemNoticeSettings());
    final row = find.byKey(const Key('system-notices-prefs'));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await settle(tester);
    expect(find.byType(NotificationPreferencesScreen), findsOneWidget);
  });

  testWidgets('the bell\'s "עדכונים" screen has a gear to the same screen', (
    tester,
  ) async {
    backend
      ..json('GET', '/mobile/notifications', {'items': [], 'nextBefore': null})
      ..json('GET', '/mobile/notifications/unread-count', {'unreadCount': 0});
    notificationsUnread.value = -1;
    await pumpAs(tester, backend, Preset.owner, const NotificationsScreen());
    await tester.tap(find.byKey(const Key('notifications-settings')));
    await settle(tester);
    expect(find.byType(NotificationPreferencesScreen), findsOneWidget);
  });

  test('/business/alerts is a B section every member can open', () {
    final r = AppRoute.parse('tevel://business/alerts')!;
    expect(r.pattern, '/business/:section');
    expect(sectionCap(BusinessSection.alerts), isNull);
    expect(r.requiredCap, isNull);
  });

  group('עדכונים ומבצעים מתבל (§30A, invoice#61)', () {
    bool marketingOn(WidgetTester tester) => tester
        .widget<SwitchListTile>(
          find.byKey(const Key('notification-pref-marketing')),
        )
        .value;

    testWidgets('hidden on a server without the consent endpoint (404)', (
      tester,
    ) async {
      await pumpAs(
        tester,
        backend,
        Preset.owner,
        const NotificationPreferencesScreen(),
      );
      await settle(tester);
      expect(
        find.byKey(const Key('notification-pref-SECURITY')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('notification-pref-marketing')),
        findsNothing,
      );
    });

    testWidgets('off by default with an explanation; switching on PUTs it', (
      tester,
    ) async {
      backend
        ..json('GET', '/mobile/push/marketing-consent', {
          'granted': false,
          'grantedAt': null,
          'revokedAt': null,
          'wordingVersion': 1,
        })
        ..on(
          'PUT',
          '/mobile/push/marketing-consent',
          (r) => FakeResponse(200, {'granted': (r.body as Map)['granted']}),
        );
      await pumpAs(
        tester,
        backend,
        Preset.owner,
        const NotificationPreferencesScreen(),
      );
      await settle(tester);
      final tile = find.byKey(const Key('notification-pref-marketing'));
      await tester.ensureVisible(tile);
      expect(marketingOn(tester), isFalse);
      expect(find.text(NotificationPrefsHe.marketing), findsOneWidget);
      expect(find.text(NotificationPrefsHe.marketingHint), findsOneWidget);
      await tester.tap(tile);
      await settle(tester);
      expect(backend.last('PUT', '/mobile/push/marketing-consent')!.body, {
        'granted': true,
      });
      expect(marketingOn(tester), isTrue);
    });

    testWidgets('shows the server wording; a failed save reverts', (
      tester,
    ) async {
      backend
        ..json('GET', '/mobile/push/marketing-consent', {
          'granted': true,
          'text': 'נוסח ההסכמה מהשרת',
        })
        ..error('PUT', '/mobile/push/marketing-consent', 500, 'INTERNAL');
      await pumpAs(
        tester,
        backend,
        Preset.owner,
        const NotificationPreferencesScreen(),
      );
      await settle(tester);
      final tile = find.byKey(const Key('notification-pref-marketing'));
      await tester.ensureVisible(tile);
      expect(find.text('נוסח ההסכמה מהשרת'), findsOneWidget);
      expect(marketingOn(tester), isTrue);
      await tester.tap(tile);
      await settle(tester);
      expect(marketingOn(tester), isTrue);
    });
  });

  group('push opens (invoice#61 POST /mobile/push/opened)', () {
    const id = '0f8fad5b-d9cb-469f-a165-70867728950e';

    Future<void> flush() =>
        Future<void>.delayed(const Duration(milliseconds: 20));

    test('a tap with pushId is reported once signed in', () async {
      backend.json('POST', '/mobile/push/opened', {
        'status': 'ok',
        'recorded': true,
      });
      await signInAs(backend, Preset.owner);
      systemNotices.debugEvent({'type': 'pushOpened', 'pushId': id});
      await flush();
      expect(backend.calls('POST', '/mobile/push/opened').map((r) => r.body), [
        {'pushId': id},
      ]);
    });

    test('cold start: a tap before sign-in is reported after it', () async {
      backend.json('POST', '/mobile/push/opened', {
        'status': 'ok',
        'recorded': true,
      });
      systemNotices.debugEvent({'type': 'pushOpened', 'pushId': id});
      await flush();
      expect(backend.calls('POST', '/mobile/push/opened'), isEmpty);
      await signInAs(backend, Preset.owner);
      systemNotices.debugFlushOpenedPushes(); // the session listener's job
      await flush();
      expect(backend.calls('POST', '/mobile/push/opened'), hasLength(1));
    });

    test('bad ids are never sent; 404/429 are ignored silently', () async {
      await signInAs(backend, Preset.owner);
      systemNotices.debugEvent({'type': 'pushOpened', 'pushId': 'x; drop'});
      systemNotices.debugEvent({'type': 'pushOpened', 'pushId': 42});
      await flush();
      expect(backend.calls('POST', '/mobile/push/opened'), isEmpty);
      backend.error('POST', '/mobile/push/opened', 404, 'NOT_FOUND');
      await reportPushOpened(id);
      backend.error('POST', '/mobile/push/opened', 429, 'RATE_LIMITED');
      await reportPushOpened(id);
      expect(backend.calls('POST', '/mobile/push/opened'), hasLength(2));
    });

    test('a network error is retried once', () async {
      await signInAs(backend, Preset.owner);
      var n = 0;
      backend.on('POST', '/mobile/push/opened', (_) {
        n++;
        throw http.ClientException('offline');
      });
      await reportPushOpened(id);
      expect(n, 2);
    });
  });
}
