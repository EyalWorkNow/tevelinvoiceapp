import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/app_shell.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/compose/compose_screen.dart';
import 'package:invoice/screens/people/sheets/s2_customer.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/app_page_route.dart';
import 'package:invoice/ui/ds.dart';

import 'business/e_harness.dart';
import 'fakes/fake_api.dart';

void main() {
  late FakeBackend backend;
  final originalPicker = pickCustomer;
  final originalContactPicker = pickContact;

  setUp(() async {
    backend = await eSetUp();
    installIssueFakes(backend);
    installPeopleFakes(backend);
    pickCustomer = (context) => showCustomerSheet(context);
    await signInAs(backend, Preset.owner);
  });
  tearDown(() {
    pickCustomer = originalPicker;
    pickContact = originalContactPicker;
  });

  Future<BuildContext> start(WidgetTester tester) async {
    phone(tester);
    late BuildContext root;
    await tester.pumpWidget(
      eApp(
        Builder(
          builder: (context) {
            root = context;
            return const Scaffold(body: Text('origin'));
          },
        ),
        brightness: Brightness.dark,
      ),
    );
    return root;
  }

  for (final intent in ['PAID', 'REQUEST']) {
    testWidgets(
      '$intent: cancel customer selection returns to origin without keypad',
      (tester) async {
        final root = await start(tester);
        unawaited(openCompose(root, intent: intent));
        await settle(tester);
        expect(find.byType(CustomerSheet), findsOneWidget);
        await tester.tap(find.byType(DesignBackButton).last);
        // Inspect intermediate frames as well as the final destination.
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          expect(find.byType(Keypad), findsNothing);
        }
        await settle(tester);
        expect(find.text('origin'), findsOneWidget);
        expect(find.byType(ComposeScreen), findsNothing);
        expect(navigatorKey.currentState!.canPop(), isFalse);
      },
    );
  }

  testWidgets(
    'back during composer loading never opens a late customer picker',
    (tester) async {
      final response = Completer<FakeResponse>();
      backend.on('GET', '/tax-rates', (_) => response.future);
      final root = await start(tester);
      unawaited(openCompose(root, intent: 'REQUEST'));
      await tester.pumpAndSettle();
      expect(find.byType(SkeletonList), findsOneWidget);
      navigatorKey.currentState!.pop();
      // Complete the network call while the outgoing route is still mounted.
      response.complete(const FakeResponse(200, {'rates': []}));
      await settle(tester);
      expect(find.text('origin'), findsOneWidget);
      expect(find.byType(CustomerSheet), findsNothing);
      expect(find.byType(Keypad), findsNothing);
      expect(navigatorKey.currentState!.canPop(), isFalse);
    },
  );

  for (final open in <String, Future<void> Function(BuildContext)>{
    'documents': (c) => openActivity(c),
    'expenses': (c) => openExpenses(c),
  }.entries) {
    testWidgets(
      '${open.key}: back returns to origin; repeated taps cannot stack pages',
      (tester) async {
        final root = await start(tester);
        unawaited(open.value(root));
        unawaited(open.value(root));
        await settle(tester);
        await tester.tap(find.byType(DesignBackButton).last);
        await settle(tester);
        expect(find.text('origin'), findsOneWidget);
        expect(navigatorKey.currentState!.canPop(), isFalse);
        expect(find.byType(Keypad), findsNothing);
      },
    );
  }

  testWidgets('new customer form back returns to customer selection', (
    tester,
  ) async {
    final root = await start(tester);
    pickContact = () async => null;
    unawaited(showCustomerSheet(root));
    await settle(tester);
    await tester.tap(find.byKey(const Key('s2-new')));
    await settle(tester);
    expect(find.byKey(const Key('s2-name')), findsOneWidget);
    await tester.tap(find.byType(DesignBackButton));
    await settle(tester);
    expect(find.byKey(const Key('s2-search')), findsOneWidget);
    expect(find.byKey(const Key('s2-name')), findsNothing);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'navigation labels and targets fit at 320pt and text scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(960, 2400);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          eApp(
            MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                bottomNavigationBar: TabBarWithCreate(
                  current: AppTab.home,
                  showCreate: true,
                  onTab: (_) {},
                  onCreate: () {},
                ),
              ),
            ),
            brightness: Brightness.dark,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final name in ['home', 'business', 'profile', 'create']) {
          final size = tester.getSize(find.byKey(Key('tab-$name')));
          expect(size.width, greaterThanOrEqualTo(44));
          expect(size.height, greaterThanOrEqualTo(44));
        }
        expect(find.text('ניהול'), findsOneWidget);
        expect(find.text('פרופיל'), findsOneWidget);
      },
    );
  }

  testWidgets('routes paint their own background', (tester) async {
    final root = await start(tester);
    unawaited(
      Navigator.of(root).push(
        AppPageRoute<void>(builder: (_) => const Scaffold(body: Text('next'))),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final routeContext = tester.element(find.text('next'));
    expect(
      routeContext.findAncestorWidgetOfExactType<AppBackground>(),
      isNotNull,
    );
    await tester.pumpAndSettle();
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('origin'), findsOneWidget);
  });
}
