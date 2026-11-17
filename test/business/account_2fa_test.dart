// FIXB wiring audit: "אימות דו-שלבי" shows the member's real second factors
// (GET /auth/mfa/methods), not a fixed "קוד במייל".

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:invoice/api/auth_api.dart' show MfaMethods, fetchMfaMethods;
import 'package:invoice/screens/business/account_page.dart';
import 'package:invoice/state/caps.dart';

import '../fakes/fake_api.dart';
import 'e_harness.dart';

void main() {
  late FakeBackend backend;
  setUp(() async => backend = await eSetUp());

  for (final (methods, label) in [
    (
      const MfaMethods(
        totp: true,
        email: true,
        emailAvailable: true,
        recoveryCodesRemaining: 8,
      ),
      'אפליקציה + קוד במייל',
    ),
    (
      const MfaMethods(
        totp: false,
        email: false,
        emailAvailable: true,
        recoveryCodesRemaining: 0,
      ),
      'לא מוגדר',
    ),
  ]) {
    testWidgets('2FA row: $label', (tester) async {
      loadMfaMethods = () async => methods;
      addTearDown(() => loadMfaMethods = fetchMfaMethods);
      await pumpAs(tester, backend, Preset.owner, const AccountPage());
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const Key('account-2fa')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(label), findsOneWidget);
      if (methods.totp) {
        expect(find.text('מחוברת · 8 קודי שחזור'), findsOneWidget);
      }
    });
  }
}
