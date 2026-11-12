// Document actions (squad C) — SPEC-v2 §6.D, S6, S8, §8.2–8.3, §4.8, §4.9.
// approve / reject, credit / void, allocation (retry / manual / decision /
// cancel), share (link, e-mail, PDF copy, consent), quote actions on D,
// duplicate. Payments live in payments_api.dart, signing in signing_api.dart.
//
// Money-moving calls (approve, credit) keep their Idempotency-Keys in AppCache
// per document, so a retry — even after the app was killed — re-sends the
// SAME key.

import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../state/cache.dart';
import '../util/cancel_policy.dart';
import '../util/labels/labels.dart';
import '../util/money.dart';
import 'client.dart';
import 'customers_api.dart' show fetchCustomerDetail, isMissingRoute;
import 'documents_api.dart' show fetchDocument, notifyDocumentsChanged;
import 'models/models.dart';
import 'payments_api.dart' show withMoneyErrors;
import 'quotes_api.dart' show convertQuoteToInvoice, quoteAcceptUrl;
import 'signing_api.dart';

export 'payments_api.dart'
    show canRecordPaymentOn, paymentNeedsReceipt, withMoneyErrors;
export 'quotes_api.dart' show fetchQuote, setQuoteStatus;

final _api = ApiClient.instance;

/// A refusal that a retry with the same key will never turn into success
/// (409 transition, 403, 422 …): the pending key file is dropped. Offline,
/// 5xx, 401 (log in again) and 429 keep it for the retry.
bool _permanent(ApiException e) =>
    !e.isNetwork &&
    e.status >= 400 &&
    e.status < 500 &&
    e.status != 401 &&
    e.status != 408 &&
    e.status != 429;

// ---- reads ----------------------------------------------------------------

/// Same reader as documents_api; kept under this name for D.
Future<DocumentDetail> fetchDocumentDetail(String id) => fetchDocument(id);

/// GET /documents/:id as raw JSON (D reads the BE-36/37 fields the shared
/// model does not carry, e.g. `cancelled`, `submitted_at`).
Future<Map<String, dynamic>> fetchDocumentJson(String id) =>
    _api.get('/documents/$id');

/// GET /customers/:id (BE-09; customers_api falls back on the list).
/// Null when the customer is gone.
Future<Customer?> fetchCustomerById(String id) async {
  try {
    return (await fetchCustomerDetail(id)).customer;
  } on ApiException catch (e) {
    if (e.isNetwork || (e.status != 404 && !isMissingRoute(e))) rethrow;
    return null;
  }
}

/// The list row of [doc] (BE-10a: `sentAt`, `cancelled`, `openMinor`), found
/// with the documentNumber filter. Null when the server has no such row.
Future<DocumentSummary?> fetchDocumentRow(DocumentDetail doc) async {
  if (doc.documentNumber == null) return null;
  final json = await _api.get(
    '/documents',
    query: {
      'documentNumber': doc.documentNumber!,
      'documentType': doc.documentType,
      'limit': '5',
    },
  );
  for (final r in json['documents'] as List? ?? const []) {
    final row = DocumentSummary.fromJson(r as Map<String, dynamic>);
    if (row.id == doc.id) return row;
  }
  return null;
}

/// The stored ORIGINAL PDF (the signed one when it exists).
Future<Uint8List> fetchOriginalPdf(String documentId) =>
    _api.getBytes('/documents/$documentId/pdf');

/// "PDF העתק נאמן למקור": POST /artifact?type=COPY, then GET /pdf?type=COPY.
/// A 404 on the read → create once and retry once (§6.D edge).
Future<Uint8List> fetchCopyPdf(String documentId) async {
  Future<Uint8List> read() =>
      _api.getBytes('/documents/$documentId/pdf', query: {'type': 'COPY'});
  try {
    return await read();
  } on ApiException catch (e) {
    if (e.status != 404) rethrow;
  }
  await _api.post('/documents/$documentId/artifact?type=COPY');
  return read();
}

// ---- original artifact + share link ----------------------------------------

/// Share-link / send / credit need the stored original. A FINALIZED document
/// without one gets it now (POST /artifact); later statuses already have it.
Future<void> ensureOriginal(DocumentDetail doc) async {
  if (doc.status == 'FINALIZED') await createOriginalArtifact(doc.id);
}

/// POST /documents/:id/share-link → public URL (`/d/<token>`, 30 days).
/// Creates the original first when the server says it is missing.
Future<String> createShareLink(DocumentDetail doc) async {
  await ensureOriginal(doc);
  Map<String, dynamic> json;
  try {
    json = await _api.post('/documents/${doc.id}/share-link');
  } on ApiException catch (e) {
    if (e.code != 'ARTIFACT_REQUIRED' || doc.isDraft) rethrow;
    await createOriginalArtifact(doc.id);
    json = await _api.post('/documents/${doc.id}/share-link');
  }
  notifyDocumentsChanged(); // sentAt (BE-10a) counts the first share link
  return json['url'] as String;
}

/// BE-12 (P1): POST /documents/:id/share-link/revoke → {revoked: n}. Every
/// public link of the document stops working.
Future<void> revokeShareLink(String documentId) async {
  await _api.post('/documents/$documentId/share-link/revoke');
  notifyDocumentsChanged();
}

// ---- e-mail (S6, §6.6 of API-MOBILE) ------------------------------------------

/// POST /documents/:id/send → deliveryId. Throws CONSENT_REQUIRED (409) when
/// the customer must agree to computerized documents first.
Future<String> sendDocumentEmail(
  String documentId,
  String recipient, {
  String? paymentUrl,
}) async {
  final json = await _api.post('/documents/$documentId/send', {
    'recipient': recipient,
    if (paymentUrl != null && paymentUrl.isNotEmpty) 'paymentUrl': paymentUrl,
  });
  return json['deliveryId'] as String;
}

/// POST /deliveries/:id/process → SENT | RETRY_SCHEDULED | FAILED.
/// Idempotent: safe after the server worker already sent it.
Future<String> processDelivery(String deliveryId) async {
  final json = await _api.post('/deliveries/$deliveryId/process');
  return json['status'] as String? ?? 'FAILED';
}

/// The owner confirms the customer agreed (S6 CONSENT_REQUIRED dialog).
Future<void> recordConsent(String customerId) =>
    _api.post('/customers/$customerId/consent', {'method': 'VERBAL_IN_APP'});

// ---- approvals (§4.8, BE-37) ---------------------------------------------------

/// Result of "אשר והפק".
class ApproveOutcome {
  const ApproveOutcome({
    required this.status,
    this.documentNumber,
    this.signingPending = false,
  });

  /// FINALIZED | WAITING_FOR_ALLOCATION
  final String status;
  final String? documentNumber;

  /// Issued but the signature waits (Face ID cancelled) — D row 6.
  final bool signingPending;
}

/// POST /documents/:id/approve [Idempotency-Key] → original (+ signing).
/// The key is kept per document until the original exists.
Future<ApproveOutcome> approveDocument(
  DocumentDetail doc, {
  required PassphrasePrompt askPassphrase,
}) async {
  final name = 'pending_approve_${doc.id}';
  final saved = await AppCache.read(name);
  final p = saved is Map<String, dynamic>
      ? saved
      : <String, dynamic>{'key': ApiClient.newIdempotencyKey()};
  Future<void> save() => AppCache.write(name, p);
  await save();
  if (p['status'] == null) {
    final Map<String, dynamic> json;
    try {
      json = await _api.post('/documents/${doc.id}/approve', {
        'scopeKey': doc.numberingScopeKey ?? 'default',
      }, p['key'] as String);
    } on ApiException catch (e) {
      if (_permanent(e)) await AppCache.remove(name);
      rethrow;
    }
    p['status'] = json['status'];
    p['documentNumber'] = json['documentNumber']?.toString();
    await save();
  }
  var signingPending = false;
  if (p['status'] == 'FINALIZED') {
    signingPending = !await issueSignedOriginal(
      doc.id,
      askPassphrase: askPassphrase,
    );
  }
  await AppCache.remove(name);
  notifyDocumentsChanged();
  return ApproveOutcome(
    status: p['status'] as String,
    documentNumber: p['documentNumber'] as String?,
    signingPending: signingPending,
  );
}

/// POST /documents/:id/reject {reason} (reason required, §4.8).
Future<void> rejectDocument(String documentId, String reason) async {
  final r = reason.trim();
  if (r.isEmpty) throw ArgumentError.value(reason, 'reason', 'required');
  await _api.post('/documents/$documentId/reject', {'reason': r});
  notifyDocumentsChanged();
}

// ---- credit / void (S8, §8.3) ---------------------------------------------------

class CreditOutcome {
  const CreditOutcome({
    this.creditId,
    this.status,
    this.documentNumber,
    this.signingPending = false,
  });

  final String? creditId;

  /// FINALIZED | WAITING_FOR_ALLOCATION (the credit's D then shows row 4).
  final String? status;
  final String? documentNumber;
  final bool signingPending;
}

/// The original lines as [CreditSourceLine]s.
List<CreditSourceLine> creditSourceOf(DocumentDetail doc) => [
  for (final l in doc.lines)
    CreditSourceLine(
      description: l.description,
      quantityMicros: l.quantityMicros,
      unitPriceMinor: l.unitPriceMinor,
      discountMinor: l.discountMinor,
      taxRateBasisPoints: l.taxRateBasisPoints,
      totalMinor: l.totalMinor,
      itemId: l.itemId,
    ),
];

/// The most that can still be credited: total − credited (§8.3).
BigInt creditableOf(DocumentDetail doc) {
  final left = doc.totalMinor - (doc.creditedMinor ?? BigInt.zero);
  return left > BigInt.zero ? left : BigInt.zero;
}

/// Thrown when the server refused the amount (CREDIT_LIMIT_EXCEEDED);
/// [maxMinor] = what can still be credited, re-read from the server.
class CreditLimitExceeded implements Exception {
  const CreditLimitExceeded(this.maxMinor);
  final BigInt maxMinor;

  @override
  String toString() => 'CreditLimitExceeded(max $maxMinor)';
}

/// POST /documents/:id/credit [Idempotency-Key] {scopeKey, lines} → the credit
/// note's original (+ signing). [amountMinor] INCLUDES VAT; a full first
/// credit copies the source lines, anything else is split by VAT group
/// (§8.2.5, [creditLines]).
///
/// ONE Idempotency-Key per document until the credit is known, whatever the
/// amount: a lost response followed by a retry with another amount must not
/// become a second credit. The server hashes the credit's own (new) draft, so
/// any reuse of a key that already produced a credit answers
/// IDEMPOTENCY_CONFLICT (409) and rolls back — that answer means "the first
/// credit landed": the key is dropped and the outcome has no [creditId]
/// (D reloads and lists the credit under its linked documents).
Future<CreditOutcome> creditDocument(
  DocumentDetail doc, {
  required BigInt amountMinor,
  required PassphrasePrompt askPassphrase,
}) async {
  final name = 'pending_credit_${doc.id}';
  final saved = await AppCache.read(name);
  final p = saved is Map<String, dynamic> && saved['key'] is String
      ? saved
      : <String, dynamic>{'key': ApiClient.newIdempotencyKey()};
  Future<void> save() => AppCache.write(name, p);

  if (p['creditId'] == null) {
    p['amount'] = amountMinor.toString();
    await save(); // before the call: a lost response keeps the key
    final Map<String, dynamic> json;
    try {
      json = await _api.post('/documents/${doc.id}/credit', {
        'scopeKey': doc.numberingScopeKey ?? 'default',
        'lines': creditLines(
          source: creditSourceOf(doc),
          totalMinor: doc.totalMinor,
          alreadyCreditedMinor: doc.creditedMinor ?? BigInt.zero,
          amountMinor: amountMinor,
          partialDescription: DocumentHe.partialCreditLine(doc.documentNumber),
        ),
      }, p['key'] as String);
    } on ApiException catch (e) {
      if (e.code == 'CREDIT_LIMIT_EXCEEDED') {
        await AppCache.remove(name);
        throw CreditLimitExceeded(creditableOf(await fetchDocument(doc.id)));
      }
      if (e.code == 'IDEMPOTENCY_CONFLICT') {
        await AppCache.remove(name);
        notifyDocumentsChanged();
        return const CreditOutcome();
      }
      if (_permanent(e)) await AppCache.remove(name);
      rethrow;
    }
    final outcome = json['outcome'] as Map<String, dynamic>? ?? const {};
    p['creditId'] = json['creditDocumentId'];
    p['status'] = outcome['status'];
    p['documentNumber'] = outcome['documentNumber']?.toString();
    await save();
  }
  var signingPending = false;
  if (p['status'] == 'FINALIZED') {
    signingPending = !await issueSignedOriginal(
      p['creditId'] as String,
      askPassphrase: askPassphrase,
    );
  }
  await AppCache.remove(name);
  notifyDocumentsChanged();
  return CreditOutcome(
    creditId: p['creditId'] as String?,
    status: p['status'] as String?,
    documentNumber: p['documentNumber'] as String?,
    signingPending: signingPending,
  );
}

/// BE-36 (P1): POST /documents/:id/void {reason} (required, ≤500) → {id,
/// voidedAt}. Finalized 300 without payments, 100, 500 (`document:cancel`).
/// Errors: DOCUMENT_HAS_PAYMENTS 409, DOCUMENT_VOID_NOT_ALLOWED 422,
/// DOCUMENT_ALREADY_VOIDED 409 (a lost response: treated as done).
Future<void> voidDocument(String documentId, String reason) async {
  try {
    await withMoneyErrors(
      () => _api.post('/documents/$documentId/void', {'reason': reason.trim()}),
    );
  } on ApiException catch (e) {
    if (e.code != 'DOCUMENT_ALREADY_VOIDED') rethrow;
  }
  notifyDocumentsChanged();
}

// ---- allocation number (§6.D row 4, §4.9) ----------------------------------------

/// GET /documents/:id/allocation (the part D needs).
class AllocationState {
  const AllocationState({
    required this.state,
    this.labelHe,
    this.allocationNumber,
    this.detailHe,
    this.serviceNoticeHe,
    this.nextAutoRetryAt,
  });

  factory AllocationState.fromJson(Map<String, dynamic> j) {
    final degradation = j['degradation'] as Map<String, dynamic>?;
    return AllocationState(
      state: j['state'] as String? ?? 'NOT_EVALUATED',
      labelHe: j['labelHe'] as String?,
      allocationNumber: j['allocationNumber']?.toString(),
      detailHe:
          (j['evaluation'] as Map<String, dynamic>?)?['detailHe'] as String? ??
          j['userFacingHe'] as String?,
      serviceNoticeHe: degradation?['noticeHe'] as String?,
      nextAutoRetryAt: DateTime.tryParse(
        degradation?['nextAutoRetryAt'] as String? ?? '',
      ),
    );
  }

  final String state;
  final String? labelHe;
  final String? allocationNumber;
  final String? detailHe;

  /// ADR-SHAAM-DEGRADATION: calm notice while the Tax Authority is unavailable (or the
  /// automatic retries ran out). Informational — the document waits, nothing is lost.
  final String? serviceNoticeHe;

  /// When the server's worker will try again on its own (null = not scheduled).
  final DateTime? nextAutoRetryAt;

  /// "המשך בלי מספר" is allowed only here (server: recordAllocationDecision).
  bool get decisionAllowed =>
      state == 'USER_ACTION_REQUIRED' || state == 'HEARING_PENDING';

  /// The tax-authority connection is missing (P0: "המשך במחשב").
  bool get needsAuthorization => state == 'AUTHORIZATION_REQUIRED';
  bool get inFlight => state == 'REQUESTING' || state == 'OUTCOME_UNKNOWN';
}

Future<AllocationState> fetchAllocationState(String documentId) async =>
    AllocationState.fromJson(
      await _api.get('/documents/$documentId/allocation'),
    );

/// "נסה שוב": reconcile an in-flight request, otherwise request again.
/// While the Tax Authority is down the server fails fast (SHAAM_SERVICE_UNAVAILABLE) without
/// touching the document; that is not an error of this document — the refreshed state carries
/// the calm notice and the worker retries on its own.
Future<AllocationState> retryAllocation(String documentId) async {
  final now = await fetchAllocationState(documentId);
  final action = now.inFlight ? 'reconcile' : 'request';
  try {
    await _api.post('/documents/$documentId/allocation/$action', const {});
  } on ApiException catch (e) {
    if (e.code != 'SHAAM_SERVICE_UNAVAILABLE') rethrow;
  }
  notifyDocumentsChanged();
  return fetchAllocationState(documentId);
}

/// "הזן מספר ידנית" (only with /me.shaam.manualEntryEnabled).
Future<void> attachManualAllocation(String documentId, String number) async {
  await _api.post('/documents/$documentId/allocation/manual', {
    'allocationNumber': number.trim(),
  });
  notifyDocumentsChanged();
}

/// "המשך בלי מספר" (only when [AllocationState.decisionAllowed]).
Future<void> continueWithoutAllocation(String documentId) async {
  await _api.post('/documents/$documentId/allocation/decision', {
    'decision': 'CONTINUE',
  });
  notifyDocumentsChanged();
}

/// "בטל בקשה" (BE-26, P1): POST /documents/:id/allocation/cancel → the
/// document is READY_TO_FINALIZE again (D row 3). With Israel Invoices live
/// the number is reserved at lock time → 409 ALLOCATION_NUMBER_RESERVED, shown
/// in Hebrew ("המשך בלי מספר" / "נסה שוב" stay on the ⋯).
Future<void> cancelAllocationRequest(String documentId) async {
  await withMoneyErrors(
    () => _api.post('/documents/$documentId/allocation/cancel', const {}),
  );
  notifyDocumentsChanged();
}

// ---- quotes on D (§6.D rows 11–15, §8.2.4) -----------------------------------------

/// "הפוך לחשבונית" — one tap, up to two calls (§8.2.4): SENT → ACCEPTED, then
/// POST /quotes/:id/convert {documentType, taxRateBasisPoints}. 305 for VAT
/// businesses, 300 (rate 0) for exempt / nonprofit. BE-06: each line keeps its
/// own rate; [vatRateBasisPoints] is the fallback for lines without one.
/// Returns the new draft id (C opens it prefilled).
Future<String> quoteToInvoice(
  Quote quote, {
  required bool vatExempt,
  required int vatRateBasisPoints,
}) async {
  final id = await convertQuoteToInvoice(
    quote,
    documentType: vatExempt ? 'TRANSACTION_INVOICE' : 'TAX_INVOICE',
    taxRateBasisPoints: vatExempt ? 0 : vatRateBasisPoints,
  );
  notifyDocumentsChanged();
  return id;
}

/// BE-06: the quote PDF, rendered on demand (never an accounting artifact).
Future<Uint8List> quotePdfBytes(String quoteId) =>
    _api.getBytes('/quotes/$quoteId/pdf');

/// BE-06: POST /quotes/:id/share-link → `/d/<token>`, shared as `/q/<token>`
/// (the customer's accept page, same token).
Future<String> quoteShareUrl(String quoteId) async {
  final json = await _api.post('/quotes/$quoteId/share-link');
  return quoteAcceptUrl(json['url'] as String);
}

/// BE-06: POST /quotes/:id/clone → a new DRAFT quote (valid 14 days).
Future<String> duplicateQuote(String quoteId) async {
  final json = await _api.post('/quotes/$quoteId/clone');
  notifyDocumentsChanged();
  return json['id'] as String;
}

/// The quote has its full view (BE-06: lines from GET /quotes/:id).
bool quoteHasLines(Quote q) => q.lines.isNotEmpty;

// ---- duplicate (§8.2.9) -----------------------------------------------------------

/// "שכפל": BE-08 `POST /documents/:id/clone` when the server has it, else (P0)
/// a new draft with the same type, customer and lines, dated today. Returns
/// the new draft id.
Future<String> duplicateDocument(DocumentDetail doc) async {
  try {
    final json = await _api.post('/documents/${doc.id}/clone', const {});
    notifyDocumentsChanged();
    return json['id'] as String;
  } on ApiException catch (e) {
    if (!isMissingRoute(e)) {
      rethrow; // the route itself is missing (before BE-08)
    }
  }
  final json = await _api.post('/documents', {
    'documentType': doc.documentType,
    'customerId': ?doc.customerId,
    'currency': doc.currency,
    'fiscalContext': 'default',
    'lines': [
      for (final l in doc.lines)
        {
          'description': l.description,
          'quantityMicros': l.quantityMicros.toString(),
          'unitPriceMinor': l.unitPriceMinor.toString(),
          'discountMinor': l.discountMinor.toString(),
          'taxRateBasisPoints': l.taxRateBasisPoints,
          'itemId': ?l.itemId,
        },
    ],
  });
  notifyDocumentsChanged();
  return json['id'] as String;
}

/// "הפק חשבונית מס" from an order (100) or a transaction invoice (300 of a
/// VAT business, §8.2.3): BE-08 linked clone `{documentType: TAX_INVOICE,
/// link: true}`. The CONVERTED_FROM link is written when the new 305 is
/// finalized (it then clears TAX_INVOICE_DUE). Returns the draft id.
Future<String> issueTaxInvoiceFrom(String documentId) async {
  final json = await withMoneyErrors(
    () => _api.post('/documents/$documentId/clone', {
      'documentType': 'TAX_INVOICE',
      'link': true,
    }),
  );
  notifyDocumentsChanged();
  return json['id'] as String;
}

// ---- WhatsApp text (§13.5) ----------------------------------------------------------

/// V1 kept a user template in the Keychain (settings_api still reads these).
/// V2 §13.5: the text is FIXED in the app; [loadWhatsAppTemplate] stays for
/// the V1 settings code until squad E removes the template editor.
const waTemplateKey = 'wa_template';
const waTemplateStorage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);

/// §13.5 fixed wording.
const defaultWhatsAppTemplate =
    "שלום {שם}, מצורפת {סוג} מס' {מספר} על סך {סכום}. לצפייה ולתשלום: {קישור}. תודה, {עסק}";

/// V1 compatibility (settings); V2 screens use [whatsAppMessage].
Future<String> loadWhatsAppTemplate() async {
  String? text;
  try {
    text = await waTemplateStorage.read(key: waTemplateKey);
  } on Object {
    text = null;
  }
  return text != null && text.trim().isNotEmpty
      ? text
      : defaultWhatsAppTemplate;
}

/// Fills {שם} {סוג} {מספר} {סכום} {עסק} {קישור}. A template without {קישור}
/// gets the link on its own line; [paymentLinkUrl] with an open balance adds
/// "לתשלום: …" (V1 behaviour; the V2 /d/ page has its own pay button).
String buildWhatsAppMessage({
  String template = defaultWhatsAppTemplate,
  String? customerName,
  required String documentType,
  String? documentNumber,
  required BigInt totalMinor,
  required String businessName,
  required String link,
  BigInt? balanceMinor,
  String? paymentLinkUrl,
}) {
  final name = customerName?.trim() ?? '';
  var text = template
      .replaceAll(RegExp(r' ?\{שם\}'), name.isEmpty ? '' : ' $name')
      .replaceAll(
        " מס' {מספר}",
        documentNumber == null ? '' : " מס' $documentNumber",
      )
      .replaceAll('{סוג}', docTypeLabel(documentType))
      .replaceAll(' {מספר}', documentNumber == null ? '' : ' $documentNumber')
      .replaceAll('{מספר}', documentNumber ?? '')
      .replaceAll('{סכום}', formatMoney(totalMinor, trimZeroAgorot: true))
      .replaceAll('{עסק}', businessName);
  text = text.contains('{קישור}')
      ? text.replaceAll('{קישור}', link)
      : '$text\n$link';
  if (balanceMinor != null &&
      balanceMinor > BigInt.zero &&
      paymentLinkUrl != null &&
      paymentLinkUrl.isNotEmpty) {
    text = '$text\nלתשלום: $paymentLinkUrl';
  }
  return text.trim();
}

/// The fixed §13.5 message for a document.
String whatsAppMessage({
  String? customerName,
  required String documentType,
  String? documentNumber,
  required BigInt totalMinor,
  required String businessName,
  required String link,
}) => buildWhatsAppMessage(
  customerName: customerName,
  documentType: documentType,
  documentNumber: documentNumber,
  totalMinor: totalMinor,
  businessName: businessName,
  link: link,
);

/// Quote text (§8.2.4). P1 (BE-06): with [link] to the quote's page and PDF;
/// P0 (no link): header and amount only.
String quoteWhatsAppMessage({
  String? customerName,
  required BigInt totalMinor,
  String? validUntil,
  required String businessName,
  String? link,
}) {
  final name = customerName?.trim() ?? '';
  final until = validUntil == null
      ? ''
      : ', בתוקף עד ${formatDateHe(validUntil)}';
  final view = link == null ? '' : '. לצפייה: $link';
  return 'שלום${name.isEmpty ? '' : ' $name'}, הצעת מחיר על סך '
      '${formatMoney(totalMinor, trimZeroAgorot: true)}$until$view. תודה, $businessName';
}
