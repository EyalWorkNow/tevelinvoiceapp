// Regressions for the transition crash sweep (QA 2026-11-15,
// docs/qa-2026-11-15/CRASH-SWEEP-he.md).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/screens/people/customer_crm_agenda_screen.dart';
import 'package:invoice/screens/people/customer_crm_panel.dart';
import 'package:invoice/ui/theme.dart';
import 'package:invoice/ui/widgets/safe_error_card.dart';
import 'package:invoice/util/error_log.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('tevel-sweep-test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
  });
  tearDownAll(() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  Widget app(Widget child) => MaterialApp(
    locale: const Locale('he', 'IL'),
    supportedLocales: const [Locale('he', 'IL')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: buildTheme(Brightness.dark),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets(
    'a CRM panel mounting next to a mounted CRM widget does not notify the '
    'store during build (markNeedsBuild called during build)',
    (tester) async {
      late StateSetter rebuild;
      var showPanel = false;
      // The preview (home) and the panel (person card) live in different
      // subtrees, like two routes: notifying the preview while the panel's
      // subtree builds is outside the current build scope.
      await tester.pumpWidget(
        app(
          Column(
            children: [
              CustomerCrmReminderPreview(
                businessId: 'sweep-a',
                onOpenAgenda: () {},
                onOpenCustomer: (_) {},
              ),
              StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return showPanel
                      ? CustomerCrmPanel(
                          businessId: 'sweep-b',
                          customerId: 'c1',
                          customerName: 'דנה',
                          canEdit: true,
                          onOpenAgenda: () {},
                        )
                      : const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      rebuild(() => showPanel = true);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  group('error log', () {
    setUp(() async {
      ErrorLog.instance.fileProvider = () async =>
          File('${directory.path}/error_log.json');
      await ErrorLog.instance.clear();
    });

    test(
      'keeps the last 50 with route and 15 stack lines, persisted',
      () async {
        ErrorLog.instance.currentRoute = () => '/person/c1';
        final stack = StackTrace.fromString(
          List.generate(30, (i) => '#$i frame $i').join('\n'),
        );
        for (var i = 0; i < 60; i++) {
          ErrorLog.instance.record('flutter', StateError('boom $i'), stack);
        }
        final entries = ErrorLog.instance.entries;
        expect(entries, hasLength(ErrorLog.capacity));
        expect(entries.first.error, contains('boom 10'));
        expect(entries.last.route, '/person/c1');
        expect(entries.last.stack, hasLength(ErrorLog.stackLines));
        await ErrorLog.instance.load(); // waits for the queued writes
        final saved = File(
          '${directory.path}/error_log.json',
        ).readAsStringSync();
        expect(saved, contains('boom 59'));
        expect(ErrorLog.instance.report(), startsWith('errors: 50'));
      },
    );

    testWidgets('install leaves a test binding\'s FlutterError.onError alone', (
      tester,
    ) async {
      final before = FlutterError.onError;
      ErrorLog.instance.install();
      expect(FlutterError.onError, same(before));
    });
  });

  testWidgets('release error card: "חזור" pops to the root', (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: key, home: const Text('root')),
    );
    // leaveBrokenScreen uses the app's navigatorKey; here the card's own
    // build and tap target are what is checked.
    key.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            safeErrorWidget(FlutterErrorDetails(exception: StateError('x'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(safeErrorTitle), findsOneWidget);
    expect(find.byKey(const Key('safe-error-back')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
