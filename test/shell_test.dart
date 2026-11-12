import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/app_shell.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/business/business_screen.dart';
import 'package:invoice/screens/compose/compose_screen.dart';
import 'package:invoice/screens/document/document_screen.dart';
import 'package:invoice/screens/home/home_screen.dart';
import 'package:invoice/screens/people/people_screen.dart';
import 'package:invoice/screens/profile/profile_settings_screen.dart';
import 'package:invoice/screens/reports/reports_screen.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/theme.dart';

import 'fakes/fake_api.dart';

void main() {
  late FakeBackend backend;
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('shell_test');
    AppCache.directoryProvider = () async => tmp;
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    resetSession();
    currentTab.value = AppTab.home;
    backend = FakeBackend()..install();
  });

  Future<void> pumpShell(
    WidgetTester tester,
    Preset preset, {
    bool contactsPermissionPrompted = true,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(
      () => AppCache.write(
        'contacts_permission_prompted',
        contactsPermissionPrompted,
      ),
    );
    await tester.runAsync(() => signInAs(backend, preset));
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: messengerKey,
        navigatorObservers: [AppRouter.instance.observer],
        locale: const Locale('he', 'IL'),
        supportedLocales: const [Locale('he', 'IL')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildTheme(Brightness.light),
        home: const AppShell(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('large reserved glass navigation; create action only at home', (
    tester,
  ) async {
    await pumpShell(tester, Preset.owner);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byKey(const Key('home-profile-avatar')), findsOneWidget);
    expect(find.textContaining('שלום,'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Scaffold && widget.bottomNavigationBar != null,
      ),
      findsAtLeastNWidgets(1),
    );
    expect(find.byKey(const Key('tab-home')), findsOneWidget);
    expect(find.byKey(const Key('tab-business')), findsOneWidget);
    expect(find.byKey(const Key('tab-profile')), findsOneWidget);
    expect(find.byKey(const Key('home-create-glass')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab-create')));
    await tester.pumpAndSettle();
    expect(find.byType(ComposeScreen), findsOneWidget);
    expect(
      AppRouter.instance.observer.stack.any(
        (route) => route.contains('/compose'),
      ),
      isTrue,
    );
    Navigator.of(
      tester.element(find.byType(AppShell, skipOffstage: false)),
    ).popUntil((route) => route.isFirst);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('tab-business')));
    await tester.pumpAndSettle();
    expect(currentTab.value, AppTab.business);
    expect(find.byType(BusinessScreen), findsOneWidget);
    expect(find.byKey(const Key('tab-create')), findsNothing);
    await tester.tap(find.byKey(const Key('tab-profile')));
    await tester.pumpAndSettle();
    expect(currentTab.value, AppTab.profile);
    expect(find.byType(ProfileSettingsScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('tab-home')));
    await tester.pumpAndSettle();
    expect(currentTab.value, AppTab.home);
    expect(find.byKey(const Key('home-create-glass')), findsOneWidget);
  });

  testWidgets(
    'no invoice action for read-only and accountant presets; accountant home = R',
    (tester) async {
      await pumpShell(tester, Preset.viewer);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byKey(const Key('tab-create')), findsNothing);

      resetSession();
      await pumpShell(tester, Preset.accountantRep);
      expect(find.byKey(const Key('tab-create')), findsNothing);
      expect(find.byType(ReportsScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);

      resetSession();
      await pumpShell(tester, Preset.accountantFull);
      expect(find.byKey(const Key('tab-create')), findsNothing);
      expect(find.byType(ReportsScreen), findsOneWidget);
    },
  );

  testWidgets('go(): deep link opens D; a route the caps forbid is refused', (
    tester,
  ) async {
    await pumpShell(tester, Preset.employee);
    expect(await go('tevel://doc/d1'), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(DocumentScreen), findsOneWidget);
    expect(AppRouter.instance.observer.stack.last, 'tevel://doc/d1');
    Navigator.of(tester.element(find.byType(DocumentScreen))).pop();
    await tester.pumpAndSettle();

    expect(await go('/reports'), isFalse);
    expect(await go('/business/team'), isFalse);
    expect(await go('/people?chip=debtors'), isTrue);
    await tester.pumpAndSettle();
    expect(currentTab.value, AppTab.people);
    expect(
      tester.widget<PeopleScreen>(find.byType(PeopleScreen)).chip,
      'debtors',
    );
  });

  testWidgets(
    '403 → toast "ההרשאות שלך עודכנו" and back home from a forbidden screen',
    (tester) async {
      await pumpShell(tester, Preset.owner);
      expect(await go('/business/team'), isTrue);
      await tester.pumpAndSettle();
      expect(
        tester.widget<BusinessScreen>(find.byType(BusinessScreen)).section,
        'team',
      );
      // Demoted to employee elsewhere; the next call answers 403.
      backend
        ..json('GET', '/me', meJson(Preset.employee))
        ..error('GET', '/business/members', 403, 'FORBIDDEN');
      AppRouter.instance.install();
      await tester.runAsync(() async {
        try {
          await ApiClient.instance.get('/business/members');
        } on ApiException {
          // expected
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('ההרשאות שלך עודכנו'), findsOneWidget);
      expect(
        find.byType(BusinessScreen),
        findsNothing,
      ); // sub-page gone, home tab shown
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(AppRouter.instance.observer.stack, ['/home']);
    },
  );
}
