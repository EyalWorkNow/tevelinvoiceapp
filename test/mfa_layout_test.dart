import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/screens/auth/mfa_sheet.dart';

import 'business/e_harness.dart';

void main() {
  setUp(() async {
    final backend = await eSetUp();
    backend
      ..json('GET', '/auth/mfa/methods', {
        'totp': false,
        'email': {'enabled': true},
        'emailAvailable': true,
        'recoveryCodesRemaining': 0,
      })
      ..json('POST', '/auth/mfa/email/send', {
        'sentTo': 'te***@test.com',
        'resendAfterSeconds': 45,
      });
  });

  for (final width in [320.0, 402.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('MFA centered 3 by 2 circles at $width pt and $scale text', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width * 3, 844 * 3);
        tester.view.devicePixelRatio = 3;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          eApp(
            Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => unawaited(showMfaStep(context)),
                  child: const Text('open'),
                ),
              ),
            ),
            brightness: Brightness.dark,
          ),
        );
        await tester.tap(find.text('open'));
        await settle(tester);
        final positions = [
          for (var i = 0; i < 6; i++)
            tester.getCenter(find.byKey(ValueKey('mfa-digit-$i'))),
        ];
        expect(positions[0].dy, positions[1].dy);
        expect(positions[1].dy, positions[2].dy);
        expect(positions[3].dy, positions[4].dy);
        expect(positions[4].dy, positions[5].dy);
        expect(positions[3].dy, greaterThan(positions[0].dy));
        expect(positions[0].dx, positions[3].dx);
        expect(positions[0].dx, lessThan(positions[1].dx));
        if (tester.getSize(find.byType(MfaSheet)).height <= 700) {
          expect(tester.getCenter(find.byType(MfaSheet)).dy, closeTo(422, 1));
        }
        expect(
          tester.getCenter(find.byType(CodeBoxes)).dx,
          closeTo(width / 2, 1),
        );
        for (var i = 0; i < 6; i++) {
          final size = tester.getSize(find.byKey(ValueKey('mfa-digit-$i')));
          expect(size.width, size.height);
          expect(size.width, greaterThanOrEqualTo(80));
        }
        await tester.enterText(find.byType(TextField), '12345');
        await tester.pump();
        for (final digit in ['1', '2', '3', '4', '5']) {
          expect(find.text(digit), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        tester.view.viewInsets = const FakeViewPadding(bottom: 900);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(CodeBoxes));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
