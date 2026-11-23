// Late navigation (owner sweep 2026-11-16): a request that ends after the
// user left a screen — or while its back transition still runs — must not
// open a share sheet / WhatsApp, push or pop a route, or start an upload.
// Each case: start the action, leave, then let the request finish.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:invoice/api/debts_api.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/api/reports_api.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/debts/debt_entry_sheet.dart';
import 'package:invoice/screens/debts/debts_screen.dart';
import 'package:invoice/screens/document/sheets/s6_share.dart'
    show pdfSharer, textSharer;
import 'package:invoice/screens/expense/expense_capture_screen.dart';
import 'package:invoice/screens/people/person_screen.dart';
import 'package:invoice/screens/reports/daily_summary_view.dart';
import 'package:invoice/screens/reports/report_view.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/widgets/more_menu.dart';
import 'package:invoice/util/labels/people_he.dart';

import 'business/e_harness.dart';
import 'debts_screen_test.dart' show debtsJson;
import 'fakes/fake_api.dart';

/// A gallery whose answer arrives when the test says so.
class _SlowPicker extends ImagePicker {
  final picked = Completer<XFile?>();

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) => picked.future;
}

/// A root page that says 'open' and pushes [screen].
Widget _over(Widget screen) => Builder(
  builder: (context) => Scaffold(
    body: TextButton(
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => screen)),
      child: const Text('open'),
    ),
  ),
);

void main() {
  late List<String> shared;
  late FakeLauncher launcher;
  final oldPdf = pdfSharer;
  final oldText = textSharer;
  final oldFile = fileSharer;

  setUp(() {
    shared = [];
    pdfSharer = (bytes, name, {text}) async => shared.add('pdf:$name');
    textSharer = (text) async => shared.add('text');
    fileSharer = (file, {subject, text}) async =>
        shared.add('file:${file.name}');
    launcher = FakeLauncher()..install();
  });
  tearDown(() {
    pdfSharer = oldPdf;
    textSharer = oldText;
    fileSharer = oldFile;
    FakeLauncher.uninstall();
  });

  /// Leaves the top screen with a system back, then lets [release] finish.
  Future<void> leaveThen(WidgetTester tester, void Function() release) async {
    navigatorKey.currentState!.pop();
    release();
    await settle(tester);
  }

  testWidgets(
    'PDF picker returning during back transition never starts an expense upload',
    (tester) async {
      late FakeBackend backend;
      await tester.runAsync(() async {
        backend = await eSetUp();
        installIssueFakes(backend);
        await signInAs(backend, Preset.owner);
      });
      final picked = Completer<Uint8List?>();
      phone(tester);
      await tester.pumpWidget(
        eApp(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ExpenseCaptureScreen(
                      autoOpenCamera: false,
                      pickPdf: () => picked.future,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.tap(find.text(ExpenseHe.pickPdf));
      await tester.pump();
      navigatorKey.currentState!.pop();
      picked.complete(Uint8List.fromList('%PDF-1.4 test'.codeUnits));
      await settle(tester);
      expect(find.text('open'), findsOneWidget);
      expect(
        backend.requests.where((request) => request.method != 'GET'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'gallery photo returning during back transition never starts an upload',
    (tester) async {
      late FakeBackend backend;
      await tester.runAsync(() async {
        backend = await eSetUp();
        installIssueFakes(backend);
        await signInAs(backend, Preset.owner);
      });
      final picker = _SlowPicker();
      phone(tester);
      await tester.pumpWidget(
        eApp(
          _over(ExpenseCaptureScreen(autoOpenCamera: false, picker: picker)),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.tap(find.text(ExpenseHe.fromGallery));
      await tester.pump();
      await leaveThen(
        tester,
        () => picker.picked.complete(
          XFile.fromData(Uint8List.fromList([0xFF, 0xD8, 0xFF]), name: 'r.jpg'),
        ),
      );
      expect(find.text('open'), findsOneWidget);
      expect(backend.requests.where((r) => r.method != 'GET'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('single report: leaving while the PDF loads opens no share', (
    tester,
  ) async {
    final backend = (await tester.runAsync(eSetUp))!;
    final pdf = Completer<FakeResponse>();
    backend.on(
      'GET',
      '/reports/:kind',
      (r) => r.query['format'] == 'pdf'
          ? pdf.future
          : FakeResponse(200, reportJson()),
    );
    await pumpAs(
      tester,
      backend,
      Preset.owner,
      _over(ReportView(kind: 'income', period: PeriodKey.current)),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('report-share')));
    await tester.pump();
    await leaveThen(
      tester,
      () => pdf.complete(const FakeResponse(200, <int>[37, 80, 68, 70])),
    );
    expect(find.text('open'), findsOneWidget);
    expect(shared, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('customer statement (כרטסת): leaving while the PDF loads '
      'opens no share', (tester) async {
    final backend = (await tester.runAsync(eSetUp))!;
    installPeopleFakes(
      backend,
      customers: [customerJson('c1', 'דנה', email: 'd@x.co')],
      be17: true,
    );
    final pdf = Completer<FakeResponse>();
    backend.on('GET', '/customers/:id/statement.pdf', (_) => pdf.future);
    await pumpAs(
      tester,
      backend,
      Preset.accountantRep, // no send: the PDF goes to the share sheet
      _over(const PersonScreen(id: 'c1')),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(MoreMenu),
        matching: find.byType(IconButton),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('שליחת כרטסת'));
    await tester.pump();
    await leaveThen(
      tester,
      () => pdf.complete(const FakeResponse(200, <int>[37, 80, 68, 70])),
    );
    expect(find.text('open'), findsOneWidget);
    expect(shared, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('daily summary: leaving while the PDF loads opens no share', (
    tester,
  ) async {
    final backend = (await tester.runAsync(eSetUp))!;
    final pdf = Completer<FakeResponse>();
    backend.on(
      'GET',
      '/reports/:kind',
      (r) => r.query['format'] == 'pdf'
          ? pdf.future
          : const FakeResponse(200, {
              'totalMinor': '37000',
              'count': 1,
              'byMethod': [
                {'method': 'CASH', 'count': 1, 'totalMinor': '37000'},
              ],
              'receipts': <Object>[],
            }),
    );
    await pumpAs(
      tester,
      backend,
      Preset.owner,
      _over(const DailySummaryView()),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('daily-pdf')));
    await tester.pump();
    await leaveThen(
      tester,
      () => pdf.complete(const FakeResponse(200, <int>[37, 80, 68, 70])),
    );
    expect(find.text('open'), findsOneWidget);
    expect(shared, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('debts reminder: leaving while the link is made opens no '
      'WhatsApp and does not crash', (tester) async {
    final backend = (await tester.runAsync(eSetUp))!;
    loadWhoOwesMe = fetchWhoOwesMe;
    final link = Completer<FakeResponse>();
    backend
      ..json('GET', '/debts', debtsJson())
      ..on('POST', '/documents/:id/share-link', (_) => link.future);
    await pumpAs(
      tester,
      backend,
      Preset.owner,
      _over(DebtsScreen(now: () => DateTime(2026, 11, 16, 12))),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('debtor-remind-c-yossi')));
    await tester.pump();
    await leaveThen(
      tester,
      () => link.complete(
        const FakeResponse(200, {
          'url': 'https://invoice.test/d/t',
          'token': 't',
        }),
      ),
    );
    expect(find.text('open'), findsOneWidget);
    expect(launcher.opened, isEmpty);
    expect(shared, isEmpty);
    expect(backend.last('POST', '/reminders/log'), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('debt-entry sheet closed while saving never pops the screen '
      'under it', (tester) async {
    final backend = (await tester.runAsync(eSetUp))!;
    final save = Completer<FakeResponse>();
    backend.on('POST', '/debt-entries', (_) => save.future);
    await pumpAs(
      tester,
      backend,
      Preset.owner,
      _over(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDebtEntrySheet(
                context,
                customer: const Customer(id: 'c1', name: 'יוסי'),
              ),
              child: const Text('debts'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    await tester.tap(find.text('debts'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('debt-entry-amount')), '600');
    await tester.enterText(find.byKey(const Key('debt-entry-note')), 'שיעור');
    await tester.tap(find.byKey(const Key('debt-entry-save')));
    await tester.pump();
    await leaveThen(
      tester,
      () => save.complete(
        const FakeResponse(201, {
          'debtEntry': {
            'id': 'e9',
            'customerId': 'c1',
            'amountMinor': '60000',
            'note': 'שיעור',
            'debtDate': '2026-11-16',
            'status': 'OPEN',
          },
          'reused': false,
        }),
      ),
    );
    expect(find.text('debts'), findsOneWidget);
    expect(find.byKey(const Key('debt-entry-sheet')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
