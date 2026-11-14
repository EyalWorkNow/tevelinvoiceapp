// Isolated simulator showcase. All API calls use in-memory fixtures.
// flutter run -d <simulator> -t tool/notch_preview.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:invoice/app_shell.dart';
import 'package:invoice/router.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/customer_crm_store.dart';
import 'package:invoice/state/business_context.dart';
import 'crm_preview_data.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/system_notices.dart';
import 'package:invoice/ui/theme.dart';
import 'package:invoice/ui/widgets/notch_notice.dart';

import '../test/fakes/fake_api.dart';

const _examples = <NoticeMotion, String>{
  NoticeMotion.document: 'חשבונית 1042 הופקה בהצלחה',
  NoticeMotion.sent: 'הדוח נשלח לרואה החשבון',
  NoticeMotion.signed: 'המסמכים נחתמו. הכול מוכן.',
  NoticeMotion.payment: 'התשלום נרשם בהצלחה',
  NoticeMotion.reminder: 'התזכורות נשלחו ללקוחות',
  NoticeMotion.saved: 'עיצוב המסמכים נשמר',
  NoticeMotion.error: 'אין חיבור כרגע. נסו שוב.',
  NoticeMotion.approved: 'הלקוח אישר את הצעת המחיר!',
};

void _show(NoticeMotion motion) {
  final host = notchNoticeKey.currentState;
  if (host == null) return;
  host.clear();
  host.show(SnackBar(content: Text(_examples[motion]!)), motion: motion);
}

Future<void> main() async {
  if (!kDebugMode) {
    throw StateError('The simulator showcase is debug-only; build lib/main.dart');
  }
  WidgetsFlutterBinding.ensureInitialized();
  CustomerCrmStore.instance.useDeviceLocalPreview();
  final previewDirectory = await Directory.systemTemp.createTemp(
    'notch-preview',
  );
  AppCache.directoryProvider = () async => previewDirectory;
  resetSession();
  final backend = FakeBackend()..install();
  installBusinessFakes(backend);
  installIssueFakes(backend);
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
  await signInAs(backend, Preset.owner);
  AppRouter.instance.install();
  currentTab.value = AppTab.home;
  runApp(const _PreviewApp());
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 9998);
  server.listen((request) async {
    if (request.uri.queryParameters['crm'] == 'seed') {
      await seedCrmPreview(businessContext.business!.businessId);
    }
    final destination = request.uri.queryParameters['to'];
    if (destination != null) unawaited(go(destination));
    if (request.uri.queryParameters['native'] == 'start') {
      try {
        request.response.write(await systemNotices.preview());
      } catch (error) {
        request.response.statusCode = 500;
        request.response.write(error);
      }
      await request.response.close();
      return;
    }
    if (request.uri.queryParameters['native'] == 'end') {
      await systemNotices.endAll();
    }
    final name = request.uri.queryParameters['motion'];
    final matches = NoticeMotion.values.where((motion) => motion.name == name);
    if (matches.isNotEmpty) _show(matches.first);
    request.response.write('preview: $name');
    await request.response.close();
  });
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
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
    home: const _PreviewHome(),
  );
}

class _PreviewHome extends StatefulWidget {
  const _PreviewHome();
  @override
  State<_PreviewHome> createState() => _PreviewHomeState();
}

class _PreviewHomeState extends State<_PreviewHome> {
  int _index = 0;
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const AppShell(),
      Positioned(
        bottom: MediaQuery.viewPaddingOf(context).bottom + 82,
        left: 18,
        child: Material(
          color: Colors.black,
          borderRadius: BorderRadius.circular(24),
          child: TextButton.icon(
            onPressed: () {
              _show(NoticeMotion.values[_index++ % NoticeMotion.values.length]);
            },
            icon: const Icon(
              Icons.play_arrow_rounded,
              color: DesignTokens.green,
            ),
            label: const Text(
              'אנימציה הבאה',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    ],
  );
}
