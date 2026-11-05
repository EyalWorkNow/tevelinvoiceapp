import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/commerce_api.dart';
import 'package:invoice/screens/billing/billing_screen.dart';
import 'package:invoice/screens/expense/expense_overview_screen.dart';
import 'package:invoice/screens/business/cardcom_merchant_screen.dart';
import 'package:invoice/util/allowed_urls.dart';
import 'business/e_harness.dart';
import 'fakes/commerce_fake.dart';
import 'fakes/fake_backend.dart';

void main() {
  late FakeBackend backend;
  setUp(() async {
    backend = await eSetUp();
    installCommerceFakes(backend);
  });
  testWidgets(
    'selecting a plan opens its checkout with the exact VAT-inclusive price',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(
        eApp(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => unawaited(showBillingPlans(context)),
                child: const Text('plans'),
              ),
            ),
          ),
          brightness: Brightness.dark,
        ),
      );
      await tester.tap(find.text('plans'));
      await settle(tester);
      expect(find.byKey(const Key('plan-START')), findsOneWidget);
      expect(find.byKey(const Key('plan-GROW')), findsOneWidget);
      expect(find.byKey(const Key('plan-UNLIMITED')), findsOneWidget);
      await tester.tap(find.byKey(const Key('plan-dot-START')));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('plans-continue')));
      await tester.tap(find.byKey(const Key('plans-continue')));
      await settle(tester);
      expect(find.byType(BillingCheckoutScreen), findsOneWidget);
      expect(find.text('עד 21 מסמכי הכנסה בכל חודש'), findsOneWidget);
      expect(find.text('כלול במחיר'), findsOneWidget);
      await tester.tap(find.byKey(const Key('checkout-pay')));
      await settle(tester);
      expect(backend.calls('POST', '/billing/checkout'), isEmpty);
      expect(find.text('יש לאשר את פרטי המסלול לפני התשלום'), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.tap(find.byKey(const Key('checkout-pay')));
      await settle(tester);
      expect(backend.last('POST', '/billing/checkout')!.body, {
        'planCode': 'START',
        'accepted': true,
      });
      expect(find.text('העסק שלך מוכן להמשיך'), findsNothing);
    },
  );
  testWidgets('horizontal swiping changes the selected carousel page', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      eApp(const Scaffold(body: PlansSheet()), brightness: Brightness.dark),
    );
    await settle(tester);
    final page = tester.widget<PageView>(
      find.byKey(const Key('plans-carousel')),
    );
    expect(page.controller!.page, 1);
    await tester.drag(
      find.byKey(const Key('plans-carousel')),
      const Offset(280, 0),
    );
    await tester.pumpAndSettle();
    expect(page.controller!.page, isNot(1));
  });
  testWidgets(
    'expense overview filters categories and persists classification',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(
        eApp(const ExpenseOverviewScreen(), brightness: Brightness.dark),
      );
      await settle(tester);
      expect(find.text('סך ההוצאות החודש'), findsOneWidget);
      expect(find.text('לאן הכסף הולך?'), findsOneWidget);
      await tester.ensureVisible(find.text('לאן הכסף הולך?'));
      await tester.ensureVisible(find.text('ציוד משרדי').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('ציוד משרדי').first);
      await tester.pumpAndSettle();
      final row = find.text('דברים קטנים למשרד');
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await settle(tester);
      expect(find.text('מסדרים את ההוצאה'), findsOneWidget);
      await tester.tap(find.text('פרטית').last);
      await tester.ensureVisible(find.text('שומרים סיווג'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('שומרים סיווג'));
      await settle(tester);
      expect(
        backend.last('PATCH', '/expenses/:id/recognition')!.body,
        containsPair('classification', 'PERSONAL'),
      );
      expect(
        backend.last('PATCH', '/expenses/:id/recognition')!.body,
        containsPair('expensePercent', 0),
      );
      expect(find.text('מסדרים את ההוצאה'), findsNothing);
    },
  );
  testWidgets(
    'active subscription shows usage and cancellation requires confirmation',
    (tester) async {
      var cancelled = false;
      backend.on(
        'GET',
        '/billing/subscription',
        (_) => FakeResponse(200, {
          'active': true,
          'needsPlan': false,
          'usedInvoices': 12,
          'subscription': {
            'plan_code': 'GROW',
            'period_end': '2026-12-04T00:00:00Z',
            'cancel_at_period_end': cancelled,
          },
        }),
      );
      backend.on('POST', '/billing/subscription/cancel', (_) {
        cancelled = true;
        return const FakeResponse(200, {'cancelAtPeriodEnd': true});
      });
      phone(tester);
      await tester.pumpWidget(
        eApp(const Scaffold(body: PlansSheet()), brightness: Brightness.dark),
      );
      await settle(tester);
      expect(find.text('12 מסמכי הכנסה הופקו החודש'), findsOneWidget);
      await tester.tap(find.text('ביטול חידוש המסלול'));
      await settle(tester);
      expect(cancelled, isFalse);
      await tester.tap(find.text('ביטול החידוש'));
      await settle(tester);
      expect(cancelled, isTrue);
      expect(
        find.text('החידוש בוטל. המסלול פעיל עד סוף התקופה ששולמה.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'business merchant credentials require ownership acknowledgement and are cleared after save',
    (tester) async {
      backend.json('GET', '/settings/cardcom', {
        'configured': false,
        'account': null,
        'canStore': true,
      });
      backend.json('GET', '/payments/cardcom-checkouts', {'checkouts': []});
      backend.json('PUT', '/settings/cardcom', {
        'configured': true,
        'verified': false,
      });
      phone(tester);
      await tester.pumpWidget(
        eApp(const CardcomMerchantScreen(), brightness: Brightness.dark),
      );
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('merchant-terminal')),
        '1234',
      );
      await tester.enterText(
        find.byKey(const Key('merchant-api-name')),
        'fixture-api-name',
      );
      await tester.ensureVisible(find.byKey(const Key('merchant-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('merchant-save')));
      await settle(tester);
      expect(backend.calls('PUT', '/settings/cardcom'), isEmpty);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.ensureVisible(find.byKey(const Key('merchant-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('merchant-save')));
      await settle(tester);
      expect(backend.last('PUT', '/settings/cardcom')!.body, {
        'terminalNumber': '1234',
        'apiName': 'fixture-api-name',
        'acceptedOwnership': true,
      });
      final field = tester.widget<TextField>(
        find.byKey(const Key('merchant-api-name')),
      );
      expect(field.controller!.text, isEmpty);
    },
  );
  testWidgets(
    'BIT selection is sent to the server without claiming payment succeeded',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(
        eApp(
          const BillingCheckoutScreen(
            plan: BillingPlan(
              code: 'START',
              name: 'מתחילים',
              monthlyMinor: 800,
              limit: 21,
            ),
          ),
          brightness: Brightness.dark,
        ),
      );
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('payment-BIT')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('payment-BIT')));
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.tap(find.byKey(const Key('checkout-pay')));
      await settle(tester);
      expect(
        backend.last('POST', '/billing/checkout')!.body,
        containsPair('paymentMethod', 'BIT'),
      );
      expect(find.text('העסק שלך מוכן להמשיך'), findsNothing);
    },
  );
  for (final width in [320.0, 402.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'expense dashboard and checkout fit $width pt at $scale text',
        (tester) async {
          tester.view.physicalSize = Size(width * 3, 844 * 3);
          tester.view.devicePixelRatio = 3;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpWidget(
            eApp(
              const Scaffold(body: PlansSheet()),
              brightness: Brightness.dark,
            ),
          );
          await settle(tester);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(
            find.byKey(const Key('plan-dot-UNLIMITED')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('plan-dot-UNLIMITED')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(
            eApp(const ExpenseOverviewScreen(), brightness: Brightness.dark),
          );
          await settle(tester);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('לאן הכסף הולך?'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(
            eApp(
              const BillingCheckoutScreen(
                plan: BillingPlan(
                  code: 'UNLIMITED',
                  name: 'בלי גבולות',
                  monthlyMinor: 1500,
                ),
              ),
              brightness: Brightness.dark,
            ),
          );
          await settle(tester);
          expect(tester.takeException(), isNull);
          backend.json('GET', '/settings/cardcom', {
            'configured': false,
            'account': null,
            'canStore': true,
          });
          backend.json('GET', '/payments/cardcom-checkouts', {'checkouts': []});
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(
            eApp(const CardcomMerchantScreen(), brightness: Brightness.dark),
          );
          await settle(tester);
          expect(tester.takeException(), isNull);
          await tester.scrollUntilVisible(
            find.byKey(const Key('merchant-save')),
            250,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  test(
    'payment browser target is restricted to the Cardcom hosted payment origin',
    () async {
      await expectLater(
        () => openPaymentPage(
          Uri.parse('https://secure.cardcom.solutions.evil/EA/test'),
        ),
        throwsArgumentError,
      );
      await expectLater(
        () => openPaymentPage(
          Uri.parse('http://secure.cardcom.solutions/EA/test'),
        ),
        throwsArgumentError,
      );
      await expectLater(
        () => openPaymentPage(
          Uri.parse('https://secure.cardcom.solutions:8443/EA/test'),
        ),
        throwsArgumentError,
      );
      await expectLater(
        () => openPaymentPage(
          Uri.parse('https://someone@secure.cardcom.solutions/EA/test'),
        ),
        throwsArgumentError,
      );
    },
  );
}
