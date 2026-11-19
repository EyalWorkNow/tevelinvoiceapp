import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/screens/business/delete_account_screen.dart';
import 'package:invoice/state/caps.dart';

import '../fakes/fake_api.dart';
import 'e_harness.dart';

void main() {
  late FakeBackend backend;
  setUp(() async {
    backend = await eSetUp();
    backend.json('POST', '/mobile/account/delete', {'status': 'deleted'});
  });

  Future<void> show(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder);
      await settle(tester);
      return;
    }
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
  }

  Future<void> confirm(WidgetTester tester, String password) async {
    await show(tester, find.byKey(const Key('delete-password')));
    await tester.enterText(find.byKey(const Key('delete-password')), password);
    await show(tester, find.byKey(const Key('delete-confirm')));
    await tester.enterText(
      find.byKey(const Key('delete-confirm')),
      deleteConfirmWord,
    );
    await settle(tester);
    await show(tester, find.text('מחיקת החשבון לצמיתות'));
    await tester.tap(find.text('מחיקת החשבון לצמיתות'));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'old Apple sign-in marker cannot hide password or require Apple',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({'apple_sign_in_used': '1'});
      await pumpAs(tester, backend, Preset.owner, const DeleteAccountScreen());
      await show(tester, find.byKey(const Key('delete-password')));
      expect(find.byKey(const Key('delete-password')), findsOneWidget);
      expect(find.textContaining('Apple'), findsNothing);
      await confirm(tester, 'CurrentPassword123!');
      expect(backend.last('POST', '/mobile/account/delete')!.body, {
        'confirm': 'DELETE',
        'password': 'CurrentPassword123!',
      });
    },
  );

  testWidgets(
    'deletion requires both a password and the exact confirmation word',
    (tester) async {
      await pumpAs(tester, backend, Preset.owner, const DeleteAccountScreen());
      await show(tester, find.byKey(const Key('delete-confirm')));
      await tester.enterText(
        find.byKey(const Key('delete-confirm')),
        deleteConfirmWord,
      );
      await show(tester, find.text('מחיקת החשבון לצמיתות'));
      await tester.tap(find.text('מחיקת החשבון לצמיתות'));
      await tester.pump();
      expect(backend.calls('POST', '/mobile/account/delete'), isEmpty);
      await show(tester, find.byKey(const Key('delete-password')));
      await tester.enterText(
        find.byKey(const Key('delete-password')),
        'CurrentPassword123!',
      );
      await show(tester, find.byKey(const Key('delete-confirm')));
      await tester.enterText(
        find.byKey(const Key('delete-confirm')),
        'לא למחוק',
      );
      await show(tester, find.text('מחיקת החשבון לצמיתות'));
      await tester.tap(find.text('מחיקת החשבון לצמיתות'));
      await tester.pump();
      expect(backend.calls('POST', '/mobile/account/delete'), isEmpty);
    },
  );

  testWidgets('wrong password can be corrected and retried without Apple', (
    tester,
  ) async {
    backend.error('POST', '/mobile/account/delete', 403, 'REAUTH_FAILED');
    await pumpAs(tester, backend, Preset.owner, const DeleteAccountScreen());
    await confirm(tester, 'wrong');
    await settle(tester);
    expect(find.textContaining('לא הצלחנו לאמת את הזהות'), findsOneWidget);
    backend.json('POST', '/mobile/account/delete', {'status': 'deleted'});
    await confirm(tester, 'CurrentPassword123!');
    expect(backend.calls('POST', '/mobile/account/delete'), hasLength(2));
    expect(
      backend.last('POST', '/mobile/account/delete')!.body['password'],
      'CurrentPassword123!',
    );
  });

  testWidgets('password visibility can be toggled explicitly', (tester) async {
    await pumpAs(tester, backend, Preset.owner, const DeleteAccountScreen());
    await show(tester, find.byKey(const Key('delete-password')));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('delete-password')))
          .obscureText,
      isTrue,
    );
    await tester.tap(find.byTooltip('הצגת הסיסמה'));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('delete-password')))
          .obscureText,
      isFalse,
    );
  });
}
