// Shared harness for DS tests: Hebrew RTL app, theme, text scale, privacy.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:invoice/ui/ds.dart';

Widget dsApp(
  Widget child, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
  bool hideAmounts = false,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('he', 'IL'),
  supportedLocales: const [Locale('he', 'IL')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: buildTheme(brightness),
  builder: (context, app) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: AppBackground(
      child: AmountPrivacy(hidden: hideAmounts, child: app!),
    ),
  ),
  home: Scaffold(body: child),
);
