import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/app_shell.dart';

// AT-29: a business switch flips the לקוחות tab; the capsule animates its
// width while the Row already holds the new tab count. No overflow mid-way.
void main() {
  Widget nav(bool showPeople) => MaterialApp(
    home: Scaffold(
      bottomNavigationBar: ShellBottomNavigation(
        current: AppTab.home,
        showPeople: showPeople,
        showCreate: true,
        onTab: (_) {},
        onCreate: () {},
      ),
    ),
  );

  for (final size in const [Size(1170, 2532), Size(750, 1334)]) {
    testWidgets('3 → 4 → 3 tabs animate without overflow at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = size.width > 1000 ? 3 : 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(nav(false));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tab-people')), findsNothing);

      await tester.pumpWidget(nav(true));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 45));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tab-people')), findsOneWidget);

      await tester.pumpWidget(nav(false));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 45));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tab-people')), findsNothing);
    });
  }
}
