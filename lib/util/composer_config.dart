// Composer configuration table (SPEC-v2 §8.1). Owner: squad B.
//
// The Composer never branches on a document type: every difference comes from
// the row of this table (test/composer_config_test.dart has one test per row).
//
// | code  | type                     | counterparty | VAT                        | on screen                 | entry                       | needs               | after issue |
// | 320   | חשבונית מס-קבלה          | customer     | yes                        | amount, description, method | PAID (VAT business)       | docIssue (else submit) | share   |
// | 305   | חשבונית מס               | customer     | yes                        | amount, description       | REQUEST (VAT business)      | docDraft            | collect     |
// | 300   | חשבון עסקה / פרופורמה    | customer     | exempt: no; others: yes    | amount, description       | REQUEST (exempt); "עוד"     | docDraft            | collect     |
// | 400   | קבלה                     | customer     | no                         | amount, method            | PAID (exempt); "עוד"        | paymentRecord       | share       |
// | 405   | קבלה על תרומה            | donor (ID)   | no                         | amount, method            | "עוד" (nonprofit + §46)     | paymentRecord       | share       |
// | 330   | זיכוי                    | from source  | from source                | amount                    | S8 only (squad C)           | docCancel           | share       |
// | QUOTE | הצעת מחיר                | customer     | business rate              | amount/lines, valid until | ＋ "הצעת מחיר"              | docDraft            | quote       |
// | 100   | הזמנה                    | customer     | yes                        | lines                     | "עוד"                       | docDraft            | share       |
// | 500   | הזמנת רכש                | supplier     | yes                        | supplier, lines           | "עוד"                       | docDraft + supplier | share       |
// 200/210/310/340/345/205/410/420/600/610/700/710/800–910: not in the app (W).

import '../state/caps.dart';

/// Document kinds the Composer (and S8 for 330) can produce.
enum DocKind {
  taxInvoiceReceipt,
  taxInvoice,
  transactionInvoice,
  receipt,
  donationReceipt,
  credit,
  quote,
  salesOrder,
  purchaseOrder,
}

enum Counterparty { customer, donor, supplier, fromSource }

/// How the VAT of a kind is decided.
enum VatRule {
  /// Always the business rate (never offered to an exempt business).
  always,

  /// Never (receipts).
  never,

  /// Exempt / nonprofit: none; VAT businesses: the business rate.
  byBusiness,

  /// Same rates as the credited source document (330).
  fromSource,
}

/// What D offers right after the issue (§6.D).
enum AfterIssue { share, collect, quote }

class ComposerConfig {
  const ComposerConfig({
    required this.kind,
    required this.code,
    required this.serverType,
    required this.counterparty,
    required this.vat,
    required this.paid,
    required this.cap,
    required this.after,
    this.vatBusinessesOnly = false,
    this.viaComposer = true,
    this.lines = false,
    this.validUntil = false,
    this.needsSection46 = false,
    this.nonprofitOnly = false,
  });

  final DocKind kind;

  /// Tax-authority code; null for a quote.
  final int? code;

  /// POST /documents documentType; null for a quote.
  final String? serverType;
  final Counterparty counterparty;
  final VatRule vat;

  /// Money was received: a payment is recorded (payment-method chips shown).
  final bool paid;

  /// The capability that unlocks the kind (§8.1 "זמין ל-").
  final Cap cap;
  final AfterIssue after;

  /// Not for עוסק פטור / עמותה (server: DOCUMENT_TYPE_NOT_ALLOWED_FOR_BUSINESS).
  final bool vatBusinessesOnly;

  /// False = never opened in the Composer (330 is S8 only).
  final bool viaComposer;

  /// Opens with the line editor (S3) as the main input.
  final bool lines;

  /// Quote: "בתוקף עד" (+14 days).
  final bool validUntil;
  final bool needsSection46;
  final bool nonprofitOnly;

  /// Receipt-only flow: POST /payments → POST /receipts (no POST /documents).
  bool get receiptOnly => paid && vat == VatRule.never;
  bool get isQuote => kind == DocKind.quote;
}

const Map<DocKind, ComposerConfig> composerTable = {
  DocKind.taxInvoiceReceipt: ComposerConfig(
      kind: DocKind.taxInvoiceReceipt, code: 320, serverType: 'TAX_INVOICE_RECEIPT',
      counterparty: Counterparty.customer, vat: VatRule.always, paid: true,
      cap: Cap.docIssue, after: AfterIssue.share, vatBusinessesOnly: true),
  DocKind.taxInvoice: ComposerConfig(
      kind: DocKind.taxInvoice, code: 305, serverType: 'TAX_INVOICE',
      counterparty: Counterparty.customer, vat: VatRule.always, paid: false,
      cap: Cap.docDraft, after: AfterIssue.collect, vatBusinessesOnly: true),
  DocKind.transactionInvoice: ComposerConfig(
      kind: DocKind.transactionInvoice, code: 300, serverType: 'TRANSACTION_INVOICE',
      counterparty: Counterparty.customer, vat: VatRule.byBusiness, paid: false,
      cap: Cap.docDraft, after: AfterIssue.collect),
  DocKind.receipt: ComposerConfig(
      kind: DocKind.receipt, code: 400, serverType: 'RECEIPT',
      counterparty: Counterparty.customer, vat: VatRule.never, paid: true,
      cap: Cap.paymentRecord, after: AfterIssue.share),
  DocKind.donationReceipt: ComposerConfig(
      kind: DocKind.donationReceipt, code: 405, serverType: 'DONATION_RECEIPT',
      counterparty: Counterparty.donor, vat: VatRule.never, paid: true,
      cap: Cap.paymentRecord, after: AfterIssue.share, needsSection46: true, nonprofitOnly: true),
  DocKind.credit: ComposerConfig(
      kind: DocKind.credit, code: 330, serverType: 'CREDIT_DOCUMENT',
      counterparty: Counterparty.fromSource, vat: VatRule.fromSource, paid: false,
      cap: Cap.docCancel, after: AfterIssue.share, vatBusinessesOnly: true, viaComposer: false),
  DocKind.quote: ComposerConfig(
      kind: DocKind.quote, code: null, serverType: null,
      counterparty: Counterparty.customer, vat: VatRule.byBusiness, paid: false,
      cap: Cap.docDraft, after: AfterIssue.quote, validUntil: true),
  DocKind.salesOrder: ComposerConfig(
      kind: DocKind.salesOrder, code: 100, serverType: 'SALES_ORDER',
      counterparty: Counterparty.customer, vat: VatRule.byBusiness, paid: false,
      cap: Cap.docDraft, after: AfterIssue.share, lines: true),
  DocKind.purchaseOrder: ComposerConfig(
      kind: DocKind.purchaseOrder, code: 500, serverType: 'PURCHASE_ORDER',
      counterparty: Counterparty.supplier, vat: VatRule.byBusiness, paid: false,
      cap: Cap.docDraft, after: AfterIssue.share, lines: true),
};

ComposerConfig configFor(DocKind kind) => composerTable[kind]!;

/// Kind of a tax-authority code; null when the app does not produce it (W).
DocKind? kindForCode(int code) {
  for (final c in composerTable.values) {
    if (c.code == code) return c.kind;
  }
  return null;
}

/// Kind of a server documentType ('TAX_INVOICE' → taxInvoice).
DocKind? kindForServerType(String type) {
  for (final c in composerTable.values) {
    if (c.serverType == type) return c.kind;
  }
  return null;
}

/// עוסק פטור / עמותה: no VAT component anywhere (§4.7).
bool isVatExemptBusiness(String businessType) =>
    businessType == 'OSEK_PATUR' || businessType == 'NONPROFIT';

/// Server types that record money received (a payment is attached on issue).
bool isPaidServerType(String type) {
  final k = kindForServerType(type);
  return k != null && configFor(k).paid;
}

/// Whether [kind] carries VAT for [businessType] (330: decided by the source).
bool kindHasVat(DocKind kind, String businessType) => switch (configFor(kind).vat) {
      VatRule.always => true,
      VatRule.never => false,
      VatRule.byBusiness || VatRule.fromSource => !isVatExemptBusiness(businessType),
    };

/// Line VAT rate in basis points.
int taxRateFor(DocKind kind, String businessType, int vatBasisPoints) =>
    kindHasVat(kind, businessType) ? vatBasisPoints : 0;

/// [kind] can be produced by this business at all.
bool kindAllowedFor(DocKind kind, String businessType, {bool section46 = false}) {
  final c = configFor(kind);
  if (c.vatBusinessesOnly && isVatExemptBusiness(businessType)) return false;
  if (c.nonprofitOnly && businessType != 'NONPROFIT') return false;
  if (c.needsSection46 && !section46) return false;
  return true;
}

/// [kind] is offered to a user with [caps] (the server is still the gate).
/// 320 stays available without docIssue: it ends in "שלח לאישור" (§8.1).
bool kindAllowedForCaps(DocKind kind, Caps caps, {bool supplierPicker = false}) {
  final c = configFor(kind);
  if (!caps.can(Cap.docDraft) && c.cap != Cap.paymentRecord) return false;
  if (c.cap == Cap.docIssue) return caps.can(Cap.docDraft);
  if (c.counterparty == Counterparty.supplier) {
    return supplierPicker && caps.can(Cap.supplierManage);
  }
  return caps.can(c.cap);
}

/// S1 "עוד סוגים" and the S3 type list: the flat list of ≤6 kinds allowed to
/// the business (§6 S1), in the spec order. Quotes and 330 are never here.
List<DocKind> moreKinds(String businessType, Caps caps,
    {bool section46 = false, bool supplierPicker = false}) {
  const order = [
    DocKind.taxInvoice,
    DocKind.taxInvoiceReceipt,
    DocKind.transactionInvoice,
    DocKind.receipt,
    DocKind.donationReceipt,
    DocKind.salesOrder,
    DocKind.purchaseOrder,
  ];
  return [
    for (final k in order)
      if (kindAllowedFor(k, businessType, section46: section46) &&
          kindAllowedForCaps(k, caps, supplierPicker: supplierPicker))
        k
  ];
}

/// F8 / §7: the due date from the customer's payment terms (BE-09 codes),
/// 'YYYY-MM-DD'. שוטף = the end of the issue month; שוטף+N = that + N days;
/// מיידי = the issue date. Unknown / none → שוטף+30 (§7 default).
String dueDateForTerms(String? terms, DateTime issueDate) {
  // Calendar arithmetic (DateTime(y, m, d + n)), never Duration: DST-safe.
  final eom = DateTime(issueDate.year, issueDate.month + 1, 0);
  DateTime plus(int days) => DateTime(eom.year, eom.month, eom.day + days);
  final due = switch (terms) {
    'IMMEDIATE' => DateTime(issueDate.year, issueDate.month, issueDate.day),
    'EOM' => eom,
    'EOM_45' => plus(45),
    'EOM_60' => plus(60),
    'EOM_90' => plus(90),
    _ => plus(30),
  };
  return '${due.year.toString().padLeft(4, '0')}-${due.month.toString().padLeft(2, '0')}-'
      '${due.day.toString().padLeft(2, '0')}';
}
