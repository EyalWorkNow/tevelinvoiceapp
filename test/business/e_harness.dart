// Squad E test harness: app with the real navigator keys, a fake backend with
// E's defaults, and a tap counter for the §7 journeys.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/reports_api.dart' show resetReportsProbe;
import 'package:invoice/api/settings_api.dart' show resetFeatureProbes;
import 'package:invoice/api/team_api.dart' show resetAccountantRepProbe;
import 'package:invoice/app_shell.dart';
import 'package:invoice/router.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/theme.dart';

import '../fakes/fake_api.dart';

Directory? _tmp;

/// setUp for every E test: clean session, Keychain, cache dir, backend.
Future<FakeBackend> eSetUp() async {
  _tmp ??= await Directory.systemTemp.createTemp('e_test');
  AppCache.directoryProvider = () async => _tmp!;
  FlutterSecureStorage.setMockInitialValues({});
  resetSession();
  resetFeatureProbes();
  resetAccountantRepProbe();
  resetReportsProbe();
  currentTab.value = AppTab.home;
  final backend = FakeBackend()..install();
  installBusinessFakes(backend);
  return backend;
}

Widget eApp(Widget home, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      navigatorObservers: [AppRouter.instance.observer],
      locale: const Locale('he', 'IL'),
      supportedLocales: const [Locale('he', 'IL')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(brightness),
      home: home,
    );

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Signs in as [preset] and pumps [home].
Future<void> pumpAs(
  WidgetTester tester,
  FakeBackend backend,
  Preset preset,
  Widget home, {
  String businessType = 'OSEK_MURSHE',
  int businesses = 1,
  Map<String, dynamic>? approvalPolicy,
  Map<String, dynamic>? profile,
}) async {
  phone(tester);
  await tester.runAsync(
    () => signInAs(
      backend,
      preset,
      businessType: businessType,
      businesses: businesses,
      approvalPolicy: approvalPolicy,
      profile: profile,
    ),
  );
  await tester.pumpWidget(eApp(home));
  await settle(tester);
}

/// pumpAndSettle that also lets the fake's real async work (cache files) run.
Future<void> settle(WidgetTester tester) async {
  var quietFrames = 0;
  for (var i = 0; i < 400 && quietFrames < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    quietFrames = tester.binding.hasScheduledFrame ? 0 : quietFrames + 1;
  }
  await tester.pumpAndSettle();
}

/// Counts taps on the counted journey (§1 F3.1).
class Taps {
  int count = 0;

  Future<void> tap(WidgetTester tester, Finder f) async {
    count++;
    // Disk-backed caches and asynchronous feature probes can complete after
    // route animation settles, especially when the suite runs concurrently.
    for (var i = 0; i < 50 && f.evaluate().isEmpty; i++) {
      await settle(tester);
    }
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await settle(tester);
  }
}
