// "מסמך לחתימה" walkthrough (0116) on the simulator against a local API that
// has the sign-requests routes. The host passes a dev device token, the
// business, a DRAFT request (with a field) and a COMPLETED request, and takes a
// screenshot at every SHOT: marker (same protocol as quotes_journey_test):
//
//   ~/flutter/bin/flutter test integration_test/sign_requests_walkthrough_test.dart -d $U \
//     --dart-define=API_BASE=http://127.0.0.1:3216 --dart-define=DEVICE_TOKEN=inv_… \
//     --dart-define=BUSINESS_ID=… --dart-define=DRAFT_ID=… --dart-define=DONE_ID=… 2>&1 |
//   while IFS= read -r l; do echo "$l"; if [[ $l == *SHOT:* ]]; then
//     xcrun simctl io $U screenshot "$OUT/${l##*SHOT:}.png" >/dev/null 2>&1; fi; done
// ignore_for_file: avoid_print, use_build_context_synchronously
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/api/sign_requests_api.dart';
import 'package:invoice/main.dart' as app;
import 'package:invoice/router.dart';
import 'package:invoice/screens/sign/sign_editor_screen.dart';
import 'package:invoice/screens/sign/sign_send_screen.dart';

import 'crash_sweep_test.dart' show t, pumpMs, waitFor;
import 'v2_qa_gate_helpers.dart' show keychain, resetDevice;

const _token = String.fromEnvironment('DEVICE_TOKEN');
const _business = String.fromEnvironment('BUSINESS_ID');
const _draft = String.fromEnvironment('DRAFT_ID');
const _done = String.fromEnvironment('DONE_ID');

Future<void> _shot(String name) async {
  await pumpMs(2500);
  print('SHOT:esig-app-$name');
  await pumpMs(1200);
}

BuildContext get _ctx => navigatorKey.currentContext!;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sign requests walkthrough', (tester) async {
    t = tester;
    // Signed-out device + first-launch marker consumed, so the injected token is kept.
    await resetDevice();
    await keychain.write(key: 'device_token', value: _token);
    await keychain.write(key: 'business_id', value: _business);
    app.main();
    await waitFor(find.byKey(const Key('tab-home')), ms: 40000);
    await pumpMs(3000);

    unawaited(openActivity(_ctx));
    await pumpMs(3500);
    await _shot('1-documents-entry');

    unawaited(openSignRequests(_ctx));
    await pumpMs(3500);
    await _shot('2-list');

    final draft = await fetchSignRequest(_draft);
    unawaited(
      Navigator.of(_ctx).push(
        MaterialPageRoute<void>(builder: (_) => SignEditorScreen(request: draft)),
      ),
    );
    await pumpMs(5000);
    await _shot('3-editor');
    final kind = find.byKey(const Key('sign-kind-signature')).hitTestable();
    if (await waitFor(kind, ms: 4000)) {
      await tester.tap(kind.first, warnIfMissed: false);
      await pumpMs(600);
    }
    final page = find.byKey(const Key('sign-page-tap-0')).hitTestable();
    if (await waitFor(page, ms: 4000)) {
      await tester.tapAt(tester.getCenter(page.first) + const Offset(40, 120));
      await pumpMs(1200);
    }
    await _shot('4-editor-field-added');
    Navigator.of(_ctx).pop();
    await pumpMs(800);
    final leave = find.byKey(const Key('sign-leave')).hitTestable();
    if (leave.evaluate().isNotEmpty) {
      await tester.tap(leave.first, warnIfMissed: false);
      await pumpMs(800);
    }

    unawaited(
      Navigator.of(_ctx).push(
        MaterialPageRoute<void>(builder: (_) => SignSendScreen(request: draft)),
      ),
    );
    await pumpMs(3500);
    await _shot('5-send');
    Navigator.of(_ctx).pop();
    await pumpMs(800);

    unawaited(openSignRequest(_ctx, _done));
    await pumpMs(5000);
    await _shot('6-completed-detail');
    final list = find.byKey(const Key('sign-detail'));
    if (list.evaluate().isNotEmpty) {
      await tester.drag(list.first, const Offset(0, -600));
      await pumpMs(1200);
      await _shot('7-completed-trail');
    }
  });
}
