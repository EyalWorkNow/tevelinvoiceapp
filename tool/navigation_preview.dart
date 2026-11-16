// Interactive simulator preview with in-memory fixtures; never contacts the API.
// flutter run -d <simulator> -t tool/navigation_preview.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:invoice/app_shell.dart';
import 'package:invoice/router.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/system_notices.dart';
import 'package:invoice/ui/widgets/notch_notice.dart';
import 'package:invoice/state/customer_crm_store.dart';
import 'package:invoice/ui/theme.dart';
import '../test/fakes/fake_api.dart';

Future<void> main() async {
  if (!kDebugMode) {
    throw StateError(
      'The simulator showcase is debug-only; build lib/main.dart',
    );
  }
  WidgetsFlutterBinding.ensureInitialized();
  CustomerCrmStore.instance.useDeviceLocalPreview();
  final previewDirectory = await Directory.systemTemp.createTemp(
    'navigation-preview',
  );
  AppCache.directoryProvider = () async => previewDirectory;
  resetSession();
  final backend = FakeBackend()..install();
  FakeLauncher().install();
  installBusinessFakes(backend);
  final issue = installIssueFakes(backend);
  installPeopleFakes(
    backend,
    be09: true,
    customers: [
      customerJson('c1', 'דניאל רוזן', phone: '0520000111', be09: true),
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
            number: '${1040 + i}',
            customerName: 'דניאל רוזן',
            total: i == 1 ? 28400 : 254800,
            issueDate: '2026-11-08',
          ),
      ],
    ),
  );
  // Inbox fixtures provide only a minimal document stub; completed requests
  // need the full document produced by the issue fixture.
  backend.on('GET', '/documents/:id', (request) {
    final id = request.params['id']!;
    if (!issue.docs.containsKey(id)) {
      return FakeResponse.error(404, 'DOCUMENT_NOT_FOUND');
    }
    return FakeResponse(200, issue.detail(id));
  });
  await signInAs(backend, Preset.owner);
  AppRouter.instance.install();
  currentTab.value = AppTab.home;
  systemNotices.install();
  runApp(
    MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      navigatorObservers: [AppRouter.instance.observer],
      debugShowCheckedModeBanner: false,
      locale: const Locale('he', 'IL'),
      supportedLocales: const [Locale('he', 'IL')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(Brightness.dark),
      builder: (context, child) => AppBackground(
        child: NotchNoticeHost(key: notchNoticeKey, child: child!),
      ),
      home: const AppShell(),
    ),
  );
  // Allows repeatable captures while leaving the simulator fully interactive.
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 9997);
  server.listen((request) async {
    if (request.uri.queryParameters['native'] == 'start') {
      request.response.write(await systemNotices.preview());
      await request.response.close();
      return;
    }
    if (request.uri.queryParameters['native'] == 'end') {
      await systemNotices.endAll();
    }
    final tab = request.uri.queryParameters['tab'];
    final matches = AppTab.values.where((value) => value.name == tab);
    if (matches.isNotEmpty) currentTab.value = matches.first;
    request.response.write(currentTab.value.name);
    await request.response.close();
  });
}
