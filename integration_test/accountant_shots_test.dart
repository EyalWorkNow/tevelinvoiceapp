// Accountant multi-business shots (2026-11-22) with MOCKED data (the test
// FakeBackend, no server). Prints SHOT: markers (same protocol as
// keyboard_shots_test):
//
//   U=<sim udid>; OUT=$PWD/docs/qa/accountant-2026-11-22
//   ~/flutter/bin/flutter test integration_test/accountant_shots_test.dart -d $U 2>&1 |
//   while IFS= read -r l; do echo "$l"; if [[ $l == *SHOT:* ]]; then
//     n=${l##*SHOT:}; xcrun simctl io $U screenshot "$OUT/$n.png" >/dev/null 2>&1; fi; done
// ignore_for_file: avoid_print
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/app_shell.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/auth/access_request_screen.dart';
import 'package:invoice/screens/business/business_screen.dart';
import 'package:invoice/screens/business/notification_preferences_screen.dart';
import 'package:invoice/screens/business/sheets/s14_switch.dart';
import 'package:invoice/state/accountant_store.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/session.dart';

import '../test/accountant/accountant_test.dart'
    show client, clientsJson, request, servePeriodReview, accessToken;
import '../test/business/e_harness.dart';
import '../test/fakes/fake_api.dart';

late WidgetTester t;

Future<void> pumpMs(int ms) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  do {
    await t.pump(const Duration(milliseconds: 50));
  } while (DateTime.now().isBefore(end));
}

Future<void> shot(String name) async {
  await pumpMs(1500);
  print('SHOT:$name');
  await pumpMs(1500);
}

Future<void> tap(Finder f) async {
  await t.ensureVisible(f);
  await pumpMs(300);
  await t.tap(f);
  await pumpMs(1200);
}

FakeBackend backendFor() {
  final b = FakeBackend()..install();
  installBusinessFakes(b);
  b
    ..json(
      'GET',
      '/mobile/accountant/clients',
      clientsJson(
        clients: [
          client('b1', readiness: 96, reviewed: '2026-09'),
          client(
            'b2',
            readiness: 58,
            payments: 2,
            taxInvoices: 1,
            phone: '0501234567',
          ),
          client('b3', readiness: 74, expenses: 4, phone: '0527654321'),
        ],
        requests: [request('r1', 'PENDING'), request('r2', 'DECLINED')],
      ),
    )
    ..json('POST', '/mobile/accountant/access-requests', {
      'id': 'r9',
      'link': 'https://app.tevel.space/m/access/$accessToken',
      'whatsappText': 'משרד כהן מבקש גישה לעסק שלך בתבל',
      'emailed': true,
    }, status: 201)
    ..json('GET', '/mobile/access-requests/:token', {
      'id': 'r1',
      'accountant': {
        'name': 'יוסי כהן',
        'email': 'yossi@cohen.test',
        'officeName': 'משרד כהן ושות׳',
      },
      'role': 'ACCOUNTANT_REP',
      'expiresAt': '2026-11-29T00:00:00Z',
      'businesses': [
        {'businessId': 'b1', 'legalName': 'סטודיו תבל'},
        {'businessId': 'b2', 'legalName': 'נגריית הגליל'},
      ],
    })
    ..json('GET', '/mobile/push/catalogue', {
      'categories': [
        {'id': 'MONEY', 'label': 'תשלומים', 'description': 'תשלום שהתקבל'},
      ],
    })
    ..json('GET', '/mobile/push/preferences', {
      'disabledCategories': <String>[],
      'enabledKinds': <String>[],
      'quietHours': true,
      'disabledKinds': <String>[],
    });
  servePeriodReview(b, const []);
  return b;
}

Future<void> signIn(FakeBackend b, Preset p, Widget home) async {
  accountantStore.reset();
  await signInAs(b, p, businesses: 3);
  await t.pumpWidget(eApp(home));
  await pumpMs(2500);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('accountant shots', (tester) async {
    t = tester;
    var b = await eSetUp();
    b = backendFor();

    // 1 · home row + R with "סימון כנבדק".
    await signIn(b, Preset.accountantRep, const AppShell());
    await shot('01-home-row');
    await t.scrollUntilVisible(
      find.byKey(const Key('period-review')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await shot('02-period-review');
    await tap(find.byKey(const Key('period-review')));
    await shot('03-period-reviewed');

    // 3 · the clients list: badges, ✓, reminder, pending requests.
    unawaited(showSwitchBusinessSheet(navigatorKey.currentContext!));
    await pumpMs(1500);
    await shot('04-clients-list');

    // 2 · add a client.
    await tap(find.byKey(const Key('s14-add-client')));
    await shot('05-add-client');
    await t.enterText(
      find.byKey(const Key('add-client-contact')),
      'owner@galil.co.il',
    );
    await pumpMs(300);
    FocusManager.instance.primaryFocus?.unfocus();
    await pumpMs(600);
    await tap(find.byKey(const Key('add-client-send')));
    await shot('06-add-client-sent');
    navigatorKey.currentState!.popUntil((r) => r.isFirst);
    await pumpMs(800);

    // 7 · leave.
    await t.pumpWidget(eApp(const BusinessScreen()));
    await pumpMs(1500);
    await t.scrollUntilVisible(
      find.byKey(const Key('brow-leave')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await shot('07-business-leave-row');
    await tap(find.byKey(const Key('brow-leave')));
    await shot('08-leave-confirm');
    navigatorKey.currentState!.popUntil((r) => r.isFirst);
    await pumpMs(500);

    // 4 · accountant mute toggles.
    await t.pumpWidget(eApp(const NotificationPreferencesScreen()));
    await pumpMs(1500);
    await t.scrollUntilVisible(
      find.byKey(const Key('notification-kind-ACCOUNTANT_EXPENSES_DIGEST')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await shot('09-notification-prefs');

    // 2 · the owner's approval screen.
    b = backendFor();
    await signIn(
      b,
      Preset.owner,
      const AccessRequestScreen(token: accessToken),
    );
    await shot('10-owner-approve');

    // 5 · an accountant without businesses.
    b = backendFor();
    b
      ..json('GET', '/mobile/session', accountJson(count: 0))
      ..json(
        'GET',
        '/mobile/accountant/clients',
        clientsJson(office: 'משרד לוי', clients: const []),
      );
    accountantStore.reset();
    session
      ..business = null
      ..me = null
      ..profile = null;
    await session.refreshAccount();
    await t.pumpWidget(eApp(const SizedBox()));
    resetToAccountantClients();
    await pumpMs(2000);
    await shot('11-accountant-empty');
  });
}
