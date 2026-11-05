// §6.D nextAction — one test per table row, plus the fixed ⋯ and §4.4 presets.

import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/screens/document/next_action.dart';
import 'package:invoice/state/caps.dart';

import '../fakes/me_fixtures.dart';

Caps capsOf(Preset p, {Map<String, dynamic>? policy}) =>
    Caps.fromMe(Me.fromJson(meJson(p, approvalPolicy: policy)));

DocViewer viewer(Preset p,
        {bool exempt = false, bool manual = false, Map<String, dynamic>? policy, String userId = 'u-me'}) =>
    DocViewer(caps: capsOf(p, policy: policy), userId: userId, vatExempt: exempt, manualAllocationEnabled: manual);

DocFacts open305({String? sentAt, bool phone = true, String status = 'ARCHIVED', int credited = 0}) => DocFacts(
      status: status,
      documentType: 'TAX_INVOICE',
      totalMinor: BigInt.from(118000),
      openMinor: BigInt.from(118000 - credited),
      creditedMinor: BigInt.from(credited),
      sentAt: sentAt,
      customerHasPhone: phone,
    );

void main() {
  final otherApprover = {
    'mode': 'THRESHOLD',
    'thresholdMinor': '500000',
    'selfApprovalAllowed': false,
    'otherApproverExists': true,
  };

  group('§6.D rows', () {
    test('1: PENDING_APPROVAL + approval.decide, not the submitter → "אשר והפק" + ⋯ "דחה"', () {
      final n = nextAction(DocFacts(status: 'PENDING_APPROVAL', documentType: 'TAX_INVOICE', submittedBy: 'u-emp'),
          viewer(Preset.owner, policy: otherApprover));
      expect(n.row, 1);
      expect(n.label, 'אשר והפק');
      expect(n.menu, [DocAction.reject]);
    });

    test('1: the submitter is a sole approver → may approve', () {
      final n = nextAction(DocFacts(status: 'PENDING_APPROVAL', documentType: 'TAX_INVOICE', submittedBy: 'u-me'),
          viewer(Preset.owner)); // otherApproverExists false
      expect(n.row, 1);
    });

    test('2: own submission with another approver, or no approval.decide → waiting, no button', () {
      final own = nextAction(DocFacts(status: 'PENDING_APPROVAL', documentType: 'TAX_INVOICE', submittedBy: 'u-me'),
          viewer(Preset.owner, policy: otherApprover));
      expect(own.row, 2);
      expect(own.primary, isNull);
      expect(own.waiting, 'ממתין לאישור');
      final emp = nextAction(DocFacts(status: 'PENDING_APPROVAL', documentType: 'TAX_INVOICE', submittedBy: 'u-x'),
          viewer(Preset.employeeIssuer));
      expect(emp.row, 2);
      expect(emp.menu, isEmpty);
    });

    test('3: draft + doc.draft → "המשך"; rejected → "תקן ושלח שוב"', () {
      for (final s in ['DRAFT', 'VALIDATING', 'READY_TO_FINALIZE']) {
        final n = nextAction(DocFacts(status: s, documentType: 'TAX_INVOICE'), viewer(Preset.employee));
        expect((n.row, n.label), (3, 'המשך'), reason: s);
      }
      final r = nextAction(DocFacts(status: 'DRAFT', documentType: 'TAX_INVOICE', rejected: true),
          viewer(Preset.employee));
      expect(r.label, 'תקן ושלח שוב');
      // a viewer gets nothing on a draft (no PDF to share)
      final v = nextAction(DocFacts(status: 'DRAFT', documentType: 'TAX_INVOICE'), viewer(Preset.viewer));
      expect((v.row, v.primary), (0, null));
      expect(v.menu, isEmpty);
    });

    test('4: WAITING_FOR_ALLOCATION + allocation.request → "נסה שוב" + state ⋯', () {
      final n = nextAction(
          DocFacts(
              status: 'WAITING_FOR_ALLOCATION',
              documentType: 'TAX_INVOICE',
              allocationDecisionAllowed: true,
              allocationNeedsAuthorization: true),
          viewer(Preset.owner, manual: true));
      expect(n.row, 4);
      expect(n.label, 'נסה שוב');
      expect(n.menu, [
        DocAction.manualAllocation,
        DocAction.continueWithoutNumber,
        DocAction.cancelAllocation,
        DocAction.connectTaxAuthority,
      ]);
    });

    test('4: AT-62 "המשך בלי מספר" hidden unless the decision allows it; manual only when enabled', () {
      final n = nextAction(DocFacts(status: 'WAITING_FOR_ALLOCATION', documentType: 'TAX_INVOICE'),
          viewer(Preset.owner));
      expect(n.menu, [DocAction.cancelAllocation]);
    });

    test('5: WAITING_FOR_ALLOCATION without allocation.request → waiting', () {
      final n = nextAction(DocFacts(status: 'WAITING_FOR_ALLOCATION', documentType: 'TAX_INVOICE'),
          viewer(Preset.employee));
      expect((n.row, n.primary, n.waiting), (5, null, 'ממתין למספר הקצאה'));
    });

    test('6/7: ARTIFACT_PENDING → "חתום והפק PDF" for doc.issue, else waiting', () {
      final f = DocFacts(status: 'ARTIFACT_PENDING', documentType: 'TAX_INVOICE_RECEIPT');
      expect(nextAction(f, viewer(Preset.owner)).label, 'חתום והפק PDF');
      final w = nextAction(f, viewer(Preset.employee));
      expect((w.row, w.waiting), (7, 'ממתין לחתימה של בעל העסק'));
    });

    test('8: open 305 never sent + doc.send → "שלח בווטסאפ" (no phone: "שלח") + ⋯ "קיבלתי תשלום"', () {
      final n = nextAction(open305(), viewer(Preset.owner));
      expect((n.row, n.label), (8, 'שלח בווטסאפ'));
      expect(n.menu.first, DocAction.recordPayment);
      expect(nextAction(open305(phone: false), viewer(Preset.owner)).label, 'שלח');
      // employee without payment.record: no "קיבלתי תשלום" in ⋯
      expect(nextAction(open305(), viewer(Preset.employee)).menu, isNot(contains(DocAction.recordPayment)));
    });

    test('9: open 305 already sent + payment.record → "קיבלתי תשלום" + ⋯ "שלח שוב"', () {
      final n = nextAction(open305(sentAt: '2026-10-30T10:00:00Z'), viewer(Preset.owner));
      expect((n.row, n.label), (9, 'קיבלתי תשלום'));
      expect(n.menu.first, DocAction.sendAgain);
    });

    test('10: open, sent, doc.send without payment.record → "שלח תזכורת"', () {
      final n = nextAction(open305(sentAt: '2026-10-30T10:00:00Z'), viewer(Preset.employee));
      expect((n.row, n.label), (10, 'שלח תזכורת'));
    });

    test('11: quote DRAFT + doc.send → "שלח הצעה" + ⋯ "הפוך לחשבונית" (AT-20b)', () {
      final n = nextAction(DocFacts(status: 'DRAFT', isQuote: true), viewer(Preset.owner));
      expect((n.row, n.label), (11, 'שלח הצעה'));
      expect(n.menu, [DocAction.convertQuote]);
    });

    test('12: quote SENT → "הפוך לחשבונית" + ⋯ "הלקוח דחה" · "שלח שוב" (AT-20)', () {
      final n = nextAction(DocFacts(status: 'SENT', isQuote: true), viewer(Preset.owner));
      expect((n.row, n.label), (12, 'הפוך לחשבונית'));
      expect(n.menu, [DocAction.customerRejected, DocAction.sendAgain]);
    });

    test('13/14/15: ACCEPTED → convert; CONVERTED → "פתח חשבונית"; REJECTED/EXPIRED → "לא רלוונטית"', () {
      expect(nextAction(DocFacts(status: 'ACCEPTED', isQuote: true), viewer(Preset.owner)).row, 13);
      final c = nextAction(DocFacts(status: 'CONVERTED', isQuote: true, convertedDocumentId: 'd9'),
          viewer(Preset.viewer));
      expect((c.row, c.label), (14, 'פתח חשבונית'));
      for (final s in ['REJECTED', 'EXPIRED']) {
        final r = nextAction(DocFacts(status: s, isQuote: true), viewer(Preset.owner));
        expect((r.row, r.primary, r.waiting), (15, null, 'לא רלוונטית'));
      }
    });

    test('16: paid / receipt / credit / cancelled + doc.view → "שתף"', () {
      for (final f in [
        DocFacts(status: 'ARCHIVED', documentType: 'TAX_INVOICE_RECEIPT', totalMinor: BigInt.from(1)),
        DocFacts(status: 'ARCHIVED', documentType: 'RECEIPT'),
        DocFacts(status: 'ARCHIVED', documentType: 'CREDIT_DOCUMENT'),
        DocFacts(status: 'ARCHIVED', documentType: 'SALES_ORDER'),
        open305(credited: 118000), // fully credited = בוטל
        DocFacts(status: 'SENT', documentType: 'TAX_INVOICE', totalMinor: BigInt.from(1), openMinor: BigInt.zero),
      ]) {
        final n = nextAction(f, viewer(Preset.viewer));
        expect((n.row, n.label), (16, 'שתף'), reason: f.documentType);
      }
    });
  });

  group('fixed ⋯ (שתף · שכפל · בטל / זכה)', () {
    test('owner on an open 305: state items, then share, duplicate, cancel last', () {
      final n = nextAction(open305(sentAt: 'x'), viewer(Preset.owner));
      // "שלח שוב" and "שתף" open the same S6 sheet: only one of them.
      expect(n.menu, [DocAction.sendAgain, DocAction.duplicate, DocAction.cancelOrCredit]);
    });

    test('§6.D: ⋯ never has two items with the same target, at most 4 (open 300 with "הפק חשבונית מס")', () {
      for (final t in ['TAX_INVOICE', 'TRANSACTION_INVOICE']) {
        final f = DocFacts(
            status: 'ARCHIVED',
            documentType: t,
            totalMinor: BigInt.from(118000),
            openMinor: BigInt.from(118000),
            sentAt: 'x');
        final n = nextAction(f, viewer(Preset.owner));
        expect(n.row, 9, reason: t);
        expect(n.menu.length, lessThanOrEqualTo(4), reason: t);
        final sheetOpeners = n.menu.where((a) => a == DocAction.share || a == DocAction.sendAgain);
        expect(sheetOpeners, hasLength(1), reason: t);
        expect(n.menu.toSet(), hasLength(n.menu.length), reason: t);
      }
    });

    test('AT-42 employee + "מפיק בעצמו": no "בטל / זכה", no "אשר והפק" on another\'s document', () {
      final n = nextAction(open305(sentAt: 'x'), viewer(Preset.employeeIssuer));
      expect(n.menu, isNot(contains(DocAction.cancelOrCredit)));
      final p = nextAction(DocFacts(status: 'PENDING_APPROVAL', documentType: 'TAX_INVOICE', submittedBy: 'u-x'),
          viewer(Preset.employeeIssuer));
      expect(p.primary, isNull);
    });

    test('AT-44 accountant (P0 rep) and AT-40 viewer: "שתף" only, no cancel, no duplicate', () {
      for (final pr in [Preset.accountantRep, Preset.viewer]) {
        final n = nextAction(open305(sentAt: 'x'), viewer(pr));
        expect(n.label, 'שתף', reason: '$pr');
        expect(n.menu, isEmpty, reason: '$pr');
      }
    });

    test('AT-56: "בטל / זכה" only for 305/320 among invoices; never for receipts or credits', () {
      DocFacts f(String t) => DocFacts(status: 'ARCHIVED', documentType: t, totalMinor: BigInt.from(100));
      expect(nextAction(f('TAX_INVOICE_RECEIPT'), viewer(Preset.owner)).menu, contains(DocAction.cancelOrCredit));
      for (final t in ['RECEIPT', 'DONATION_RECEIPT', 'CREDIT_DOCUMENT']) {
        expect(nextAction(f(t), viewer(Preset.owner)).menu, isNot(contains(DocAction.cancelOrCredit)), reason: t);
      }
    });

    test('quotes have no fixed ⋯ items; drafts are not duplicated', () {
      expect(nextAction(DocFacts(status: 'ACCEPTED', isQuote: true), viewer(Preset.owner)).menu, isEmpty);
      expect(nextAction(DocFacts(status: 'DRAFT', documentType: 'TAX_INVOICE'), viewer(Preset.owner)).menu, isEmpty);
    });
  });

  group('hidden amounts and a missing PDF', () {
    test('BE-03 hidden amounts (another member\'s document): no money rows, no share / send, no cancel', () {
      final f = DocFacts(
          status: 'ARCHIVED', documentType: 'TAX_INVOICE', amountHidden: true, openMinor: BigInt.zero, sentAt: 'x');
      for (final pr in [Preset.employee, Preset.employeeIssuer, Preset.owner]) {
        final n = nextAction(f, viewer(pr));
        expect(n.primary, isNot(anyOf(DocAction.share, DocAction.recordPayment, DocAction.sendReminder)),
            reason: '$pr');
        expect(n.menu, isNot(contains(DocAction.share)), reason: '$pr');
        expect(n.menu, isNot(contains(DocAction.sendAgain)), reason: '$pr');
        expect(n.menu, isNot(contains(DocAction.cancelOrCredit)), reason: '$pr');
      }
      final q = nextAction(DocFacts(status: 'DRAFT', isQuote: true, amountHidden: true, quoteFull: true),
          viewer(Preset.employee));
      expect(q.primary, isNot(DocAction.sendQuote));
      expect(q.menu, isNot(contains(DocAction.share)));
    });

    test('§6.D edge: issued but no stored PDF → row 6 "חתום והפק PDF" (doc.issue), else row 7', () {
      final f = DocFacts(
          status: 'FINALIZED',
          documentType: 'CREDIT_DOCUMENT',
          totalMinor: BigInt.from(100),
          pdfMissing: true);
      final o = nextAction(f, viewer(Preset.owner));
      expect((o.row, o.label), (6, 'חתום והפק PDF'));
      final v = nextAction(f, viewer(Preset.viewer));
      expect((v.row, v.primary), (7, null));
    });
  });

  group('P1 ⋯ items', () {
    DocFacts issued(String t, {bool converted = false, String? voidedAt, int open = 0}) => DocFacts(
          status: 'ARCHIVED',
          documentType: t,
          totalMinor: BigInt.from(118000),
          openMinor: BigInt.from(open),
          voidedAt: voidedAt,
          sentAt: 'x',
          convertedToInvoice: converted,
        );

    test('BE-08: 100 and a paid 300 (VAT business) → "הפק חשבונית מס" before the fixed items', () {
      final order = nextAction(issued('SALES_ORDER'), viewer(Preset.owner));
      expect(order.menu.first, DocAction.issueTaxInvoice);
      expect(order.menu.last, DocAction.cancelOrCredit);
      final paid300 = nextAction(issued('TRANSACTION_INVOICE'), viewer(Preset.owner));
      expect(paid300.menu, contains(DocAction.issueTaxInvoice));
      expect(paid300.menu.indexOf(DocAction.issueTaxInvoice), lessThan(paid300.menu.indexOf(DocAction.duplicate)));
      final open300 = nextAction(issued('TRANSACTION_INVOICE', open: 118000), viewer(Preset.owner));
      expect(open300.menu, contains(DocAction.issueTaxInvoice));
    });

    test('no "הפק חשבונית מס": exempt 300, already converted, voided, no doc.draft, 305', () {
      expect(nextAction(issued('TRANSACTION_INVOICE'), viewer(Preset.owner, exempt: true)).menu,
          isNot(contains(DocAction.issueTaxInvoice)));
      expect(nextAction(issued('SALES_ORDER', converted: true), viewer(Preset.owner)).menu,
          isNot(contains(DocAction.issueTaxInvoice)));
      expect(nextAction(issued('SALES_ORDER', voidedAt: 'x'), viewer(Preset.owner)).menu,
          isNot(contains(DocAction.issueTaxInvoice)));
      expect(nextAction(issued('SALES_ORDER'), viewer(Preset.viewer)).menu, isNot(contains(DocAction.issueTaxInvoice)));
      expect(nextAction(issued('TAX_INVOICE'), viewer(Preset.owner)).menu, isNot(contains(DocAction.issueTaxInvoice)));
    });

    test('BE-06 quote: ⋯ adds שתף · שכפל after the state items; viewer gets שתף only', () {
      final sent = nextAction(DocFacts(status: 'SENT', isQuote: true, quoteFull: true), viewer(Preset.owner));
      expect(sent.menu,
          [DocAction.customerRejected, DocAction.sendAgain, DocAction.share, DocAction.duplicate]);
      final rejected = nextAction(DocFacts(status: 'REJECTED', isQuote: true, quoteFull: true), viewer(Preset.owner));
      expect(rejected.menu, [DocAction.share, DocAction.duplicate]);
      final view = nextAction(DocFacts(status: 'SENT', isQuote: true, quoteFull: true), viewer(Preset.viewer));
      expect(view.menu, [DocAction.share]);
    });
  });
}
