import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api/settings_api.dart' show hideAmounts, loadHideAmounts;
import 'router.dart';
import 'screens/auth/app_lock.dart';
import 'screens/auth/splash_screen.dart';
import 'screens/people/sheets/s2_customer.dart';
import 'state/session.dart';
import 'ui/money_text.dart' show AmountPrivacy;
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppRouter.instance.install();
  loadHideAmounts();
  if (!kReleaseMode) {
    _startDevServer();
  }
  runApp(const TevelApp());
}

Future<void> _startDevServer() async {
  try {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 9999);
    server.listen((req) async {
      final to = req.uri.queryParameters['to'];
      final sheet = req.uri.queryParameters['sheet'];
      final pop = req.uri.queryParameters['pop'];
      if (pop == 'true') {
        final nav = navigatorKey.currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
          req.response.write('popped');
        } else {
          req.response.write('cannot pop');
        }
      } else if (to != null) {
        await go(to);
        req.response.write('navigated to $to');
      } else if (sheet == 'customer') {
        final ctx = navigatorKey.currentContext;
        if (ctx != null) {
          unawaited(showCustomerSheet(ctx));
          req.response.write('opened sheet $sheet');
        } else {
          req.response.write('no context');
        }
      } else {
        req.response.write('ok');
      }
      await req.response.close();
    });
  } catch (_) {}
}

class TevelApp extends StatefulWidget {
  const TevelApp({super.key});

  @override
  State<TevelApp> createState() => _TevelAppState();
}

class _TevelAppState extends State<TevelApp> {
  SessionStatus _last = session.status;

  @override
  void initState() {
    super.initState();
    session.addListener(_onSession);
  }

  @override
  void dispose() {
    session.removeListener(_onSession);
    super.dispose();
  }

  /// Signed in → signed out (logout, expiry, account deleted) always lands on S1.
  void _onSession() {
    final now = session.status;
    if (_last == SessionStatus.signedIn && now == SessionStatus.signedOut) {
      resetToLogin(expired: session.expired);
    }
    _last = now;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      navigatorObservers: [AppRouter.instance.observer],
      title: 'תבל',
      debugShowCheckedModeBanner: false,
      locale: const Locale('he', 'IL'),
      supportedLocales: const [Locale('he', 'IL')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.dark,
      builder: (context, child) => ValueListenableBuilder<bool>(
        valueListenable: hideAmounts,
        builder: (context, hidden, _) => AppBackground(
          child: AmountPrivacy(
            hidden: hidden,
            child: AppLockGate(child: child!),
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
