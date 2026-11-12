// V2 additions of the issue sequence (§6.C API, §4.9, §8.2) and quotes_api
// (§8.2.4), against the squad-B fake in test/fakes/issue_fake.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/api/issue_api.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/api/quotes_api.dart';
import 'package:invoice/state/cache.dart';

import 'fakes/fake_api.dart';

PendingIssue issue({
  String type = 'TAX_INVOICE_RECEIPT',
  String customer = 'c3',
  String unit = '508475', // 5,084.75 + 18% = 6,000.00
  bool evaluate = true,
  bool requestAllocation = false,
  bool paid = true,
}) => PendingIssue(
  businessId: 'b1',
  body: {
    'documentType': type,
    'customerId': customer,
    'currency': 'ILS',
    'fiscalContext': 'default',
    'lines': [
      {
        'description': 'ייעוץ',
        'quantityMicros': '1000000',
        'unitPriceMinor': unit,
        'taxRateBasisPoints': 1800,
      },
    ],
  },
  form: const {},
  payment: paid ? const PaymentInput(method: 'BANK_TRANSFER') : null,
  totalMinor: BigInt.from(600000),
  needsApproval: false,
  evaluate: evaluate,
  requestAllocation: requestAllocation,
);

void main() {
  late FakeBackend backend;
  late IssueFake fake;
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('issue_flow_v2');
    AppCache.directoryProvider = () async => tmp;
    backend = FakeBackend()..install();
    fake = installIssueFakes(backend);
    ApiClient.instance
      ..deviceToken = 'inv_t'
      ..businessId = 'b1';
  });

  tearDown(() => AppCache.clearAll());

  test(
    'AT-17: evaluate NOT_REQUIRED → finalize WITHOUT requestAllocation',
    () async {
      final r = await runIssue(issue(customer: 'c2'));
      expect(r.outcome, IssueOutcome.issued);
      expect(
        backend.calls('POST', '/documents/:id/allocation/evaluate'),
        hasLength(1),
      );
      expect(backend.last('POST', '/documents/:id/finalize')!.body, {
        'scopeKey': 'default',
      });
      expect(
        backend.last('POST', '/documents/:id/payments')!.body['amountMinor'],
        fake.docs['d1']!['total_minor'],
        reason: 'the server total, never the local preview',
      );
    },
  );

  test(
    '"הלקוח ביקש מספר הקצאה" → requestAllocation:true (voluntary)',
    () async {
      await runIssue(issue(requestAllocation: true));
      expect(
        backend
            .last('POST', '/documents/:id/finalize')!
            .body['requestAllocation'],
        isTrue,
      );
    },
  );

  test(
    'AT-17b: REQUIRES_USER_INPUT → ask → PATCH customer → evaluate again → finalize',
    () async {
      fake.evaluateAnswers.add({
        'state': 'REQUIRES_USER_INPUT',
        'evaluation': {
          'requirement': 'REQUIRES_USER_INPUT',
          'reasonCode': 'CUSTOMER_VAT_STATUS_UNKNOWN',
        },
      });
      String? asked;
      final r = await runIssue(
        issue(),
        askVatStatus: (reason) async {
          asked = reason;
          return const VatStatusAnswer(authorizedDealer: true);
        },
      );
      expect(asked, 'CUSTOMER_VAT_STATUS_UNKNOWN');
      expect(backend.last('PATCH', '/customers/:id')!.body, {
        'vatDealerStatus': 'AUTHORIZED_DEALER',
      });
      expect(
        backend.calls('POST', '/documents/:id/allocation/evaluate'),
        hasLength(2),
      );
      expect(r.outcome, IssueOutcome.issued);
    },
  );

  test(
    'closing the dealer dialog stops before finalize; the draft stays saved',
    () async {
      fake.evaluateAnswers.add({
        'state': 'REQUIRES_USER_INPUT',
        'evaluation': {'reasonCode': 'CUSTOMER_VAT_NUMBER_MISSING'},
      });
      await expectLater(
        runIssue(issue(), askVatStatus: (_) async => null),
        throwsA(isA<IssueCancelled>()),
      );
      expect(backend.calls('POST', '/documents/:id/finalize'), isEmpty);
      expect((await loadPendingIssue())!.draftId, 'd1');
    },
  );

  test('AT-64: signing LOCKED → unlock callback → /sign → payment', () async {
    fake.artifactSigning = 'LOCKED';
    var asked = 0;
    final r = await runIssue(
      issue(evaluate: false),
      unlockSigning: () async {
        asked++;
        fake.signingUnlocked = true;
        return true;
      },
    );
    expect(asked, 1);
    expect(
      backend.calls('POST', '/documents/:id/sign'),
      hasLength(2),
      reason: 'locked try + signed',
    );
    expect(r.outcome, IssueOutcome.issued);
    expect(backend.calls('POST', '/payments'), hasLength(1));
  });

  test(
    'AT-64: Face ID cancelled → signingLocked (D state 6), resume signs + pays once',
    () async {
      fake.artifactSigning = 'LOCKED';
      final r = await runIssue(
        issue(evaluate: false),
        unlockSigning: () async => false,
      );
      expect(r.outcome, IssueOutcome.signingLocked);
      expect(r.document.status, 'ARTIFACT_PENDING');
      expect(backend.calls('POST', '/payments'), isEmpty);
      fake.signingUnlocked = true; // e.g. unlocked from D
      final done = await resumeIssueFor('d1');
      expect(done!.outcome, IssueOutcome.issued);
      expect(
        backend.calls('POST', '/documents/:id/artifact'),
        hasLength(1),
        reason: 'never a second original',
      );
      expect(backend.calls('POST', '/payments'), hasLength(1));
    },
  );

  test(
    '400 receipt only: POST /payments → POST /receipts (keys) → artifact; no POST /documents',
    () async {
      final p = PendingIssue(
        businessId: 'b1',
        body: {'documentType': 'RECEIPT', 'customerId': 'c1'},
        form: const {},
        payment: const PaymentInput(method: 'CASH'),
        totalMinor: BigInt.from(35000),
        needsApproval: false,
        receiptOnly: true,
      );
      final r = await runIssue(p);
      expect(r.outcome, IssueOutcome.issued);
      expect(backend.calls('POST', '/documents'), isEmpty);
      expect(backend.last('POST', '/payments')!.body['amountMinor'], '35000');
      final receipt = backend.last('POST', '/receipts')!;
      expect(receipt.idempotencyKey, isNotEmpty);
      expect(receipt.body['customerId'], 'c1');
      expect(receipt.body['paymentIds'], [
        {'id': 'p-${backend.last('POST', '/payments')!.idempotencyKey}'},
      ]);
      expect(backend.calls('POST', '/documents/:id/artifact'), hasLength(1));
    },
  );

  test('share link for WhatsApp', () async {
    final r = await runIssue(issue(evaluate: false));
    expect(await createIssueShareLink(r.document.id), contains('/d/'));
  });

  group('quotes_api', () {
    test('create (net lines) → status uses the server field `to`', () async {
      final id = await createQuote(
        customerId: 'c1',
        validUntil: '2026-11-13',
        lines: [
          QuoteLine(
            description: 'עיצוב',
            quantityMicros: BigInt.from(1000000),
            unitPriceMinor: BigInt.from(100000),
          ),
        ],
      );
      expect(id, 'q1');
      expect(
        backend.last('POST', '/quotes')!.body['lines'],
        [
          {
            'description': 'עיצוב',
            'quantityMicros': '1000000',
            'unitPriceMinor': '100000',
          },
        ],
        reason: 'no rate given → none sent',
      );
      await setQuoteStatus(id, 'SENT');
      expect(backend.last('POST', '/quotes/:id/status')!.body, {'to': 'SENT'});
    });

    test('AT-20: SENT → ACCEPTED then convert {TAX_INVOICE, 1800}', () async {
      final q = Quote(id: 'q1', status: 'SENT', totalMinor: BigInt.zero);
      final id = await convertQuoteToInvoice(
        q,
        documentType: 'TAX_INVOICE',
        taxRateBasisPoints: 1800,
      );
      expect(backend.requests.map((r) => r.pattern).toList(), [
        '/quotes/:id/status',
        '/quotes/:id/convert',
      ]);
      expect(backend.last('POST', '/quotes/:id/status')!.body, {
        'to': 'ACCEPTED',
      });
      expect(backend.last('POST', '/quotes/:id/convert')!.body, {
        'documentType': 'TAX_INVOICE',
        'taxRateBasisPoints': 1800,
      });
      expect(id, startsWith('d'));
    });

    test('AT-20b: DRAFT → convert directly (no ACCEPTED)', () async {
      final q = Quote(id: 'q1', status: 'DRAFT', totalMinor: BigInt.zero);
      await convertQuoteToInvoice(
        q,
        documentType: 'TRANSACTION_INVOICE',
        taxRateBasisPoints: 0,
      );
      expect(backend.calls('POST', '/quotes/:id/status'), isEmpty);
    });

    test('fetchQuote falls back on GET /quotes before BE-06', () async {
      backend.json('GET', '/quotes', {
        'quotes': [
          {
            'id': 'q7',
            'status': 'SENT',
            'customerId': 'c1',
            'totalMinor': '100000',
            'validUntil': '2026-11-13',
          },
        ],
      });
      final q = await fetchQuote('q7');
      expect(q!.status, 'SENT');
      expect(q.totalMinor, BigInt.from(100000));
    });
  });

  group('P1', () {
    Future<String> issued300() async {
      final r = await runIssue(
        issue(
          type: 'TRANSACTION_INVOICE',
          customer: 'c1',
          evaluate: false,
          paid: false,
        ),
      );
      return r.document.id;
    }

    test(
      'BE-08: 300 → 305 = clone {TAX_INVOICE, link:true} → PUT the Composer content → finalize',
      () async {
        final source = await issued300();
        backend.requests.clear();
        final p =
            issue(
                type: 'TAX_INVOICE',
                customer: 'c1',
                evaluate: false,
                paid: false,
              )
              ..cloneFrom = source
              ..cloneTotal = '600000';
        final r = await runIssue(p);
        expect(backend.last('POST', '/documents/:id/clone')!.body, {
          'documentType': 'TAX_INVOICE',
          'link': true,
        });
        expect(backend.calls('POST', '/documents'), isEmpty);
        expect(backend.calls('PUT', '/documents/:id'), hasLength(1));
        expect(r.outcome, IssueOutcome.issued);
        expect(fake.docs[r.document.id]!['converted_from_document_id'], source);
      },
    );

    test('BE-08 missing (404 NOT_FOUND) → a plain POST /documents', () async {
      final source = await issued300();
      backend.off('POST', '/documents/:id/clone');
      final p = issue(
        type: 'TAX_INVOICE',
        customer: 'c1',
        evaluate: false,
        paid: false,
      )..cloneFrom = source;
      final r = await runIssue(p);
      expect(r.outcome, IssueOutcome.issued);
      expect(backend.calls('POST', '/documents'), hasLength(2));
      expect(p.cloneFrom, isNull);
    });

    test('BE-07: dueDate and notes reach POST /documents', () async {
      final p =
          issue(
              type: 'TAX_INVOICE',
              customer: 'c1',
              evaluate: false,
              paid: false,
            )
            ..body = {
              ...issue().body,
              'documentType': 'TAX_INVOICE',
              'customerId': 'c1',
              'dueDate': '2026-11-30',
              'notes': 'לפי הזמנה',
            };
      final r = await runIssue(p);
      expect(fake.docs[r.document.id]!['due_date'], '2026-11-30');
      expect(r.document.notes, 'לפי הזמנה');
      expect(r.document.dueDate, '2026-11-30');
    });

    test(
      'BE-06 quotes: GET /quotes/:id totals with VAT, PUT, share link, clone',
      () async {
        final id = await createQuote(
          customerId: 'c1',
          validUntil: '2026-11-13',
          notes: 'הערה',
          lines: [
            QuoteLine(
              description: 'עיצוב',
              quantityMicros: BigInt.from(1000000),
              unitPriceMinor: BigInt.from(100000),
              taxRateBasisPoints: 1800,
            ),
          ],
        );
        expect(backend.last('POST', '/quotes')!.body['notes'], 'הערה');
        final q = (await fetchQuote(id))!;
        expect(
          (
            q.detailed,
            q.netMinor,
            q.taxMinor,
            q.totalMinor,
            q.hasLinesWithoutRate,
            q.editable,
          ),
          (
            true,
            BigInt.from(100000),
            BigInt.from(18000),
            BigInt.from(118000),
            false,
            true,
          ),
        );
        expect(q.lines.single.taxRateBasisPoints, 1800);
        expect(
          await updateQuote(
            id,
            customerId: 'c1',
            lines: q.lines,
            validUntil: '2026-11-20',
          ),
          'DRAFT',
        );
        expect(backend.last('PUT', '/quotes/:id')!.body['notes'], isNull);
        expect(
          await createQuoteShareLink(id),
          'https://invoice.example/q/qtok-$id',
        );
        expect(await cloneQuote(id), isNot(id));
      },
    );

    test('a V1 list row: net total, not detailed, rate unknown', () {
      final q = Quote.fromJson({
        'id': 'q',
        'status': 'ACCEPTED',
        'totalMinor': '100000',
      });
      expect(
        (q.detailed, q.netMinor, q.taxMinor, q.hasLinesWithoutRate, q.editable),
        (false, BigInt.from(100000), null, true, false),
      );
    });

    test('document detail parses BE-07/08/11/12 fields', () {
      final d = DocumentDetail.fromJson({
        'document': {
          'id': 'd1',
          'document_type': 'TAX_INVOICE',
          'status': 'FINALIZED',
          'total_minor': '118000',
          'notes': 'n',
          'due_date': '2026-11-30',
          'supplier_id': null,
          'converted_from_document_id': 's1',
          'overdue': true,
          'payments': [
            {
              'id': 'p1',
              'method': 'CASH',
              'amountMinor': '1000',
              'receiptDocumentId': 'r1',
              'voidedAt': null,
            },
          ],
          'linkedDocuments': [
            {
              'id': 's1',
              'type': 'TRANSACTION_INVOICE',
              'number': '7',
              'relation': 'CONVERTED_FROM',
            },
          ],
          'timeline': [
            {
              'at': '2026-10-30T10:00:00Z',
              'event': 'document.shared',
              'by': 'u1',
              'byEmail': 'a@b.c',
              'detail': {},
            },
          ],
        },
        'lines': const [],
      });
      expect(
        (d.notes, d.dueDate, d.convertedFromDocumentId, d.overdue),
        ('n', '2026-11-30', 's1', true),
      );
      expect(d.payments.single.receiptDocumentId, 'r1');
      expect(d.linkedDocuments.single.relation, 'CONVERTED_FROM');
      expect(d.timeline.single.event, 'document.shared');
    });
  });
}
