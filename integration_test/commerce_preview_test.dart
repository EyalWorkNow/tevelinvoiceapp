// Native visual review with isolated fixtures; no payment or message is sent.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/screens/billing/billing_screen.dart';
import 'package:invoice/screens/business/cardcom_merchant_screen.dart';
import 'package:invoice/screens/expense/expense_overview_screen.dart';
import 'package:invoice/router.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/ds.dart';
import '../test/business/e_harness.dart';
import '../test/fakes/commerce_fake.dart';
import '../test/fakes/fake_api.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('commerce native visual review', (tester) async {
    final backend = await eSetUp();
    installCommerceFakes(backend);
    await signInAs(backend, Preset.owner);
    AppRouter.instance.install();
    if (const bool.fromEnvironment('PLANS_PREVIEW_ONLY')) {
      await tester.pumpWidget(
        eApp(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showBillingPlans(context),
                  child: const Text('plans'),
                ),
              ),
            ),
          ),
          brightness: Brightness.dark,
        ),
      );
      await tester.tap(find.text('plans'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 1)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      debugPrint('COMMERCE_SHOT:carousel');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 30)),
      );
      await tester.ensureVisible(find.byKey(const Key('plans-continue')));
      await tester.tap(find.byKey(const Key('plans-continue')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      debugPrint('COMMERCE_SHOT:new-checkout');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 30)),
      );
      return;
    }
    if (const bool.fromEnvironment('MERCHANT_PREVIEW_ONLY')) {
      backend.json('GET', '/settings/cardcom', {
        'configured': false,
        'account': null,
        'canStore': true,
      });
      backend.json('GET', '/payments/cardcom-checkouts', {'checkouts': []});
      await tester.pumpWidget(
        eApp(
          const AppBackground(child: CardcomMerchantScreen()),
          brightness: Brightness.dark,
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 1)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      debugPrint('COMMERCE_SHOT:merchant');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 35)),
      );
      return;
    }

    await tester.pumpWidget(
      eApp(
        const AppBackground(child: ExpenseOverviewScreen()),
        brightness: Brightness.dark,
      ),
    );
    Future<void> shot(String name) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 1)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      debugPrint('COMMERCE_SHOT:$name');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 35)),
      );
    }

    await shot('expenses');
    await tester.ensureVisible(find.text('לאן הכסף הולך?'));
    await tester.pumpAndSettle();
    await shot('charts');
    unawaited(showBillingPlans(navigatorKey.currentContext!));
    await shot('plans');
    await tester.ensureVisible(find.byKey(const Key('plans-continue')));
    await tester.tap(find.byKey(const Key('plans-continue')));
    await shot('checkout');
  });
}
