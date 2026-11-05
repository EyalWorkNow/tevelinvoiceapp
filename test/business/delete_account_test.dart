// Account deletion revokes the Apple grant (App Store 5.1.1(v)): the Apple
// step's one-time authorizationCode goes to POST /mobile/account/delete.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/screens/business/delete_account_screen.dart';
import 'package:invoice/state/caps.dart';

import '../fakes/fake_api.dart';
import 'e_harness.dart';

const _appleChannel = MethodChannel('com.aboutyou.dart_packages.sign_in_with_apple');

void main() {
  late FakeBackend backend;
  setUp(() async {
    backend = await eSetUp();
    backend.json('POST', '/mobile/account/delete', {'status': 'deleted'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _appleChannel,
      (call) async => {
        'type': 'appleid',
        'authorizationCode': 'c0de-apple',
        'identityToken': 'eyJapple',
        'userIdentifier': 'apple-sub',
      },
    );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _appleChannel,
      null,
    ),
  );

  Future<void> show(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
    await settle(tester);
  }

  Future<void> deleteWithApple(WidgetTester tester) async {
    await show(tester, find.text('אימות עם Apple'));
    await tester.tap(find.text('אימות עם Apple'));
    await settle(tester);
    expect(find.text('אומת עם Apple'), findsOneWidget);
    await show(tester, find.byType(TextField).last);
    await tester.enterText(find.byType(TextField).last, deleteConfirmWord);
    await settle(tester);
    await show(tester, find.text('מחיקת החשבון לצמיתות'));
    await tester.tap(find.text('מחיקת החשבון לצמיתות'));
    // The screen then wipes the session (spinner): pump, do not settle.
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('Apple step → body carries the identity token AND the authorization code', (tester) async {
    await pumpAs(tester, backend, Preset.owner, const DeleteAccountScreen());
    await deleteWithApple(tester);
    expect(backend.last('POST', '/mobile/account/delete')!.body, {
      'confirm': 'DELETE',
      'appleIdentityToken': 'eyJapple',
      'appleAuthorizationCode': 'c0de-apple',
    });
  });

  testWidgets('device signed in with Apple: password is not enough, Apple step required', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'apple_sign_in_used': '1'});
    await pumpAs(tester, backend, Preset.owner, const DeleteAccountScreen());
    await show(tester, find.textContaining('החיבור ל-Apple יבוטל'));
    expect(find.byType(TextField), findsOneWidget); // only the "מחק" field
    await deleteWithApple(tester);
    expect(backend.last('POST', '/mobile/account/delete')!.body['appleAuthorizationCode'], 'c0de-apple');
  });

  testWidgets('password user: no Apple code is sent', (tester) async {
    await pumpAs(tester, backend, Preset.owner, const DeleteAccountScreen());
    await show(tester, find.text('אימות עם Apple')); // the password field sits right above
    await tester.enterText(find.byType(TextField).first, 'Mobile12345678');
    await show(tester, find.byType(TextField).last);
    await tester.enterText(find.byType(TextField).last, deleteConfirmWord);
    await settle(tester);
    await show(tester, find.text('מחיקת החשבון לצמיתות'));
    await tester.tap(find.text('מחיקת החשבון לצמיתות'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(backend.last('POST', '/mobile/account/delete')!.body, {'confirm': 'DELETE', 'password': 'Mobile12345678'});
  });
}
