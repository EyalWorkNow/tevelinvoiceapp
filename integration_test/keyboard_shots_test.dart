// Keyboard / amount keypad QA (2026-11-19): the quote composer with the
// keypad open, then with the system keyboard on a field below the amount.
// Prints SHOT: markers (same protocol as quotes_journey_test).
//
//   U=<sim udid>; OUT=$PWD/docs/qa/keyboard-2026-11-19/<before|after>
//   ~/flutter/bin/flutter test integration_test/keyboard_shots_test.dart -d $U \
//     --dart-define=MAILDIR=$HOME/invoiceproject-mobile-dev-storage/outgoing-emails 2>&1 |
//   while IFS= read -r l; do echo "$l"; if [[ $l == *SHOT:* ]]; then
//     n=${l##*SHOT:}; mkdir -p "$OUT/$(dirname $n)";
//     xcrun simctl io $U screenshot "$OUT/$n.png" >/dev/null 2>&1; fi; done
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/router.dart' hide selectTab;

import 'crash_sweep_test.dart' show t, pumpMs, waitFor;
import 'persona_screens_test.dart'
    show
        role,
        shot,
        runCaptured,
        startPlansGuard,
        plansGuardOn,
        owner,
        guarded,
        hardRoot,
        typeKeypad,
        ctx;
import 'v2_qa_gate_helpers.dart' show launchSignedInAs;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  startPlansGuard();

  testWidgets('keyboard shots', (tester) async {
    await runCaptured(tester, () async {
      role = 'keyboard';
      plansGuardOn = true;
      // No native push-permission alert over the shots (fresh install).
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('tevel/system_notices'),
        (call) async => switch (call.method) {
          'status' => {
            'notifications': false,
            'determined': true,
            'authorization': 'denied',
            'liveActivities': false,
          },
          'enable' => false,
          _ => null,
        },
      );
      await launchSignedInAs(t, owner);
      await waitFor(find.byKey(const Key('tab-home')), ms: 40000);
      await pumpMs(3000);
      final c = await ApiClient.instance.post('/customers', {
        'name': 'בדיקת מקלדת ${Random().nextInt(900000) + 100000}',
        'customerType': 'INDIVIDUAL',
      });
      final cust = ((c['customer'] as Map?)?['id'] ?? c['id']) as String;

      await guarded('quote keypad', () async {
        unawaited(openCompose(ctx, intent: 'QUOTE', customerId: cust));
        await pumpMs(3500);
        await shot('quote-empty');
        await typeKeypad('1500');
        await shot('quote-keypad-amount');
        await hardRoot();
      });

      await guarded('invoice keypad', () async {
        unawaited(openCompose(ctx, intent: 'PAID', customerId: cust));
        await pumpMs(3500);
        await typeKeypad('250');
        await shot('invoice-keypad-amount');
        await hardRoot();
      });

      await guarded('payment request number pad', () async {
        unawaited(openPaymentRequest(ctx, customerId: cust));
        await pumpMs(3500);
        final amount = find.byKey(const Key('payment-request-amount'));
        if (await waitFor(amount, ms: 6000)) {
          await t.tap(amount, warnIfMissed: false);
          await pumpMs(1500);
        }
        await shot('payment-request-number-pad');
        await hardRoot();
      });
    });
  });
}
