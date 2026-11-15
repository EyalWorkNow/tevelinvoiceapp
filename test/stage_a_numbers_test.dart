// Stage A (QA 2026-11-16) — numbers you can trust (A3), the VAT draft (A4),
// compliance alerts and numbering (A8).

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/api/inbox_api.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/api/reports_api.dart';
import 'package:invoice/api/settings_api.dart';
import 'package:invoice/screens/business/sheets/editor_configs.dart';
import 'package:invoice/screens/business/sheets/editor_fields.dart';
import 'package:invoice/screens/home/inbox_cards.dart';
import 'package:invoice/screens/reports/report_view.dart';
import 'package:invoice/screens/reports/reports_screen.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/theme.dart';
import 'package:invoice/util/labels/inbox_he.dart';

import 'business/e_harness.dart';
import 'fakes/fake_api.dart';

Caps capsOf(Preset p) => Caps.fromMe(Me.fromJson(meJson(p)));

Map<String, dynamic> lateDoc(String id, String due, {bool? overdue = true}) => {
  ...docJson(id, open: 10000, number: id, issueDate: '2026-09-01'),
  'dueDate': due,
  'overdue': ?overdue,
};

void main() {
  late FakeBackend backend;

  setUp(() async {
    backend = await eSetUp();
  });

  group('A3: the lists use the server definition', () {
    test(
      'a card opens GET /documents?inbox=KIND; total = the card count',
      () async {
        await signInAs(backend, Preset.owner);
        backend.on('GET', '/documents', (r) {
          expect(r.query['inbox'], 'UNFINISHED');
          return FakeResponse(200, {
            'total': 92,
            'offset': int.parse(r.query['offset'] ?? '0'),
            'documents': [docJson('d1', status: 'DRAFT')],
          });
        });
        final page = await fetchInboxList(InboxKind.unfinished, offset: 50);
        expect(page.total, 92);
        expect(backend.last('GET', '/documents')!.query['offset'], '50');
      },
    );

    test(
      'overdue = ?overdue=1 rows, the row flag wins, oldest due first',
      () async {
        await signInAs(backend, Preset.owner);
        backend.on('GET', '/documents', (r) {
          expect(r.query['overdue'], '1');
          return FakeResponse(200, {
            'total': 3,
            'documents': [
              lateDoc('b', '2026-10-20'),
              lateDoc('a', '2026-10-01'),
              // The server says not overdue: the local rule does not override it.
              lateDoc('c', '2026-09-01', overdue: false),
            ],
          });
        });
        final page = await fetchOverdue(now: DateTime(2026, 11, 16));
        expect([for (final d in page.documents) d.id], ['a', 'b']);
        expect(page.total, 3);
      },
    );

    test('one reminder run sends at most reminderBatchMax', () async {
      await signInAs(backend, Preset.owner);
      backend
        ..json('GET', '/documents', {
          'total': 60,
          'documents': [
            for (var i = 0; i < 60; i++)
              lateDoc(
                'd$i',
                '2026-10-${(i % 28 + 1).toString().padLeft(2, '0')}',
              ),
          ],
        })
        ..json('GET', '/customers', {'customers': []});
      final r = await sendReminders(now: DateTime(2026, 11, 16));
      expect(r.whatsapp, hasLength(reminderBatchMax));
    });

    testWidgets('the preview counts every overdue invoice and caps the batch', (
      tester,
    ) async {
      await tester.runAsync(() => signInAs(backend, Preset.owner));
      final docs = [
        for (var i = 0; i < 60; i++)
          DocumentSummary.fromJson(lateDoc('d$i', '2026-10-01')),
      ];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('he', 'IL'),
          supportedLocales: const [Locale('he', 'IL')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: buildTheme(Brightness.light),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showReminderPreview(context, docs, total: 75),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(InboxHe.remindersCount(75)), findsOneWidget);
      expect(find.byKey(const Key('reminders-capped')), findsOneWidget);
      expect(
        find.text(InboxHe.remindersConfirm(reminderBatchMax)),
        findsOneWidget,
      );
    });
  });

  group('A8: compliance cards', () {
    test(
      'the accountant-rep sees TAX_INVOICE_DUE + PAYMENT_WITHOUT_RECEIPT',
      () {
        final rep = capsOf(Preset.accountantRep);
        const tax = InboxItem(kind: InboxKind.taxInvoiceDue);
        const pay = InboxItem(kind: InboxKind.paymentWithoutReceipt, count: 4);
        expect(cardAllowed(tax, rep), isTrue);
        expect(cardAllowed(pay, rep), isTrue);
        final employee = capsOf(Preset.employee);
        expect(cardAllowed(tax, employee), isFalse);
        expect(cardAllowed(pay, employee), isFalse);
        expect(cardAllowed(pay, capsOf(Preset.owner)), isTrue);
        expect(inboxTitle(pay), InboxHe.paymentWithoutReceipt(4));
      },
    );

    test('BE-05 card: paymentIds round-trip through the cache', () {
      final c = InboxItem.fromJson({
        'kind': 'PAYMENT_WITHOUT_RECEIPT',
        'count': 2,
        'amountMinor': '3600',
        'documentIds': <String>[],
        'paymentIds': ['p1', 'p2'],
        'action': 'OPEN_REPORT',
      });
      expect(c.kind, InboxKind.paymentWithoutReceipt);
      expect(InboxItem.fromJson(c.toJson()).paymentIds, ['p1', 'p2']);
    });

    test('the payments ledger marks a payment without a receipt', () async {
      await signInAs(backend, Preset.owner);
      backend.json('GET', '/payments', {
        'total': 1,
        'payments': [
          {
            'id': 'p1',
            'method': 'CASH',
            'amountMinor': '1800',
            'paymentDate': '2026-11-10',
            'receiptDocumentNumber': null,
          },
        ],
      });
      final r = await fetchPaymentsLedger(periodFor(PeriodKey.current));
      expect(r.rows.single['receipt'], noReceiptLabel);
    });

    test('the continuity check is a report row for owner and accountant', () {
      expect(
        reportKinds(capsOf(Preset.owner), exempt: false),
        contains('continuity'),
      );
      expect(
        reportKinds(capsOf(Preset.accountantRep), exempt: false),
        contains('continuity'),
      );
    });
  });

  group('A8: numbering page', () {
    Map<String, dynamic> series({
      String next = '1175',
      String? last = '1174',
      bool editable = false,
      String missing = '0',
    }) => {
      'sequences': [
        {
          'numbering_scope_key': 'default',
          'numbering_policy_version': 'v1',
          'next_number': next,
          'last_number': last,
          'issued_count': 74,
          'editable': editable,
          'missing_numbers': missing,
        },
      ],
    };

    test('a used series: shows last + next, no save button', () async {
      await signInAs(backend, Preset.owner);
      backend.json('GET', '/sequences', series(missing: '2'));
      final cfg = await numberingEditor();
      expect(cfg.onSave, isNull);
      final info = cfg.fields.first.label;
      expect(info, contains('1174'));
      expect(info, contains('1175'));
      expect(info, contains('חסרים 2'));
      expect(cfg.fields.any((f) => f.label == numberingLocked), isTrue);
    });

    test('"שמור" that changed nothing is an error, not "נשמר"', () async {
      await signInAs(backend, Preset.owner);
      var reads = 0;
      backend.on('GET', '/sequences', (_) {
        reads++;
        // Editable when the page opened; used by the time "שמור" runs.
        return FakeResponse(
          200,
          reads == 1 ? series(next: '1', last: null, editable: true) : series(),
        );
      });
      final cfg = await numberingEditor();
      expect(cfg.fields.firstWhere((f) => f.key == 'next').initial, '1');
      await expectLater(
        cfg.onSave!(EditorValues({'next': '500'})),
        throwsA(
          isA<ApiException>().having(
            (e) => e.messageHe,
            'messageHe',
            numberingNotSaved,
          ),
        ),
      );
      expect(backend.calls('PUT', '/sequences/:scopeKey/start'), isEmpty);
    });

    test('an untouched series is set and reported', () async {
      await signInAs(backend, Preset.owner);
      backend
        ..json(
          'GET',
          '/sequences',
          series(next: '1', last: null, editable: true),
        )
        ..json('PUT', '/sequences/:scopeKey/start', {
          'scopeKey': 'default',
          'nextNumber': 500,
        });
      expect(await setStartingNumber(500), 1);
      expect(backend.last('PUT', '/sequences/:scopeKey/start')!.body, {
        'nextNumber': 500,
      });
    });

    test('NumberingSeries reads an older server (no editable flag)', () {
      final s = NumberingSeries.fromJson({
        'numbering_scope_key': 'default',
        'next_number': '1',
      });
      expect(s.editable, isTrue);
      expect(s.lastNumber, isNull);
      expect(numberingSeriesLine(s), contains('עוד לא הופק מסמך'));
    });
  });

  group('A4: the VAT report is a draft with warning rows', () {
    test('ReportData reads draft / warnings / notes', () {
      final d = ReportData.fromJson({
        'kpis': [],
        'columns': [],
        'rows': [],
        'draft': true,
        'warnings': ['חשבונית ספק אחת מעל סף ההקצאה בלי מספר הקצאה'],
        'notes': ['טיוטה'],
      });
      expect(d.draft, isTrue);
      expect(d.warnings, hasLength(1));
      expect(d.notes, ['טיוטה']);
    });

    testWidgets('R2 shows the draft banner and each warning', (tester) async {
      backend.json('GET', '/reports/:kind', {
        ...reportJson(),
        'draft': true,
        'warnings': ['אזהרה ראשונה', 'אזהרה שנייה'],
      });
      await pumpAs(
        tester,
        backend,
        Preset.owner,
        const ReportView(kind: 'vat', period: PeriodKey.current),
      );
      expect(find.byKey(const Key('report-draft')), findsOneWidget);
      expect(find.text(reportDraftTitle), findsOneWidget);
      expect(find.byKey(const Key('report-warning')), findsNWidgets(2));
    });
  });
}
