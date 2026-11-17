// Invoice design gallery on a simulator against a LOCAL staging API (never
// prod): signs in, opens "עיצוב המסמכים", waits for every thumbnail, then
// selects each design. Prints `SHOT:<name>` and holds the frame so the caller
// can `xcrun simctl io <udid> screenshot`.
//
//   ~/flutter/bin/flutter test integration_test/template_gallery_shots_test.dart -d <udid> \
//     --dart-define=API_BASE=http://127.0.0.1:3044 \
//     --dart-define=EMAIL=mobile-owner@tevel.test \
//     --dart-define=MAILDIR=$HOME/invoiceproject-staging-tpl/outgoing-emails
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/app_shell.dart';
import 'package:invoice/main.dart' as app;
import 'package:invoice/router.dart';
import 'package:invoice/screens/auth/mfa_sheet.dart';
import 'package:invoice/screens/business/branding_screen.dart';
import 'package:invoice/screens/business/sheets/s14_switch.dart';
import 'package:invoice/screens/business/template_gallery.dart';
import 'package:invoice/state/session.dart';
import 'qa_plans_guard.dart';
import 'v2_login_smoke_test.dart' show latestCode, pumpFor, shot;

const email = String.fromEnvironment(
  'EMAIL',
  defaultValue: 'mobile-owner@tevel.test',
);
const password = 'Mobile12345678';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  dismissPlansDuringTests();

  testWidgets('invoice design gallery ($email)', (tester) async {
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
        await tester.enterText(
          find.descendant(
            of: find.byType(CodeBoxes),
            matching: find.byType(TextField),
          ),
          code!,
        );
        mfaDone = true;
      }
      final rows = find.descendant(
        of: find.byType(SwitchBusinessSheet),
        matching: find.byType(InkWell),
      );
      if (rows.evaluate().isNotEmpty) {
        await tester.tap(rows.first, warnIfMissed: false);
      }
    }
    expect(find.byType(AppShell), findsOneWidget);
    await pumpFor(tester, const Duration(seconds: 2));

    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const BrandingScreen()),
    );
    // Wait for every thumbnail (sequential server renders).
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      final done = invoiceTemplates.keys.every(
        (id) => find
            .byKey(Key('branding-template-thumb-$id'), skipOffstage: false)
            .evaluate()
            .isNotEmpty,
      );
      if (done) break;
    }
    await shot(tester, 'gallery');
    final gallery = find.descendant(
      of: find.byKey(const Key('branding-template-gallery')),
      matching: find.byType(Scrollable),
    );
    for (final id in invoiceTemplates.keys) {
      final card = find.byKey(Key('branding-template-$id'));
      await tester.scrollUntilVisible(card, 120, scrollable: gallery);
      await tester.tap(card);
      await pumpFor(tester, const Duration(seconds: 3)); // big preview
      await shot(tester, 'select-$id');
    }
    await session.signOut();
  });
}
