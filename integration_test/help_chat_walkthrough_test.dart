// "עזרה" walkthrough (0120) on the simulator against a local API whose
// DEEPSEEK_BASE_URL points at a local stub (never the real provider). The host
// passes a dev device token + business and screenshots every SHOT: marker:
//
//   ~/flutter/bin/flutter test integration_test/help_chat_walkthrough_test.dart -d $U \
//     --dart-define=API_BASE=http://127.0.0.1:3217 --dart-define=DEVICE_TOKEN=inv_… \
//     --dart-define=BUSINESS_ID=… 2>&1 |
//   while IFS= read -r l; do echo "$l"; if [[ $l == *SHOT:* ]]; then
//     xcrun simctl io $U screenshot "$OUT/${l##*SHOT:}.png" >/dev/null 2>&1; fi; done
// ignore_for_file: avoid_print, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/app_shell.dart';
import 'package:invoice/main.dart' as app;
import 'package:invoice/router.dart';

import 'crash_sweep_test.dart' show t, pumpMs, waitFor;
import 'v2_qa_gate_helpers.dart' show keychain, resetDevice;

const _token = String.fromEnvironment('DEVICE_TOKEN');
const _business = String.fromEnvironment('BUSINESS_ID');

Future<void> _shot(String name) async {
  await pumpMs(2000);
  print('SHOT:help-$name');
  await pumpMs(1200);
}

Future<void> _tap(Finder f) async {
  if (await waitFor(f.hitTestable(), ms: 8000)) {
    await t.tap(f.hitTestable().first, warnIfMissed: false);
    await pumpMs(900);
  }
}

Future<void> _ask(String q) async {
  await t.enterText(find.byKey(const Key('help-input')), q);
  await pumpMs(400);
  await _tap(find.byKey(const Key('help-send')));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('help chat walkthrough', (tester) async {
    t = tester;
    await resetDevice();
    await keychain.write(key: 'device_token', value: _token);
    await keychain.write(key: 'business_id', value: _business);
    app.main();
    await waitFor(find.byKey(const Key('tab-home')), ms: 40000);
    await pumpMs(3000);

    // פרופיל → (הגדרות) → "עזרה — שאלו את העוזר".
    selectTab(AppTab.profile);
    await pumpMs(2500);
    final settings = find.text('הגדרות');
    if (settings.hitTestable().evaluate().isNotEmpty) await _tap(settings);
    final row = find.byKey(const Key('account-help'));
    for (var i = 0; i < 12 && row.hitTestable().evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -250));
      await pumpMs(500);
    }
    await _shot('1-settings-row');
    await _tap(row);
    await pumpMs(1500);
    await _shot('2-chat-empty');

    await _ask('איך שולחים בקשת תשלום?');
    await pumpMs(300);
    await _shot('3-typing');
    await waitFor(
      find.byKey(const Key('help-chip-payment-request')),
      ms: 15000,
    );
    await _shot('4-answer-chip');

    await _tap(find.byKey(const Key('help-chip-payment-request')));
    await pumpMs(2500);
    await _shot('5-chip-opened');
    Navigator.of(navigatorKey.currentContext!).pop();
    await pumpMs(1500);

    await _ask('איך מחברים את החשבון לבנק דיסקונט?');
    await waitFor(find.byKey(const Key('help-cannot-escalate')), ms: 15000);
    await _shot('6-cannot-help');

    await _tap(
      find.descendant(
        of: find.byKey(const Key('help-cannot-escalate')),
        matching: find.byType(OutlinedButton),
      ),
    );
    await pumpMs(1000);
    await _shot('7-escalate-sheet');
    await _tap(find.byKey(const Key('help-escalate-send')));
    await pumpMs(3000);
    await _shot('8-escalated');
  });
}
