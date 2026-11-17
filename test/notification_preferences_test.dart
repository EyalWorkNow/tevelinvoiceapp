// "סוגי התראות" (owner 2026-11-18): per-category on/off over the server's
// GET /mobile/push/catalogue + GET/PUT /mobile/push/preferences, reachable
// from B → התראות and from the bell's "עדכונים" screen (gear).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/notifications_api.dart';
import 'package:invoice/api/push_preferences_api.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/business/notification_preferences_screen.dart';
import 'package:invoice/screens/business/system_notice_settings.dart';
import 'package:invoice/screens/home/notifications_screen.dart';
import 'package:invoice/state/caps.dart';
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
}
