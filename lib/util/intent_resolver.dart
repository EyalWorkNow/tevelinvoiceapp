// Intent → document kind, and the Composer's one primary action
// (SPEC-v2 §4.7, §6.C, §8.1). Owner: squad B. Pure functions, unit-tested.
//
// | intent     | עוסק מורשה / חברה / שותפות | עוסק פטור / עמותה |
// | PAID       | 320                        | 400               |
// | REQUEST    | 305                        | 300               |
// | QUOTE      | quote                      | quote             |
// | TYPE:<code>| that code when the business may produce it (§8.1); else null |
//
// The user never picks or sees the type before issuing (F1); S3 can switch it.

import 'composer_config.dart';

const String intentPaid = 'PAID';
const String intentRequest = 'REQUEST';
const String intentQuote = 'QUOTE';

/// 'TYPE:305' etc.
String typeIntent(DocKind kind) =>
    kind == DocKind.quote ? intentQuote : 'TYPE:${configFor(kind).code}';

/// Opens the default invoice for this business without asking for a type first.
String invoiceIntentFor(String businessType) => typeIntent(
  isVatExemptBusiness(businessType)
      ? DocKind.transactionInvoice
      : DocKind.taxInvoice,
);

/// The kind the Composer opens with; null when the intent cannot be served
/// for this business (unknown, 330, 405 without §46, a VAT type for an exempt
/// business). [canRecordPayment] false + exempt PAID → 300, because a receipt
/// cannot go through approval: the document is submitted and the approver
/// records the payment later.
DocKind? resolveIntent(
  String intent,
  String businessType, {
  bool section46 = false,
  bool canRecordPayment = true,
}) {
  final exempt = isVatExemptBusiness(businessType);
  DocKind? kind;
  if (intent == intentPaid) {
    kind = exempt
        ? (canRecordPayment ? DocKind.receipt : DocKind.transactionInvoice)
        : DocKind.taxInvoiceReceipt;
  } else if (intent == intentRequest) {
    kind = exempt ? DocKind.transactionInvoice : DocKind.taxInvoice;
  } else if (intent == intentQuote) {
    kind = DocKind.quote;
  } else if (intent.startsWith('TYPE:')) {
    final code = int.tryParse(intent.substring(5));
    kind = code == null ? null : kindForCode(code);
  }
  if (kind == null || !configFor(kind).viaComposer) return null;
  return kindAllowedFor(kind, businessType, section46: section46) ? kind : null;
}

/// The Composer's primary button (§6.C step 4, first rule that holds).
enum ComposerAction {
  /// "שלח לאישור" + the line "מסמך מ-₪X כולל מע״מ דורש אישור".
  submit,

  /// "שלח הצעה בווטסאפ".
  sendQuoteWhatsApp,

  /// "שלח הצעה" → system share sheet (customer without a phone).
  sendQuote,

  /// "הפק ושלח בווטסאפ".
  issueAndWhatsApp,

  /// "הפק" → D, where S6 opens.
  issue,
}

ComposerAction resolveAction({
  required DocKind kind,
  required bool needsApproval,
  required bool hasPhone,
  required bool canSend,
}) {
  if (kind == DocKind.quote) {
    return hasPhone
        ? ComposerAction.sendQuoteWhatsApp
        : ComposerAction.sendQuote;
  }
  if (needsApproval) return ComposerAction.submit;
  if (hasPhone && canSend) return ComposerAction.issueAndWhatsApp;
  return ComposerAction.issue;
}

/// §4.8 + BE-37: receipts (400/405) never go to approval; quotes are never
/// finalized. Everything else asks the capability rule ([approvalNeeded] =
/// `Caps.approvalNeeded(total)`, `>=` on the total INCLUDING VAT).
bool kindNeedsApproval(DocKind kind, bool Function() approvalNeeded) {
  final c = configFor(kind);
  if (c.isQuote || c.receiptOnly) return false;
  return approvalNeeded();
}

/// Amounts from this total (INCLUDING VAT) get one confirmation dialog (§6.C).
final BigInt bigAmountConfirmMinor = BigInt.from(5000000);
