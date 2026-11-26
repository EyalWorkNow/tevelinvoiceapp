// 2611 V3 (spec §9) — the iOS-style calendar, screenshots with MOCKED data
// (the test FakeBackend, no server). Prints SHOT: markers:
//
//   U=<sim udid>; OUT=$PWD/docs/qa/2611-v3
//   ~/flutter/bin/flutter test integration_test/calendar_v3_shots_test.dart -d $U 2>&1 |
//   while IFS= read -r l; do echo "$l"; if [[ $l == *SHOT:* ]]; then
//     n=${l##*SHOT:}; xcrun simctl io $U screenshot "$OUT/$n.png" >/dev/null 2>&1; fi; done
// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/business/e_harness.dart';
import '../test/calendar/calendar_shots_scenario.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('calendar v3 shots', (tester) async {
    await eSetUp();
    Future<void> pumpMs(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      do {
        await tester.pump(const Duration(milliseconds: 50));
      } while (DateTime.now().isBefore(end));
    }

    await runCalendarShots(
      tester,
      waitMs: pumpMs,
      shot: (name) async {
        await pumpMs(1000);
        print('SHOT:$name');
        await pumpMs(1200);
      },
    );
  });
}
