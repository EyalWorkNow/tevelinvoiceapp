import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/app_shell.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/auth/login_screen.dart';
import 'package:invoice/screens/business/business_screen.dart';
import 'package:invoice/screens/compose/compose_screen.dart';
import 'package:invoice/screens/document/document_screen.dart';
import 'package:invoice/screens/home/home_screen.dart';
import 'package:invoice/screens/people/people_screen.dart';
import 'package:invoice/screens/profile/profile_settings_screen.dart';
import 'package:invoice/screens/reports/reports_screen.dart';
import 'package:invoice/state/business_context.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/session.dart';
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
    int businesses = 1,
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
    await tester.runAsync(
      () => signInAs(backend, preset, businesses: businesses),
    );
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

  testWidgets(
    'QA 2026-11-15: a keyboard is taken out once — P does not overflow when '
    'the keyboard is up',
    (tester) async {
      await pumpShell(tester, Preset.owner);
      currentTab.value = AppTab.people;
      await tester.pumpAndSettle();
      expect(find.byType(PeopleScreen), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 1008);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final tabBody = MediaQuery.of(tester.element(find.byType(PeopleScreen)));
      expect(tabBody.viewInsets.bottom, 0);
    },
  );

  testWidgets('large reserved glass navigation; create action on Home only', (
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
    // ＋ slides out off Home; the capsule keeps its size (owner 2026-11-16).
    expect(find.byKey(const Key('tab-create')), findsNothing);
    await tester.tap(find.byKey(const Key('tab-profile')));
    await tester.pumpAndSettle();
    expect(currentTab.value, AppTab.profile);
    expect(find.byType(ProfileSettingsScreen), findsOneWidget);
    expect(find.byKey(const Key('tab-create')), findsNothing);
    await tester.tap(find.byKey(const Key('tab-home')));
    await tester.pumpAndSettle();
    expect(currentTab.value, AppTab.home);
    expect(find.byKey(const Key('home-create-glass')), findsOneWidget);
  });

  testWidgets(
    'capsule keeps its reference size and recenters during navigation',
    (tester) async {
      await pumpShell(tester, Preset.owner);
      // The owner sees לקוחות too (doc.view): one more item of the same size,
      // and the bar scales to fit 390pt with the orb beside it.
      const width4 = 206 + 62.808 + 3.538;
      const s = (390 - 24) / (width4 + 80 + 8);
      final capsule = find.byKey(const Key('navigation-capsule'));
      expect(tester.getSize(capsule), const Size(width4 * s, 72 * s));
      expect(
        tester.getSize(find.byKey(const Key('home-create-glass'))),
        const Size(80 * s, 80 * s),
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
      expect(tester.getSize(capsule), const Size(width4 * s, 72 * s));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('three tabs: the owner reference size 206 x 72 at 1.07', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402 * 3, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ShellBottomNavigation(
            current: AppTab.home,
            showCreate: true,
            onTab: (_) {},
            onCreate: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('navigation-capsule'))),
      const Size(206 * 1.07, 72 * 1.07),
    );
    expect(find.byKey(const Key('tab-people')), findsNothing);
  });

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
    '＋ follows the caps (doc.draft), never the role or the home tab; accountant home = R',
    (tester) async {
      await pumpShell(tester, Preset.viewer);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byKey(const Key('tab-create')), findsNothing);

      resetSession();
      await pumpShell(tester, Preset.accountantRep);
      expect(find.byKey(const Key('tab-create')), findsNothing);
      expect(find.byType(ReportsScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);

      // PM 2026-11-12: the full accountant may draft and issue → ＋, even
      // though the home tab is R.
      resetSession();
      await pumpShell(tester, Preset.accountantFull);
      expect(find.byKey(const Key('tab-create')), findsOneWidget);
      expect(find.byType(ReportsScreen), findsOneWidget);

      resetSession();
      await pumpShell(tester, Preset.employee);
      expect(find.byKey(const Key('tab-create')), findsOneWidget);
    },
  );

  testWidgets(
    'bar = [בית][לקוחות][ניהול][פרופיל]; לקוחות is a root tab gated by doc.view (§5)',
    (tester) async {
      await pumpShell(tester, Preset.owner);
      final x = {
        for (final k in ['home', 'people', 'business', 'profile'])
          k: tester.getCenter(find.byKey(Key('tab-$k'))).dx,
      };
      // RTL: בית on the right, then לקוחות, ניהול, פרופיל.
      expect(x['home']! > x['people']!, isTrue);
      expect(x['people']! > x['business']!, isTrue);
      expect(x['business']! > x['profile']!, isTrue);
      expect(
        find.descendant(
          of: find.byKey(const Key('tab-people')),
          matching: find.text('לקוחות'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('tab-people')));
      await tester.pumpAndSettle();
      expect(currentTab.value, AppTab.people);
      expect(find.byType(PeopleScreen), findsOneWidget);
      expect(
        tester.widget<PeopleScreen>(find.byType(PeopleScreen)).onBack,
        isNull,
        reason: 'a root tab has no back button',
      );
      expect(find.byKey(const Key('tab-create')), findsNothing); // Home only

      // Deep link /people → the tab.
      currentTab.value = AppTab.home;
      await tester.pumpAndSettle();
      expect(await go('tevel://people?chip=debtors'), isTrue);
      await tester.pumpAndSettle();
      expect(currentTab.value, AppTab.people);

      // A member without document:read: no tab, and the link is refused.
      backend.json('GET', '/me', {
        ...meJson(Preset.viewer),
        'permissions': <String>['money:read'],
      });
      await tester.runAsync(session.refreshBusiness);
      currentTab.value = AppTab.home;
      await tester.pumpAndSettle();
      expect(businessContext.caps.showPeopleTab, isFalse);
      expect(find.byKey(const Key('tab-people')), findsNothing);
      expect(find.byKey(const Key('tab-business')), findsOneWidget);
      expect(await go('/people'), isFalse);
      expect(currentTab.value, AppTab.home);
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

  testWidgets('1.4: entering home never asks for Contacts', (tester) async {
    await pumpShell(tester, Preset.owner, contactsPermissionPrompted: false);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('חיבור לאנשי הקשר'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    '1.11: a link closes an open dialog first; a forbidden one says so',
    (tester) async {
      await pumpShell(tester, Preset.employee);
      unawaited(
        showDialog<void>(
          context: navigatorKey.currentContext!,
          builder: (_) => const AlertDialog(content: Text('open dialog')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('open dialog'), findsOneWidget);
      expect(await go('tevel://doc/d1'), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('open dialog', skipOffstage: false), findsNothing);
      expect(find.byType(DocumentScreen), findsOneWidget);
      expect(AppRouter.instance.observer.stack.last, 'tevel://doc/d1');
      Navigator.of(tester.element(find.byType(DocumentScreen))).pop();
      await tester.pumpAndSettle();

      expect(await go('/reports'), isFalse);
      await tester.pump();
      expect(find.text('אין לך הרשאה למסך הזה'), findsOneWidget);
    },
  );

  testWidgets(
    '1.12: tevel://gate is ignored while signed in; a businessId link asks first',
    (tester) async {
      await pumpShell(tester, Preset.owner, businesses: 2);
      expect(await go('tevel://gate'), isFalse);
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);

      final asked = <String>[];
      final original = confirmBusinessSwitch;
      addTearDown(() => confirmBusinessSwitch = original);
      confirmBusinessSwitch = (name) async {
        asked.add(name);
        return false;
      };
      final before = session.business?.businessId;
      final other = session.account!.businesses.firstWhere(
        (b) => b.businessId != before,
      );
      expect(await go('/activity?businessId=${other.businessId}'), isFalse);
      expect(asked, [other.legalName]);
      expect(session.business?.businessId, before);
    },
  );
}
