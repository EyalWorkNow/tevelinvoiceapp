// 0.9 E2E finding: S2 searched only the first 500 customers, so with a capped
// list a customer outside them could never be picked. Over the cap S2 asks
// the server too (BE-09 search), like P.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/people/sheets/s2_customer.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/ds.dart';

import 'fakes/fake_api.dart';

void main() {
  late FakeBackend backend;
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('s2_search_test');
    AppCache.directoryProvider = () async => tmp;
  });

  setUp(() async {
    resetSession();
    await AppCache.clearAll();
    backend = FakeBackend()..install();
  });

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('capped list: a search finds a customer beyond the 500 on the server', (tester) async {
    installPeopleFakes(backend, be09: true);
    backend.on('GET', '/customers', (r) {
      if ((r.raw.url.queryParameters['q'] ?? '').isNotEmpty) {
        return FakeResponse(200, {
          'customers': [customerJson('far', 'רחוק מאוד', be09: true)],
        });
      }
      return FakeResponse(200, {
        'customers': [for (var i = 0; i < 500; i++) customerJson('c$i', 'לקוח $i', be09: true)],
      });
    });
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => signInAs(backend, Preset.owner));
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        locale: const Locale('he', 'IL'),
        supportedLocales: const [Locale('he', 'IL')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildTheme(Brightness.light),
        home: const Scaffold(body: Text('root')),
      ),
    );
    Customer? picked;
    unawaited(showCustomerSheet(navigatorKey.currentContext!).then((c) => picked = c));
    await flush(tester);

    await tester.enterText(find.byKey(const Key('s2-search')), 'רחוק');
    await flush(tester);
    expect(backend.last('GET', '/customers')!.query['q'], 'רחוק');
    await tester.tap(find.byKey(const Key('s2-row-far')));
    await flush(tester);
    expect(picked?.id, 'far');
  });
}
