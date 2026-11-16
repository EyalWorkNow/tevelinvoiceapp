// Owner port (2026-11-16) · three screenshots of the bottom navigation so the
// owner can confirm it is exactly theirs: owner Home (＋ beside the capsule),
// owner on another tab (＋ gone, capsule unchanged), and the employee.
// Same SHOT: protocol as persona_screens_test.dart.
//
//   U=<simulator udid>; OUT=$PWD/docs/qa-2026-11-16/owner-port (absolute)
//   ~/flutter/bin/flutter test integration_test/owner_navbar_screens_test.dart -d $U \
//     --dart-define=API_BASE=http://127.0.0.1:3041 \
//     --dart-define=MAILDIR=$HOME/invoiceproject-staging-qa/outgoing-emails 2>&1 |
//   while IFS= read -r l; do echo "$l"; if [[ $l == *SHOT:* ]]; then
//     n=${l##*SHOT:}; mkdir -p "$OUT/$(dirname $n)";
//     xcrun simctl io $U screenshot "$OUT/$n.png" >/dev/null 2>&1; fi; done
//
// Read-only: nothing is written on staging.
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/app_shell.dart';
import 'package:invoice/state/session.dart';

import 'crash_sweep_test.dart' show t, pumpMs, waitFor, selectTab;
import 'persona_screens_test.dart'
    show role, shot, runCaptured, startPlansGuard, plansGuardOn, owner, guarded;
import 'v2_qa_gate_helpers.dart' show launchSignedInAs;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  startPlansGuard();

  testWidgets('owner navbar screens', (tester) async {
    await runCaptured(tester, () async {
      role = 'navbar';
      plansGuardOn = true;
      await launchSignedInAs(t, owner);
      await waitFor(find.byKey(const Key('tab-home')), ms: 40000);
      await pumpMs(3000);
      await guarded('owner home', () async => shot('owner-home'));
      await guarded('owner business tab', () async {
        await selectTab(AppTab.business);
        await pumpMs(1500);
        await shot('owner-business-tab');
        await selectTab(AppTab.home);
      });
      await session.signOut();
      await pumpMs(1500);

      await launchSignedInAs(t, 'mobile-employee@tevel.test');
      await waitFor(find.byKey(const Key('tab-home')), ms: 40000);
      await pumpMs(3000);
      await guarded('employee home', () async => shot('employee-home'));
      await session.signOut();
      await pumpMs(1500);
    });
  }, timeout: const Timeout(Duration(minutes: 15)));
}
