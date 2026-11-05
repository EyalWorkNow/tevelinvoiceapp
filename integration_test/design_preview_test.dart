// Native visual checks with in-memory API fixtures; never contacts a server.
// Capture each DESIGN_SHOT marker with simctl while the frame is held.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/app_shell.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/people/sheets/s2_customer.dart';
import 'package:invoice/screens/business/sheets/s13_editor.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/ds.dart';

import '../test/fakes/fake_api.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('reference design and shared screens on native iOS', (
    tester,
  ) async {
    final tmp = await Directory.systemTemp.createTemp('tevel-design-preview');
    AppCache.directoryProvider = () async => tmp;
    FlutterSecureStorage.setMockInitialValues({});
    resetSession();
    final backend = FakeBackend()..install();
    installBusinessFakes(backend);
    installIssueFakes(backend);
    installPeopleFakes(
      backend,
      be09: true,
      customers: [
        for (var i = 1; i <= 8; i++)
          customerJson(
            'c$i',
            ['דניאל רוזן', 'פלוני אלמוני', 'נועה לוי', 'יובל כהן'][(i - 1) % 4],
            phone: '0520000111',
            be09: true,
            lastDocumentAt: '2026-11-01',
          ),
      ],
    );
    installInboxFakes(
      backend,
      mobileInbox: mobileInboxJson(
        open: 6587400,
        recent: [
          for (var i = 1; i <= 5; i++)
            recentJson(
              'd$i',
              number: '${1000 + i}',
              customerName: 'דניאל רוזן פרילאנסרית',
              total: i == 1 ? 28400 : 254800,
              issueDate: '2026-11-01',
            ),
        ],
      ),
    );
    await signInAs(backend, Preset.owner);
    AppRouter.instance.install();
    currentTab.value = AppTab.home;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: messengerKey,
        navigatorObservers: [AppRouter.instance.observer],
        debugShowCheckedModeBanner: false,
        locale: const Locale('he', 'IL'),
        supportedLocales: const [Locale('he', 'IL')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildTheme(Brightness.dark),
        builder: (context, child) => AppBackground(child: child!),
        home: const AppShell(),
      ),
    );
    Future<void> shot(String name) async {
      // Native asset decoding and cache reads finish outside the test clock.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 1)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      debugPrint('DESIGN_SHOT:$name');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 3)),
      );
    }

    await shot('home');
    unawaited(showCustomerSheet(navigatorKey.currentContext!));
    await shot('customer');
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    unawaited(
      openCompose(
        navigatorKey.currentContext!,
        intent: 'PAID',
        customerId: 'c1',
      ),
    );
    await shot('amount-empty');
    for (final digit in ['2', '5', '4', '8']) {
      await tester.tap(
        find.descendant(of: find.byType(Keypad), matching: find.text(digit)),
      );
      await tester.pumpAndSettle();
    }
    await shot('amount-filled');
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    currentTab.value = AppTab.people;
    await shot('people');
    currentTab.value = AppTab.business;
    await shot('business');
    unawaited(openReports(navigatorKey.currentContext!));
    await shot('reports');
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    unawaited(showEditorSheet(navigatorKey.currentContext!, instance: '13.9'));
    await shot('desktop');
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    currentTab.value = AppTab.home;
    unawaited(openCompose(navigatorKey.currentContext!, intent: 'REQUEST'));
    await shot('request-customer');
    await tester.tap(find.byType(DesignBackButton).last);
    await tester.pumpAndSettle();
    expect(find.byType(Keypad), findsNothing);
    expect(navigatorKey.currentState!.canPop(), isFalse);
    await shot('request-cancelled');
  });
}
