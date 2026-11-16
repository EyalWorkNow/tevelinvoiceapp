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
    double width = 390,
    double textScale = 1,
    bool reducedMotion = false,
  }) async {
    tester.view.physicalSize = Size(width * 3, 2532);
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reducedMotion,
          ),
          child: child!,
        ),
        home: const AppShell(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('reference glass navigation; create action only at home', (
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
    'capsule keeps its reference size and recenters during navigation',
    (tester) async {
      await pumpShell(tester, Preset.owner);
      final capsule = find.byKey(const Key('navigation-capsule'));
      expect(tester.getSize(capsule), const Size(206 * 1.07, 72 * 1.07));
      expect(
        tester.getSize(find.byKey(const Key('home-create-glass'))),
        const Size(80 * 1.07, 80 * 1.07),
      );
      final homeX = tester.getCenter(capsule).dx;
      await tester.tap(find.byKey(const Key('tab-business')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getCenter(capsule).dx, greaterThan(homeX));
      expect(tester.getCenter(capsule).dx, lessThan(195));
      expect(find.byKey(const Key('tab-create')), findsNothing);
      await tester.pumpAndSettle();
      expect(tester.getCenter(capsule).dx, closeTo(195, .01));
      expect(tester.getSize(capsule), const Size(206 * 1.07, 72 * 1.07));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tab press compresses and releases without changing its hit area',
    (tester) async {
      await pumpShell(tester, Preset.owner);
      final tab = find.byKey(const Key('tab-home'));
      final hitSize = tester.getSize(tab);
      final gesture = await tester.startGesture(tester.getCenter(tab));
      await tester.pump(const Duration(milliseconds: 150));
      final pressScale = find.descendant(
        of: tab,
        matching: find.byType(AnimatedScale),
      );
      expect(tester.widget<AnimatedScale>(pressScale).scale, .93);
      expect(tester.getSize(tab), hitSize);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedScale>(pressScale).scale, 1);
    },
  );

  for (final width in [320.0, 402.0]) {
    testWidgets(
      'navigation fits at width $width with large text and reduced motion',
      (tester) async {
        await pumpShell(
          tester,
          Preset.owner,
          width: width,
          textScale: 2,
          reducedMotion: true,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('tab-business')));
        await tester.pump();
        expect(find.byKey(const Key('tab-create')), findsNothing);
        expect(
          tester.getCenter(find.byKey(const Key('navigation-capsule'))).dx,
          closeTo(width / 2, .01),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

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
