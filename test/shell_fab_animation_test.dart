import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/app_shell.dart';

// Owner, TestFlight build 9: off Home the ＋ FAB slides out towards its edge,
// then the capsule grows into the freed space; back on Home the capsule
// shrinks first, then ＋ slides back in.
void main() {
  var creates = 0;
  setUp(() => creates = 0);

  Widget nav({
    required AppTab tab,
    bool showPeople = true,
    TextDirection direction = TextDirection.rtl,
    bool disableAnimations = false,
  }) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations),
      child: Directionality(textDirection: direction, child: child!),
    ),
    home: Scaffold(
      bottomNavigationBar: ShellBottomNavigation(
        current: tab,
        showPeople: showPeople,
        showCreate: tab == AppTab.home,
        onTab: (_) {},
        onCreate: () => creates++,
      ),
    ),
  );

  double opacity(WidgetTester t) => t
      .widget<Opacity>(
        find
            .descendant(
              of: find.byKey(const Key('shell-create-motion')),
              matching: find.byType(Opacity),
            )
            .first,
      )
      .opacity;
  double slide(WidgetTester t) => t
      .widget<FractionalTranslation>(
        find.byKey(const Key('shell-create-motion')),
      )
      .translation
      .dx;
  double capsule(WidgetTester t) =>
      t.getSize(find.byKey(const Key('shell-capsule'))).width;

  final hiddenFab = find.byKey(const Key('home-create-hidden')).hitTestable();
  final shownFab = find.byKey(const Key('tab-create')).hitTestable();

  void phone(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = size.width > 1000 ? 3 : 2;
    addTearDown(tester.view.reset);
  }

  for (final size in const [Size(1170, 2532), Size(750, 1334)]) {
    testWidgets('Home → other tab → Home, staggered, no overflow ($size)', (
      tester,
    ) async {
      phone(tester, size);
      await tester.pumpWidget(nav(tab: AppTab.home));
      await tester.pumpAndSettle();
      final compact = capsule(tester);
      final slotWidth = tester
          .getSize(find.byKey(const Key('shell-create-slot')))
          .width;
      expect(opacity(tester), 1);
      expect(slide(tester), 0);
      expect(shownFab, findsOneWidget);

      // ── Leave Home: ＋ out first, then the capsule grows.
      await tester.pumpWidget(nav(tab: AppTab.business));
      final frames = <(double, double, double)>[];
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        expect(tester.takeException(), isNull);
        expect(hiddenFab, findsNothing, reason: 'hidden ＋ is not tappable');
        if (find.byKey(const Key('tab-create')).evaluate().isNotEmpty) {
          expect(shownFab, findsNothing);
        }
        frames.add((opacity(tester), slide(tester), capsule(tester)));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // ＋ fades and slides towards the start edge (right in RTL).
      expect(frames.first.$1, lessThan(1));
      expect(frames.first.$2, greaterThan(0));
      for (var i = 1; i < frames.length; i++) {
        expect(frames[i].$1, lessThanOrEqualTo(frames[i - 1].$1));
        expect(frames[i].$2, greaterThanOrEqualTo(frames[i - 1].$2));
        expect(frames[i].$3, greaterThanOrEqualTo(frames[i - 1].$3));
      }
      // The capsule waits for ＋: while ＋ is still clearly visible it has not
      // grown, and it does grow once ＋ is gone.
      for (final f in frames.where((f) => f.$1 > .05)) {
        expect(f.$3, closeTo(compact, 1));
      }
      expect(frames.any((f) => f.$1 == 0 && f.$3 > compact + 1), isTrue);
      final expanded = capsule(tester);
      expect(expanded, greaterThan(compact + slotWidth * .9));
      expect(opacity(tester), 0);
      expect(find.byKey(const Key('tab-create')), findsNothing);
      expect(hiddenFab, findsNothing);
      expect(
        tester.getSize(find.byKey(const Key('shell-create-slot'))).width,
        0,
      );

      // ── Back Home: the capsule shrinks first, then ＋ slides in.
      await tester.pumpWidget(nav(tab: AppTab.home));
      final back = <(double, double)>[];
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        expect(tester.takeException(), isNull);
        back.add((opacity(tester), capsule(tester)));
      }
      await tester.pumpAndSettle();
      expect(back.first.$1, 0, reason: '＋ waits for the capsule');
      expect(back.first.$2, lessThan(expanded));
      for (final f in back.where((f) => f.$1 > .05)) {
        expect(f.$2, closeTo(compact, 1));
      }
      for (var i = 1; i < back.length; i++) {
        expect(back[i].$1, greaterThanOrEqualTo(back[i - 1].$1));
        expect(back[i].$2, lessThanOrEqualTo(back[i - 1].$2));
      }
      expect(capsule(tester), closeTo(compact, .01));
      expect(opacity(tester), 1);
      expect(slide(tester), 0);
      await tester.tap(shownFab);
      expect(creates, 1);
    });
  }

  testWidgets('LTR: ＋ slides out towards the left edge', (tester) async {
    phone(tester, const Size(1170, 2532));
    await tester.pumpWidget(
      nav(tab: AppTab.home, direction: TextDirection.ltr),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      nav(tab: AppTab.profile, direction: TextDirection.ltr),
    );
    await tester.pump(const Duration(milliseconds: 80));
    expect(slide(tester), lessThan(0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion snaps without animating', (tester) async {
    phone(tester, const Size(1170, 2532));
    await tester.pumpWidget(nav(tab: AppTab.home, disableAnimations: true));
    await tester.pumpAndSettle();
    final compact = capsule(tester);
    await tester.pumpWidget(nav(tab: AppTab.business, disableAnimations: true));
    await tester.pump();
    expect(opacity(tester), 0);
    expect(capsule(tester), greaterThan(compact));
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(nav(tab: AppTab.home, disableAnimations: true));
    await tester.pump();
    expect(opacity(tester), 1);
    expect(capsule(tester), closeTo(compact, .01));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('לקוחות comes and goes off Home (wide capsule): no overflow', (
    tester,
  ) async {
    phone(tester, const Size(750, 1334));
    await tester.pumpWidget(nav(tab: AppTab.profile, showPeople: false));
    await tester.pumpAndSettle();
    for (final people in [true, false, true]) {
      await tester.pumpWidget(nav(tab: AppTab.profile, showPeople: people));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
    }
    // Switching to Home and business at once (both animations together).
    await tester.pumpWidget(nav(tab: AppTab.home, showPeople: false));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tab-people')), findsNothing);
    expect(shownFab, findsOneWidget);
  });
}
