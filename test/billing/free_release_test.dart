import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/environment.dart';
import 'package:invoice/screens/billing/billing_screen.dart';
import 'package:invoice/screens/profile/profile_settings_screen.dart';
import 'package:invoice/state/caps.dart';

import '../business/e_harness.dart';
import '../fakes/commerce_fake.dart';
import '../fakes/fake_backend.dart';

void main() {
  late FakeBackend backend;
  setUp(() async {
    backend = await eSetUp();
    installCommerceFakes(backend);
  });
  testWidgets(
    'free release hides plans and refuses to open purchase flow',
    (tester) async {
      await pumpAs(
        tester,
        backend,
        Preset.owner,
        const ProfileSettingsScreen(),
      );
      expect(find.byKey(const Key('profile-plan-cta')), findsNothing);
      final context = tester.element(find.byType(ProfileSettingsScreen));
      await showBillingPlans(context);
      await settle(tester);
      expect(find.byType(PlansSheet), findsNothing);
      expect(find.byType(BillingCheckoutScreen), findsNothing);
    },
    skip: paidFeaturesEnabled,
  );
}
