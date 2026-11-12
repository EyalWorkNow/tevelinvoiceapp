import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/screens/business/cardcom_merchant_screen.dart';
import 'package:invoice/ui/theme.dart';
import 'package:invoice/ui/widgets/notch_notice.dart';

void main() {
  testWidgets(
    'payment attempt shows a coming soon notice from the notch without collecting card data',
    (tester) async {
      final messenger = GlobalKey<ScaffoldMessengerState>();
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          scaffoldMessengerKey: messenger,
          builder: (context, child) =>
              NotchNoticeHost(key: notchNoticeKey, child: child!),
          home: CustomerPaymentPreviewScreen(
            businessName: 'סטודיו תבל',
            invoiceLabel: 'חשבונית לדוגמה',
            amountMinor: BigInt.from(11800),
          ),
        ),
      );

      expect(find.byType(TextField), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const Key('secure-payment-continue')),
        320,
      );
      expect(find.text('בקרוב'), findsOneWidget);
      await tester.tap(find.byKey(const Key('secure-payment-continue')));
      await tester.pumpAndSettle();

      expect(find.text('בקרוב — הסליקה תהיה זמינה כאן'), findsOneWidget);
      expect(find.byKey(const Key('notch-notice')), findsOneWidget);
      expect(messenger.currentState, isNotNull);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
