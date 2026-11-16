import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/screens/compose/payment_coming_soon_screen.dart';
import 'package:invoice/ui/theme.dart';

void main() {
  for (final textScale in [1.0, 2.0]) {
    testWidgets(
      'coming soon fits a narrow screen at text scale $textScale and returns',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.dark),
            locale: const Locale('he', 'IL'),
            supportedLocales: const [Locale('he', 'IL')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const PaymentComingSoonScreen(),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('payment-coming-soon')), findsOneWidget);
        expect(find.text('בקרוב'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const Key('payment-coming-soon-back')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('payment-coming-soon-back')));
        await tester.pumpAndSettle();
        expect(find.text('open'), findsOneWidget);
      },
    );
  }
}
