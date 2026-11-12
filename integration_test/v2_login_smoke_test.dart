// V2 simulator smoke (INT): real app against the LOCAL dev API (never prod).
// One preset per run; the e-mail MFA code is read from the dev mail folder
// (simulator apps can read the host file system).
//
//   ~/flutter/bin/flutter test integration_test/v2_login_smoke_test.dart -d <udid> \
//     --dart-define=API_BASE=http://127.0.0.1:3031 \
//     --dart-define=EMAIL=mobile-owner@tevel.test \
//     --dart-define=MAILDIR=$HOME/invoiceproject-mobile-dev-storage/outgoing-emails
//
// Prints `SHOT:<name>` and holds the frame for a few seconds so
// ops/sim-screens-v2.sh can take `simctl io screenshot`.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/api/inbox_api.dart' show mobileInboxAvailable;
import 'package:invoice/state/business_context.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/app_shell.dart';
import 'package:invoice/main.dart' as app;
import 'package:invoice/screens/auth/mfa_sheet.dart';
import 'package:invoice/screens/business/business_screen.dart';
import 'package:invoice/screens/business/sheets/s14_switch.dart';
import 'package:invoice/screens/home/home_screen.dart';
import 'package:invoice/screens/reports/reports_screen.dart';
import 'package:invoice/state/session.dart';
import 'qa_plans_guard.dart';

const email = String.fromEnvironment(
  'EMAIL',
  defaultValue: 'mobile-staff@tevel.test',
);
const mailDir = String.fromEnvironment('MAILDIR');
const password = 'Mobile12345678';
final shotName = email.split('@').first.replaceFirst('mobile-', '');

Future<void> pumpFor(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> shot(WidgetTester tester, String name) async {
  await pumpFor(tester, const Duration(seconds: 2));
  debugPrint('SHOT:$name');
  await pumpFor(tester, const Duration(seconds: 5));
}

/// Newest 6-digit login code e-mailed to [to] after [since].
String? latestCode(String to, DateTime since) {
  final dir = Directory(mailDir);
  if (mailDir.isEmpty || !dir.existsSync()) return null;
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
        );
  for (final f in files) {
    if (f.statSync().modified.isBefore(since)) break;
    final m = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final subject = '${m['subject']}';
    if (m['to'] == to && RegExp(r'^\d{6}').hasMatch(subject))
      return subject.substring(0, 6);
  }
  return null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  dismissPlansDuringTests();

  testWidgets('V2 sign-in → home ($email)', (tester) async {
    // Start signed out (a stale Keychain token would open the app lock).
    const storage = FlutterSecureStorage();
    final stale = await storage.read(key: 'device_token');
    if (stale != null) {
      ApiClient.instance.deviceToken = stale;
      try {
        await ApiClient.instance.post('/mobile/logout');
      } on ApiException {
        // already revoked
      }
      ApiClient.instance.clearCredentials();
    }
    await storage.deleteAll();

    app.main();
    final loginButton = find.text('כניסה');
    for (var i = 0; i < 150 && loginButton.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(loginButton, findsOneWidget);
    await shot(tester, 'login');

    await tester.enterText(find.byType(TextField).at(0), email);
    await tester.enterText(find.byType(TextField).at(1), password);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 500));
    final since = DateTime.now().subtract(const Duration(seconds: 2));
    await tester.ensureVisible(loginButton);
    await tester.tap(loginButton);

    var mfaDone = false;
    for (var i = 0; i < 300 && find.byType(AppShell).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (!mfaDone && find.byType(MfaSheet).evaluate().isNotEmpty) {
        String? code;
        for (var j = 0; j < 50 && code == null; j++) {
          await pumpFor(tester, const Duration(milliseconds: 300));
          code = latestCode(email, since);
        }
        expect(code, isNotNull, reason: 'no MFA e-mail for $email in $mailDir');
        await shot(tester, 'mfa');
        final field = find.descendant(
          of: find.byType(CodeBoxes),
          matching: find.byType(TextField),
        );
        await tester.enterText(field, code!);
        mfaDone = true;
      }
      if (find.byType(SwitchBusinessSheet).evaluate().isNotEmpty) {
        await shot(tester, 's14');
        final rows = find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('s14-3b773037'),
        );
        if (rows.evaluate().isNotEmpty)
          await tester.tap(rows.first, warnIfMissed: false);
      }
    }
    expect(find.byType(AppShell), findsOneWidget);
    // Accountant presets: the home tab is R (§4.4), not H.
    final homeIsReports = businessContext.caps.homeIsReports;
    expect(
      find.byType(homeIsReports ? ReportsScreen : HomeScreen),
      findsOneWidget,
    );
    await pumpFor(
      tester,
      const Duration(seconds: 4),
    ); // home data (cache → network)
    debugPrint('ME role=${session.me?.role} perms=${session.me?.permissions}');
    debugPrint(
      'DIAG business=${session.business?.businessId} be05=$mobileInboxAvailable '
      'preset=${businessContext.caps.preset} money=${find.byKey(const Key('home-money')).evaluate().length}',
    );
    // BE-05 answered (not the P0 fallback, not an error) and money follows caps.
    if (!homeIsReports) {
      expect(mobileInboxAvailable, isTrue);
      expect(
        find.byKey(const Key('home-money')).evaluate().length,
        businessContext.caps.can(Cap.moneyView) ? 1 : 0,
      );
    }
    await shot(tester, 'home');

    await tester.tap(find.byKey(const Key('tab-business')));
    await pumpFor(tester, const Duration(seconds: 3));
    expect(find.byType(BusinessScreen), findsOneWidget);
    await shot(tester, 'business');

    await session.signOut(); // revokes the dev device token
  });
}
