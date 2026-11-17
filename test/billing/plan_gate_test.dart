// Walkthrough 2026-11-17 #10a: a 402 "plan required" from ANY issue path opens
// the plans sheet (owner only), once at a time, as a modal — never a reset.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/screens/billing/billing_screen.dart';
import 'package:invoice/screens/billing/plan_gate.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/util/errors_he.dart';

import '../business/e_harness.dart';
import '../fakes/commerce_fake.dart';
import '../fakes/fake_backend.dart';

void main() {
  late FakeBackend backend;
  setUp(() async {
    backend = await eSetUp();
    installCommerceFakes(backend);
    PlanGate.reset();
    PlanGate.showPlans = showBillingPlans;
    PlanGate.install();
  });

  Future<void> refuse(WidgetTester tester, String code) async {
    backend.error('POST', '/documents/:id/finalize', 402, code);
    await tester.runAsync(() async {
      try {
        await ApiClient.instance.post('/documents/d1/finalize', {});
      } on ApiException {
        // the screen shows its inline error
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await settle(tester);
  }

  testWidgets('owner: SUBSCRIPTION_REQUIRED opens the plans over the screen', (
    tester,
  ) async {
    await pumpAs(
      tester,
      backend,
      Preset.owner,
      const Scaffold(body: Text('המסך שהיה פתוח')),
    );
    await refuse(tester, 'SUBSCRIPTION_REQUIRED');
    expect(find.byType(PlansSheet), findsOneWidget);
    // A sheet on top: the screen under it is still there (no stack reset).
    expect(find.text('המסך שהיה פתוח', skipOffstage: false), findsOneWidget);
    // A second refusal while it is open does not stack another sheet.
    await refuse(tester, 'INVOICE_QUOTA_EXCEEDED');
    expect(find.byType(PlansSheet), findsOneWidget);
    expect(PlanGate.isOpen, isTrue);
  });

  testWidgets('quota used up → the plans too (upgrade)', (tester) async {
    await pumpAs(tester, backend, Preset.owner, const Scaffold());
    await refuse(tester, 'INVOICE_QUOTA_EXCEEDED');
    expect(find.byType(PlansSheet), findsOneWidget);
  });

  testWidgets('an employee is not offered a purchase (inline error only)', (
    tester,
  ) async {
    await pumpAs(tester, backend, Preset.employeeIssuer, const Scaffold());
    await refuse(tester, 'SUBSCRIPTION_REQUIRED');
    expect(find.byType(PlansSheet), findsNothing);
    expect(errorMessageHe('SUBSCRIPTION_REQUIRED'), contains('בעל העסק'));
  });

  testWidgets('other 402 / 4xx answers never open the plans', (tester) async {
    await pumpAs(tester, backend, Preset.owner, const Scaffold());
    await refuse(tester, 'PAYMENT_REQUIRED_SOMETHING_ELSE');
    backend.error(
      'POST',
      '/documents/:id/finalize',
      409,
      'SUBSCRIPTION_REQUIRED',
    );
    await tester.runAsync(() async {
      try {
        await ApiClient.instance.post('/documents/d1/finalize', {});
      } on ApiException {
        // expected
      }
    });
    await settle(tester);
    expect(find.byType(PlansSheet), findsNothing);
  });
}
