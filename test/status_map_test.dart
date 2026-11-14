import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/util/labels/labels.dart';
import 'package:invoice/util/status_map.dart';

void main() {
  final today = DateTime(2026, 10, 30);
  BigInt m(int v) => BigInt.from(v);

  DocListState s(
    String status,
    String type, {
    int total = 118000,
    int? open,
    int? credited,
    String? voided,
    String? due,
    String? issue = '2026-10-20',
    String? sent,
  }) => docListState(
    status: status,
    documentType: type,
    totalMinor: m(total),
    openMinor: open == null ? null : m(open),
    creditedMinor: credited == null ? null : m(credited),
    voidedAt: voided,
    dueDate: due,
    issueDate: issue,
    sentAt: sent,
    today: today,
  );

  test('§15.5 table, row by row', () {
    for (final st in ['DRAFT', 'VALIDATING', 'READY_TO_FINALIZE']) {
      expect(s(st, 'TAX_INVOICE').status, DocStatus.draft, reason: st);
    }
    expect(
      s('PENDING_APPROVAL', 'TAX_INVOICE').status,
      DocStatus.pendingApproval,
    );
    final alloc = s('WAITING_FOR_ALLOCATION', 'TAX_INVOICE');
    expect(alloc.status, DocStatus.pendingApproval);
    expect(alloc.attributes, contains(DocAttribute.waitingTaxAuthority));
    final sig = s('ARTIFACT_PENDING', 'TAX_INVOICE', open: 118000);
    expect(sig.status, DocStatus.awaitingPayment);
    expect(sig.attributes, contains(DocAttribute.waitingSignature));

    for (final st in ['FINALIZED', 'SIGNED', 'ARCHIVED', 'SENT']) {
      for (final type in ['TRANSACTION_INVOICE', 'TAX_INVOICE']) {
        expect(s(st, type, voided: '2026-10-21').status, DocStatus.cancelled);
        expect(
          s(st, type, open: 0, credited: 118000).status,
          DocStatus.cancelled,
        );
        expect(
          s(st, type, open: 98000, credited: 20000).status,
          DocStatus.awaitingPayment,
        );
        expect(
          s(st, type, open: 118000, issue: '2026-09-01').status,
          DocStatus.overdue,
        );
        expect(
          s(st, type, open: 118000, due: '2026-10-29').status,
          DocStatus.overdue,
        );
        expect(
          s(st, type, open: 118000, due: '2026-10-30').status,
          DocStatus.awaitingPayment,
        );
        expect(s(st, type, open: 0).status, DocStatus.paid);
        expect(
          s(st, type).status,
          DocStatus.issued,
          reason: 'unknown balance never guessed',
        );
      }
      expect(s(st, 'TAX_INVOICE_RECEIPT', open: 0).status, DocStatus.paid);
      expect(s(st, 'RECEIPT').status, DocStatus.paid);
      expect(s(st, 'DONATION_RECEIPT').status, DocStatus.paid);
      expect(s(st, 'CREDIT_DOCUMENT').status, DocStatus.issued);
      expect(s(st, 'SALES_ORDER').status, DocStatus.issued);
      expect(s(st, 'PURCHASE_ORDER').status, DocStatus.issued);
      expect(s(st, 'SALES_ORDER', voided: 'x').status, DocStatus.cancelled);
      expect(s(st, 'PURCHASE_ORDER', voided: 'x').status, DocStatus.cancelled);
    }
  });

  test('issue date + 30 is the due date until BE-07 (AT-21 numbers)', () {
    expect(
      s('ARCHIVED', 'TAX_INVOICE', open: 98000, issue: '2026-09-30').status,
      DocStatus.awaitingPayment,
    );
    expect(
      s('ARCHIVED', 'TAX_INVOICE', open: 98000, issue: '2026-09-29').status,
      DocStatus.overdue,
    );
  });

  test('sent / viewed are attributes, not statuses', () {
    final r = s('ARCHIVED', 'TAX_INVOICE', open: 1000, sent: '2026-10-21');
    expect(r.status, DocStatus.awaitingPayment);
    expect(r.attributes, {DocAttribute.sent});
  });

  test('quotes', () {
    expect(quoteListStatus('DRAFT'), QuoteListStatus.draft);
    expect(quoteListStatus('SENT'), QuoteListStatus.withCustomer);
    expect(quoteListStatus('ACCEPTED'), QuoteListStatus.accepted);
    expect(quoteListStatus('CONVERTED'), QuoteListStatus.converted);
    expect(quoteListStatus('REJECTED'), QuoteListStatus.notRelevant);
    expect(quoteListStatus('EXPIRED'), QuoteListStatus.notRelevant);
  });

  test(
    'F10 words: exactly the spec labels, every enum value labelled and toned',
    () {
      expect(docStatusLabels.values.toSet(), {
        'טיוטה',
        'ממתין לאישור',
        'ממתין לתשלום',
        'באיחור',
        'שולם',
        'בוטל',
        'הופק',
      });
      expect(quoteStatusLabels.values.toSet(), {
        'טיוטה',
        'אצל הלקוח',
        'אושרה',
        'הפכה לחשבונית',
        'לא רלוונטית',
      });
      expect(docStatusLabels.keys.toSet(), DocStatus.values.toSet());
      expect(docStatusTones.keys.toSet(), DocStatus.values.toSet());
      expect(quoteStatusTones.keys.toSet(), QuoteListStatus.values.toSet());
      expect(docAttributeLabels.keys.toSet(), DocAttribute.values.toSet());
      expect(docStatusTones[DocStatus.overdue], Tone.danger);
    },
  );
}
