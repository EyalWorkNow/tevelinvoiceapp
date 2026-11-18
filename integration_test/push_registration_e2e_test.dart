// Push registration end to end on the simulator against a LOCAL dev API
// (never prod): a signed-in owner → iOS asks once → APNs token → rows in
// mobile_push_tokens (per business) and push_devices (per user).
//
//   ~/flutter/bin/flutter test integration_test/push_registration_e2e_test.dart -d <udid> \
//     --dart-define=API_BASE=http://127.0.0.1:<port> \
//     --dart-define=PUSH_TOKEN=<device bearer minted on the dev API> \
//     --dart-define=PUSH_BUSINESS=<business id>
//
// Allow the notification prompt on the simulator when it appears (or grant it
// beforehand). The test prints the registration state every 2 s.
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/main.dart' as app;
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/session.dart';
import 'package:invoice/state/system_notices.dart';

const _token = String.fromEnvironment('PUSH_TOKEN');
const _business = String.fromEnvironment('PUSH_BUSINESS');

const _keychain = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a signed-in owner registers for push', (tester) async {
    expect(_token, isNotEmpty, reason: '--dart-define=PUSH_TOKEN');
    await tester.runAsync(() async {
      await AppCache.isFirstLaunch();
      await AppCache.clearAll();
      await _keychain.write(key: 'biometric_enabled', value: '0');
      await _keychain.write(key: 'device_token', value: _token);
      await _keychain.write(key: 'business_id', value: _business);
    });
    app.main();
    final end = DateTime.now().add(const Duration(seconds: 90));
    var registered = false;
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1800)),
      );
      final d = systemNotices.diagnostics;
      final native = await tester.runAsync(
        () => const MethodChannel(
          'tevel/system_notices',
        ).invokeMapMethod<String, Object?>('status'),
      );
      print('PUSH native=$native enabled=${systemNotices.enabled}');
      print(
        'PUSH session=${session.status.name} '
        'business=${session.business?.businessId} $d',
      );
      if (d.businessRegistered && d.catalogueRegistered) {
        registered = true;
        break;
      }
    }
    expect(registered, isTrue, reason: '${systemNotices.diagnostics}');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
