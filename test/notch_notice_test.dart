import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/ui/widgets/notch_notice.dart';

void main() {
  final messenger = GlobalKey<ScaffoldMessengerState>();

  Future<void> mount(
    WidgetTester tester, {
    bool reduced = false,
    bool accessible = false,
    double scale = 1,
    Size size = const Size(402, 874),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        scaffoldMessengerKey: messenger,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            viewPadding: const EdgeInsets.only(top: 62),
            disableAnimations: reduced,
            accessibleNavigation: accessible,
            textScaler: TextScaler.linear(scale),
          ),
          child: NotchNoticeHost(key: notchNoticeKey, child: child!),
        ),
        home: const Scaffold(body: Center(child: Text('Home'))),
      ),
    );
  }

  testWidgets('queued notices survive navigation and dismiss in order', (
    tester,
  ) async {
    await mount(tester);
    notchNoticeKey.currentState!.show(
      const SnackBar(content: Text('Issued')),
      motion: NoticeMotion.document,
    );
    notchNoticeKey.currentState!.show(
      const SnackBar(content: Text('Sent')),
      motion: NoticeMotion.sent,
    );
    await tester.pumpAndSettle();
    expect(find.text('Issued'), findsOneWidget);
    Navigator.of(tester.element(find.text('Home'))).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Document')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Issued'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Sent'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notch-notice')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('accessible action persists, runs once and drains queue', (
    tester,
  ) async {
    await mount(tester, accessible: true);
    var calls = 0;
    notchNoticeKey.currentState!.show(
      SnackBar(
        content: const Text('Reminders'),
        action: SnackBarAction(label: 'Continue', onPressed: () => calls++),
      ),
      motion: NoticeMotion.reminder,
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('Continue'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.tap(find.text('Continue'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byKey(const Key('notch-notice')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'all motions fit a small screen with large text and reduced motion',
    (tester) async {
      await mount(tester, reduced: true, scale: 2, size: const Size(320, 640));
      for (final motion in NoticeMotion.values) {
        notchNoticeKey.currentState!.show(
          SnackBar(
            content: const Text(
              'The document was successfully sent to the customer',
            ),
            action: SnackBarAction(label: 'View', onPressed: () {}),
          ),
          motion: motion,
        );
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byKey(const Key('notch-notice'))).width,
          288,
        );
        expect(tester.takeException(), isNull, reason: motion.name);
        notchNoticeKey.currentState!.clear();
        await tester.pump();
      }
    },
  );

  testWidgets('backgrounding clears private content and pending notices', (
    tester,
  ) async {
    await mount(tester);
    notchNoticeKey.currentState!.show(const SnackBar(content: Text('Private')));
    notchNoticeKey.currentState!.show(const SnackBar(content: Text('Queued')));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('Private'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Queued'), findsNothing);
  });

  testWidgets(
    'iOS bridge displays action feedback and clears queued notices',
    (tester) async {
      await mount(tester);
      messenger.currentState!.showNotchNotice(
        const SnackBar(content: Text('Issued')),
        motion: NoticeMotion.document,
      );
      messenger.currentState!.showNotchNotice(
        const SnackBar(content: Text('Later')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notch-notice')), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      messenger.currentState!.clearNotchNotices();
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('Later'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('messenger bridge falls back on other platforms', (tester) async {
    await mount(tester);
    // The bridge uses the actual target platform, not ThemeData.platform.
    messenger.currentState!.showNotchNotice(
      const SnackBar(content: Text('Fallback')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byKey(const Key('notch-notice')), findsNothing);
    messenger.currentState!.clearNotchNotices();
    await tester.pumpAndSettle();
  });
}
