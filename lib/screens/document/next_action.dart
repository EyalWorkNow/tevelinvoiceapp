// §6.D "הפעולה הבאה" — a pure function, table-tested (test/document/
// next_action_test.dart). The first row that holds wins:
//
// | #  | state                                                   | primary                     | ⋯ in this state |
// | 1  | PENDING_APPROVAL + approval.decide (not submitter / sole approver) | אשר והפק         | דחה |
// | 2  | PENDING_APPROVAL otherwise                              | — "ממתין לאישור"            | — |
// | 3  | DRAFT/VALIDATING/READY_TO_FINALIZE + doc.draft          | המשך (rejected: תקן ושלח שוב)| — |
// | 4  | WAITING_FOR_ALLOCATION + allocation.request             | נסה שוב                     | ידני · בלי מספר (decision) · בטל בקשה · רשות המסים (auth) |
// | 5  | WAITING_FOR_ALLOCATION otherwise                        | — "ממתין למספר הקצאה"       | — |
// | 6  | ARTIFACT_PENDING (or issued, PDF missing) + doc.issue   | חתום והפק PDF               | — |
// | 7  | ARTIFACT_PENDING (or issued, PDF missing) otherwise     | — "ממתין לחתימה…"           | — |
// | 8  | 300/305 open, never sent + doc.send                     | שלח בווטסאפ / שלח           | קיבלתי תשלום (payment.record) |
// | 9  | 300/305 open + payment.record                           | קיבלתי תשלום                | שלח שוב (doc.send) |
// | 10 | 300/305 open + doc.send                                 | שלח תזכורת                  | — |
// | 11 | quote DRAFT + doc.send                                  | שלח הצעה                    | הפוך לחשבונית |
// | 12 | quote SENT + doc.draft                                  | הפוך לחשבונית               | הלקוח דחה · שלח שוב |
// | 13 | quote ACCEPTED + doc.draft                              | הפוך לחשבונית               | — |
// | 14 | quote CONVERTED                                         | פתח חשבונית                 | — |
// | 15 | quote REJECTED/EXPIRED                                  | — "לא רלוונטית"             | — |
// | 16 | everything else + doc.view (issued)                     | שתף                         | — |
// Fixed ⋯ after the state items: שתף · שכפל · בטל / זכה (red, last; §8.3).
// No "שתף" when the state items already hold "שלח שוב" (same S6 sheet).
// Hidden amounts (BE-03 redactUnlessOwn: another member's document without
// money:read) → no money rows (8–10), no share / send (the PDF and the link
// are ownOrMoney), no cancel.
// P1 state items: "הפק חשבונית מס" on an issued 100 / 300 of a VAT business
// (BE-08 linked clone; hidden once a 305 was made from it). Quotes with the
// BE-06 full view also get שתף (PDF + link) and שכפל.

import '../../state/caps.dart';
import '../../util/cancel_policy.dart';
import '../../util/labels/document_he.dart';
import '../../util/status_map.dart';

enum DocAction {
  approve,
  reject,
  continueDraft,
  retryAllocation,
  manualAllocation,
  continueWithoutNumber,
  cancelAllocation,
  connectTaxAuthority,
  signAndIssue,
  sendWhatsApp,
  send,
  recordPayment,
  sendAgain,
  sendReminder,
  sendQuote,
  convertQuote,
  customerRejected,
  openInvoice,
  issueTaxInvoice,
  share,
  duplicate,
  cancelOrCredit,
}

/// What D knows about the document (or quote) — plain values only.
class DocFacts {
  DocFacts({
    required this.status,
    this.documentType = 'QUOTE',
    this.isQuote = false,
    BigInt? totalMinor,
    this.openMinor,
    this.creditedMinor,
    this.paidMinor,
    this.voidedAt,
    this.sentAt,
    this.submittedBy,
    this.rejected = false,
    this.customerHasPhone = false,
    this.convertedDocumentId,
    this.allocationDecisionAllowed = false,
    this.allocationNeedsAuthorization = false,
    this.convertedToInvoice = false,
    this.quoteFull = false,
    this.amountHidden = false,
    this.pdfMissing = false,
  }) : totalMinor = totalMinor ?? BigInt.zero;

  /// Server status (document or quote).
  final String status;
  final String documentType;
  final bool isQuote;
  final BigInt totalMinor;

  /// §15.5: BE-10a openMinor, else balanceMinor; null = unknown.
  final BigInt? openMinor;
  final BigInt? creditedMinor;
  final BigInt? paidMinor;
  final String? voidedAt;
  final String? sentAt;
  final String? submittedBy;

  /// The draft came back rejected (BE-37 `rejection`).
  final bool rejected;
  final bool customerHasPhone;
  final String? convertedDocumentId;
  final bool allocationDecisionAllowed;
  final bool allocationNeedsAuthorization;

  /// A 305 was already issued from this 100 / 300 (BE-11 linkedDocuments
  /// CONVERTED_TO).
  final bool convertedToInvoice;

  /// The quote came from BE-06 GET /quotes/:id (lines, PDF, link, clone).
  final bool quoteFull;

  /// The server redacted the amounts (no money:read, not the creator): the
  /// PDF, the share link and e-mail are refused for this viewer too.
  final bool amountHidden;

  /// Issued but the server has no stored original (ARTIFACT_REQUIRED even
  /// after D tried to create it) → rows 6 / 7.
  final bool pdfMissing;

  CancelFacts get cancelFacts => CancelFacts(
        documentType: documentType,
        status: status,
        totalMinor: totalMinor,
        creditedMinor: creditedMinor,
        paidMinor: paidMinor,
        voidedAt: voidedAt,
      );
}

/// Who is looking, in which business.
class DocViewer {
  const DocViewer({
    required this.caps,
    this.userId,
    this.vatExempt = false,
    this.manualAllocationEnabled = false,
    this.voidAvailable = true,
  });

  final Caps caps;
  final String? userId;
  final bool vatExempt;

  /// /me.shaam.manualEntryEnabled.
  final bool manualAllocationEnabled;

  /// BE-36 void deployed (P1).
  final bool voidAvailable;

  bool can(Cap c) => caps.can(c);
}

class NextAction {
  const NextAction({required this.row, this.primary, this.label, this.waiting, this.menu = const []});

  /// §6.D row (1–16), 0 = nothing applies (e.g. a draft for a viewer).
  final int row;

  /// Null = no PrimaryButton ("—" rows, F2).
  final DocAction? primary;
  final String? label;

  /// "—" rows: the one line shown instead of a button.
  final String? waiting;

  /// ⋯ items in display order (state items, then the fixed ones; the
  /// destructive one last).
  final List<DocAction> menu;

  @override
  String toString() => 'NextAction(row $row, $primary "$label", menu $menu)';
}

const Set<String> _draft = {'DRAFT', 'VALIDATING', 'READY_TO_FINALIZE', 'REJECTED'};
const Set<String> _issued = {'FINALIZED', 'SIGNED', 'ARCHIVED', 'SENT'};
const Set<String> _duplicable = {
  'TRANSACTION_INVOICE', 'TAX_INVOICE', 'TAX_INVOICE_RECEIPT', 'SALES_ORDER', 'PURCHASE_ORDER',
};

/// Open receivable (§15.5): 300/305, issued, not cancelled, open > 0.
bool isOpenReceivable(DocFacts d) {
  if (!isCollectionType(d.documentType) || !_issued.contains(d.status)) return false;
  if (d.voidedAt != null) return false;
  final credited = d.creditedMinor ?? BigInt.zero;
  if (d.totalMinor > BigInt.zero && credited >= d.totalMinor) return false;
  return (d.openMinor ?? BigInt.zero) > BigInt.zero;
}

/// The label of [a] in D (buttons and ⋯ rows).
String docActionLabel(DocAction a, {bool rejected = false, bool hasPhone = true}) => switch (a) {
      DocAction.approve => DocumentHe.approveAndIssue,
      DocAction.reject => DocumentHe.reject,
      DocAction.continueDraft => rejected ? DocumentHe.fixAndResend : DocumentHe.continueDraft,
      DocAction.retryAllocation => DocumentHe.retry,
      DocAction.manualAllocation => DocumentHe.manualAllocation,
      DocAction.continueWithoutNumber => DocumentHe.continueWithoutNumber,
      DocAction.cancelAllocation => DocumentHe.cancelAllocation,
      DocAction.connectTaxAuthority => DocumentHe.connectTaxAuthority,
      DocAction.signAndIssue => DocumentHe.signAndIssue,
      DocAction.sendWhatsApp => hasPhone ? DocumentHe.sendWhatsApp : DocumentHe.send,
      DocAction.send => DocumentHe.send,
      DocAction.recordPayment => DocumentHe.recordPayment,
      DocAction.sendAgain => DocumentHe.sendAgain,
      DocAction.sendReminder => DocumentHe.sendReminder,
      DocAction.sendQuote => DocumentHe.sendQuote,
      DocAction.convertQuote => DocumentHe.convertToInvoice,
      DocAction.customerRejected => DocumentHe.customerRejected,
      DocAction.openInvoice => DocumentHe.openInvoice,
      DocAction.issueTaxInvoice => DocumentHe.issueTaxInvoice,
      DocAction.share => DocumentHe.share,
      DocAction.duplicate => DocumentHe.duplicate,
      DocAction.cancelOrCredit => DocumentHe.cancelOrCredit,
    };

/// §6.D. Pure: same input → same output.
NextAction nextAction(DocFacts d, DocViewer v) {
  final (row, primary, waiting, state) = _row(d, v);
  final menu = <DocAction>[...state];
  final mayShare = v.can(Cap.docView) && !d.amountHidden && primary != DocAction.share;
  if (!d.isQuote && _mayIssueTaxInvoice(d, v)) menu.add(DocAction.issueTaxInvoice);
  if (d.isQuote && d.quoteFull) {
    if (mayShare) menu.add(DocAction.share);
    if (v.can(Cap.docDraft)) menu.add(DocAction.duplicate);
  }
  if (!d.isQuote) {
    if (mayShare && _issued.contains(d.status) && !state.contains(DocAction.sendAgain)) {
      menu.add(DocAction.share);
    }
    if (v.can(Cap.docDraft) && _duplicable.contains(d.documentType) && _issued.contains(d.status)) {
      menu.add(DocAction.duplicate);
    }
    if (!d.amountHidden &&
        showCancelItem(d.cancelFacts,
        canCancel: v.can(Cap.docCancel), vatExempt: v.vatExempt, voidAvailable: v.voidAvailable)) {
      menu.add(DocAction.cancelOrCredit);
    }
  }
  return NextAction(
    row: row,
    primary: primary,
    label: primary == null ? null : docActionLabel(primary, rejected: d.rejected, hasPhone: d.customerHasPhone),
    waiting: waiting,
    menu: menu,
  );
}

/// §8.1 / §8.2.3: 100 → 305, and 300 → 305 for a VAT business (BE-08).
bool _mayIssueTaxInvoice(DocFacts d, DocViewer v) {
  final fromType = d.documentType == 'SALES_ORDER' || (d.documentType == 'TRANSACTION_INVOICE' && !v.vatExempt);
  return fromType &&
      _issued.contains(d.status) &&
      d.voidedAt == null &&
      !d.convertedToInvoice &&
      v.can(Cap.docDraft);
}

(int, DocAction?, String?, List<DocAction>) _row(DocFacts d, DocViewer v) {
  if (d.isQuote) return _quoteRow(d, v);
  final s = d.status;
  if (s == 'PENDING_APPROVAL') {
    final mine = d.submittedBy != null && d.submittedBy == v.userId;
    final soleApprover = !v.caps.approvalPolicy.otherApproverExists;
    if (v.can(Cap.approvalDecide) && (!mine || soleApprover)) {
      return (1, DocAction.approve, null, [DocAction.reject]);
    }
    return (2, null, DocumentHe.waitingApproval, const []);
  }
  if (_draft.contains(s)) {
    if (v.can(Cap.docDraft)) return (3, DocAction.continueDraft, null, const []);
    return (0, null, null, const []);
  }
  if (s == 'WAITING_FOR_ALLOCATION') {
    if (v.can(Cap.allocationRequest)) {
      return (
        4,
        DocAction.retryAllocation,
        null,
        [
          if (v.manualAllocationEnabled) DocAction.manualAllocation,
          if (d.allocationDecisionAllowed) DocAction.continueWithoutNumber,
          DocAction.cancelAllocation,
          if (d.allocationNeedsAuthorization) DocAction.connectTaxAuthority,
        ]
      );
    }
    return (5, null, DocumentHe.waitingAllocation, const []);
  }
  if (s == 'ARTIFACT_PENDING' || (d.pdfMissing && _issued.contains(s))) {
    if (v.can(Cap.docIssue)) return (6, DocAction.signAndIssue, null, const []);
    return (7, null, DocumentHe.waitingSignature, const []);
  }
  if (!d.amountHidden && isOpenReceivable(d)) {
    if (d.sentAt == null && v.can(Cap.docSend)) {
      return (8, DocAction.sendWhatsApp, null, [if (v.can(Cap.paymentRecord)) DocAction.recordPayment]);
    }
    if (v.can(Cap.paymentRecord)) {
      return (9, DocAction.recordPayment, null, [if (v.can(Cap.docSend)) DocAction.sendAgain]);
    }
    if (v.can(Cap.docSend)) return (10, DocAction.sendReminder, null, const []);
  }
  if (v.can(Cap.docView) && !d.amountHidden && _issued.contains(s)) {
    return (16, DocAction.share, null, const []);
  }
  return (0, null, null, const []);
}

(int, DocAction?, String?, List<DocAction>) _quoteRow(DocFacts d, DocViewer v) {
  final send = v.can(Cap.docSend) && !d.amountHidden;
  switch (d.status) {
    case 'DRAFT':
      if (send) {
        return (11, DocAction.sendQuote, null, [if (v.can(Cap.docDraft)) DocAction.convertQuote]);
      }
      if (v.can(Cap.docDraft)) return (11, DocAction.convertQuote, null, const []);
    case 'SENT':
      if (v.can(Cap.docDraft)) {
        return (
          12,
          DocAction.convertQuote,
          null,
          [DocAction.customerRejected, if (send) DocAction.sendAgain]
        );
      }
    case 'ACCEPTED':
      if (v.can(Cap.docDraft)) return (13, DocAction.convertQuote, null, const []);
    case 'CONVERTED':
      if (d.convertedDocumentId != null) return (14, DocAction.openInvoice, null, const []);
    case 'REJECTED' || 'EXPIRED':
      return (15, null, DocumentHe.notRelevant, const []);
  }
  return (0, null, null, const []);
}
