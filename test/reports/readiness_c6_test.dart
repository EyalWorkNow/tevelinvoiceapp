import 'dart:async';

// C6 · "מוכן לרו״ח" + accountant board + "בקש תיקון/זיכוי" (QA 2026-11-16).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/inbox_api.dart' show cardAllowed;
import 'package:invoice/api/models/models.dart';
import 'package:invoice/api/readiness_api.dart';
import 'package:invoice/api/reports_api.dart';
import 'package:invoice/router.dart' show navigatorKey;
import 'package:invoice/screens/business/sheets/readiness_board.dart';
import 'package:invoice/screens/business/sheets/s14_switch.dart';
import 'package:invoice/screens/document/sheets/s8_cancel.dart';
import 'package:invoice/screens/home/inbox_cards.dart';
import 'package:invoice/screens/reports/correction_request_sheet.dart';
import 'package:invoice/screens/reports/report_view.dart';
import 'package:invoice/screens/reports/reports_screen.dart';
import 'package:invoice/state/business_context.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/util/labels/labels.dart';

import '../business/e_harness.dart';
import '../fakes/fake_api.dart';

Map<String, dynamic> item(
  String key,
  String status, {
  int count = 0,
  int weight = 15,
  String screen = 'REPORT',
  String? ref,
  List<String> ids = const [],
}) => {
  'key': key,
  'status': status,
  'count': count,
  'weight': weight,
  'titleHe': 'כותרת $key',
  'hintHe': status == 'ok' ? '' : 'רמז $key',
  'amountMinor': null,
  'ids': ids,
  'target': {'screen': screen, 'ref': ref},
};

Map<String, dynamic> readinessJson({
  int score = 62,
  bool? ready,
  List<Map<String, dynamic>>? items,
}) => {
  'from': '2026-11-01',
  'to': '2026-12-31',
  'businessType': 'OSEK_MURSHE',
  'score': score,
  'ready': ready ?? score >= 90,
  'readyThreshold': 90,
  'openItems': 2,
  'items':
      items ??
      [
        item(
          'NUMBERING',
          'fail',
          count: 1,
          weight: 20,
          screen: 'REPORT',
          ref: 'continuity',
        ),
        item('VAT_WARNINGS', 'warn', count: 1, weight: 10, ref: 'vat'),
        item('EXPENSES', 'ok', screen: 'EXPENSES'),
      ],
};

/// eSetUp registers GET /reports/:kind → 404 first; the fake matches in
/// registration order, so readiness goes in front of it.
void serveReadiness(FakeBackend b, FakeHandler handler) {
  b
    ..off('GET', '/reports/:kind')
    ..on('GET', '/reports/readiness', handler)
    ..error('GET', '/reports/:kind', 404, 'NOT_FOUND');
}

void main() {
  late FakeBackend backend;
  late List<(ExportFile, String?, String?)> shared;

  setUp(() async {
    backend = await eSetUp();
    ReadinessBoard.resetCache();
    shared = [];
    fileSharer = (file, {subject, text}) async =>
        shared.add((file, subject, text));
  });

  group('model', () {
    test('parses the server body; open items fail-first, heavier first', () {
      final r = Readiness.tryParse(readinessJson())!;
      expect(r.score, 62);
      expect(r.ready, isFalse);
      expect(r.threshold, 90);
      expect(r.open.map((i) => i.key), ['NUMBERING', 'VAT_WARNINGS']);
      expect(r.passed.map((i) => i.key), ['EXPENSES']);
      expect(r.open.first.screen, ReadinessScreen.report);
      expect(r.open.first.ref, 'continuity');
    });

    test('another shape (an old server’s /reports/:kind) → null', () {
      expect(Readiness.tryParse({'kind': 'income', 'kpis': []}), isNull);
    });

    test('badge words follow the threshold', () {
      expect(ReadinessHe.badge(95, 90), ReadinessHe.ready);
      expect(ReadinessHe.badge(75, 90), ReadinessHe.almost);
      expect(ReadinessHe.badge(40, 90), ReadinessHe.notReady);
    });
  });

  group('R: the "מוכן לרו״ח" card', () {
    testWidgets(
      'score, badge and the open items; passed ones behind a toggle',
      (tester) async {
        serveReadiness(backend, (r) {
          expect(r.query['from'], periodFor(PeriodKey.current).fromIso);
          expect(r.query['to'], periodFor(PeriodKey.current).toIso);
          return FakeResponse(200, readinessJson());
        });
        await pumpAs(tester, backend, Preset.owner, const ReportsScreen());
        expect(find.byKey(const Key('readiness-card')), findsOneWidget);
        expect(find.text(ReadinessHe.title), findsOneWidget);
        expect(find.text('62'), findsOneWidget);
        expect(find.text(ReadinessHe.notReady), findsOneWidget);
        expect(find.text(ReadinessHe.missing(2)), findsOneWidget);
        expect(
          find.byKey(const Key('readiness-item-NUMBERING')),
          findsOneWidget,
        );
        expect(find.text('רמז NUMBERING'), findsOneWidget);
        expect(find.byKey(const Key('readiness-item-EXPENSES')), findsNothing);
        await tester.tap(find.byKey(const Key('readiness-toggle-passed')));
        await settle(tester);
        expect(
          find.byKey(const Key('readiness-item-EXPENSES')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'an item opens the screen that fixes it (numbering → continuity)',
      (tester) async {
        serveReadiness(backend, (_) => FakeResponse(200, readinessJson()));
        await pumpAs(tester, backend, Preset.owner, const ReportsScreen());
        await tester.tap(find.byKey(const Key('readiness-item-NUMBERING')));
        await settle(tester);
        final view = tester.widget<ReportView>(find.byType(ReportView));
        expect(view.kind, 'continuity');
      },
    );

    testWidgets('no endpoint (404) → no card, R as before', (tester) async {
      await pumpAs(tester, backend, Preset.owner, const ReportsScreen());
      expect(find.byKey(const Key('readiness-card')), findsNothing);
      expect(find.text(ReportsHe.sendToAccountant), findsOneWidget);
    });

    testWidgets(
      'below the threshold "שלח לרו״ח" needs an explicit confirm; "אטפל קודם" sends nothing',
      (tester) async {
        serveReadiness(backend, (_) => FakeResponse(200, readinessJson()));
        await pumpAs(tester, backend, Preset.owner, const ReportsScreen());
        await tester.tap(find.byKey(const Key('send-to-accountant')));
        await settle(tester);
        expect(find.text(ReadinessHe.sendAnywayTitle), findsOneWidget);
        await tester.tap(find.byKey(const Key('readiness-fix-first')));
        await settle(tester);
        expect(backend.calls('POST', '/exports/:kind'), isEmpty);
        expect(shared, isEmpty);

        await tester.tap(find.byKey(const Key('send-to-accountant')));
        await settle(tester);
        await tester.tap(find.byKey(const Key('readiness-send-anyway')));
        await settle(tester);
        expect(backend.calls('POST', '/exports/:kind'), hasLength(1));
        expect(shared, hasLength(1));
      },
    );

    testWidgets('ready → "שלח לרו״ח" goes straight to the export', (
      tester,
    ) async {
      serveReadiness(
        backend,
        (_) => FakeResponse(
          200,
          readinessJson(
            score: 96,
            items: [item('NUMBERING', 'ok', weight: 20)],
          ),
        ),
      );
      await pumpAs(tester, backend, Preset.owner, const ReportsScreen());
      expect(find.text(ReadinessHe.allGood), findsOneWidget);
      await tester.tap(find.byKey(const Key('send-to-accountant')));
      await settle(tester);
      expect(find.text(ReadinessHe.sendAnywayTitle), findsNothing);
      expect(backend.calls('POST', '/exports/:kind'), hasLength(1));
    });
  });

  group('S14: the accountant board', () {
    Map<String, int> scores = {};
    void serveScores(FakeBackend b) => serveReadiness(b, (r) {
      final id = r.headers['X-Business-Id'] ?? r.headers['x-business-id'];
      expect(r.query['period'], 'current');
      return FakeResponse(200, readinessJson(score: scores[id] ?? 100));
    });

    testWidgets('scores per business, least ready first', (tester) async {
      scores = {'b1': 95, 'b2': 40, 'b3': 70};
      serveScores(backend);
      await pumpAs(
        tester,
        backend,
        Preset.accountantRep,
        const Scaffold(body: SwitchBusinessSheet()),
        businesses: 3,
      );
      expect(find.byKey(const Key('s14-board')), findsOneWidget);
      for (final id in ['b1', 'b2', 'b3']) {
        expect(find.byKey(Key('s14-score-$id')), findsOneWidget);
      }
      final y = {
        for (final id in ['b1', 'b2', 'b3'])
          id: tester.getTopLeft(find.byKey(Key('s14-$id'))).dy,
      };
      expect(y['b2']! < y['b3']!, isTrue);
      expect(y['b3']! < y['b1']!, isTrue);
      expect(backend.calls('GET', '/reports/readiness'), hasLength(3));
    });

    testWidgets(
      'paginated: scores load only for the shown page; "טען עוד" adds the next',
      (tester) async {
        scores = {};
        serveScores(backend);
        backend.off('GET', '/mobile/businesses');
        await pumpAs(
          tester,
          backend,
          Preset.accountantRep,
          const Scaffold(body: SwitchBusinessSheet()),
          businesses: 25,
        );
        expect(
          backend.calls('GET', '/reports/readiness'),
          hasLength(ReadinessBoard.pageSize),
        );
        final more = find.byKey(const Key('s14-board-more'));
        await tester.dragUntilVisible(
          more,
          find.byType(ListView),
          const Offset(0, -300),
        );
        await settle(tester);
        await tester.tap(more);
        await settle(tester);
        expect(backend.calls('GET', '/reports/readiness'), hasLength(25));
        expect(find.byKey(const Key('s14-board-more')), findsNothing);
      },
    );

    testWidgets('an owner of several businesses sees no board', (tester) async {
      serveScores(backend);
      await pumpAs(
        tester,
        backend,
        Preset.owner,
        const Scaffold(body: SwitchBusinessSheet()),
        businesses: 3,
      );
      expect(find.byKey(const Key('s14-board')), findsNothing);
      expect(backend.calls('GET', '/reports/readiness'), isEmpty);
    });
  });

  group('"בקש תיקון/זיכוי"', () {
    test(
      'only the accountant presets, on an issued, not cancelled document',
      () async {
        await signInAs(backend, Preset.accountantRep);
        final doc = DocumentDetail.fromJson(docDetailJson());
        expect(canRequestCorrection(doc), isTrue);
        expect(
          canRequestCorrection(
            DocumentDetail.fromJson(docDetailJson(status: 'DRAFT')),
          ),
          isFalse,
        );
        expect(
          canRequestCorrection(
            DocumentDetail.fromJson(docDetailJson(voidedAt: '2026-11-01')),
          ),
          isFalse,
        );
        expect(
          canRequestCorrection(
            DocumentDetail.fromJson(docDetailJson(type: 'CREDIT_DOCUMENT')),
          ),
          isFalse,
        );
        await signInAs(backend, Preset.owner);
        expect(canRequestCorrection(doc), isFalse);
        // Walkthrough #8: the full accountant too; never a plain viewer.
        await signInAs(backend, Preset.accountantFull);
        expect(canRequestCorrection(doc), isTrue);
        await signInAs(backend, Preset.viewer);
        expect(canRequestCorrection(doc), isFalse);
      },
    );

    testWidgets(
      'walkthrough #8: a refusal says "no permission", not "permissions updated"',
      (tester) async {
        backend.error(
          'POST',
          '/documents/:id/correction-requests',
          403,
          'DOCUMENT_ACTION_FORBIDDEN',
        );
        await pumpAs(
          tester,
          backend,
          Preset.accountantRep,
          const Scaffold(body: SizedBox()),
        );
        unawaited(
          showCorrectionRequestSheet(
            navigatorKey.currentContext!,
            DocumentDetail.fromJson(docDetailJson()),
          ),
        );
        await settle(tester);
        await tester.enterText(
          find.byKey(const Key('correction-reason')),
          'סכום שגוי',
        );
        await tester.tap(find.byKey(const Key('correction-send')));
        await settle(tester);
        expect(
          tester.widget<Text>(find.byKey(const Key('correction-error'))).data,
          'אין לך הרשאה לפעולה הזו',
        );
      },
    );

    testWidgets('the accountant sends a reason and an amount', (tester) async {
      backend.json('POST', '/documents/:id/correction-requests', {
        'id': 'cr-1',
        'status': 'OPEN',
      }, status: 201);
      await pumpAs(
        tester,
        backend,
        Preset.accountantRep,
        const Scaffold(body: SizedBox()),
      );
      final doc = DocumentDetail.fromJson(docDetailJson());
      final done = showCorrectionRequestSheet(
        navigatorKey.currentContext!,
        doc,
      );
      await settle(tester);
      await tester.tap(find.byKey(const Key('correction-send')));
      await settle(tester);
      expect(find.text(ReadinessHe.reasonRequired), findsOneWidget);
      expect(
        backend.calls('POST', '/documents/:id/correction-requests'),
        isEmpty,
      );
      await tester.enterText(
        find.byKey(const Key('correction-reason')),
        'המחיר צריך להיות 400 ₪',
      );
      await tester.enterText(find.byKey(const Key('correction-amount')), '472');
      await tester.tap(find.byKey(const Key('correction-send')));
      await settle(tester);
      expect(await done, isTrue);
      final call = backend.last('POST', '/documents/:id/correction-requests')!;
      expect(call.params['id'], 'doc-1');
      expect(call.body, {
        'reason': 'המחיר צריך להיות 400 ₪',
        'amountMinor': '47200',
      });
    });

    test(
      'the owner’s card: parsed from BE-05, shown to who may credit',
      () async {
        final c = InboxItem.fromJson({
          'kind': 'CORRECTION_REQUESTED',
          'count': 1,
          'amountMinor': '11800',
          'documentIds': ['doc-1'],
          'action': 'ISSUE_CREDIT',
          'detail': {
            'documentId': 'doc-1',
            'customerName': 'דנה',
            'requestId': 'cr-1',
            'reason': 'סכום שגוי',
            'requestKind': 'CREDIT',
            'requestedAmountMinor': '11800',
          },
        });
        expect(c.kind, InboxKind.correctionRequested);
        expect(c.requestId, 'cr-1');
        expect(c.reason, 'סכום שגוי');
        expect(c.requestedAmountMinor, BigInt.from(11800));
        expect(inboxTitle(c), contains('סכום שגוי'));
        expect(InboxItem.fromJson(c.toJson()).requestId, 'cr-1');
        await signInAs(backend, Preset.owner);
        expect(cardAllowed(c, businessContext.caps), isTrue);
        await signInAs(backend, Preset.accountantRep);
        expect(cardAllowed(c, businessContext.caps), isFalse);
      },
    );

    testWidgets(
      'S8 opens prefilled with the accountant’s amount; the request can be closed',
      (tester) async {
        installActionsFakes(backend);
        backend.json('POST', '/correction-requests/:id/dismiss', {
          'id': 'cr-1',
          'status': 'DISMISSED',
        });
        await pumpAs(
          tester,
          backend,
          Preset.owner,
          const Scaffold(body: SizedBox()),
        );
        final out = showCancelSheet(
          navigatorKey.currentContext!,
          documentId: 'doc-1',
          initialAmountMinor: BigInt.from(47200),
          requestReason: 'המחיר צריך להיות 400 ₪',
          correctionRequestId: 'cr-1',
        );
        await settle(tester);
        expect(find.byKey(const Key('s8-request-reason')), findsOneWidget);
        final amount = tester.widget<TextField>(
          find.byKey(const Key('s8-amount')),
        );
        expect(amount.controller!.text, '472');
        await tester.tap(find.byKey(const Key('s8-dismiss-request')));
        await settle(tester);
        expect((await out)?.dismissed, isTrue);
        expect(
          backend.calls('POST', '/correction-requests/:id/dismiss'),
          hasLength(1),
        );
      },
    );
  });
}
