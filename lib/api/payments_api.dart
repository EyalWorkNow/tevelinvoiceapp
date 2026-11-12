// S5 · payments on an open document (squad C) — SPEC-v2 §6 S5, §8.2.2, §9.
//
// For each payment: POST /payments [Idempotency-Key] → POST
// /documents/:id/payments {paymentId, amountMinor}. Then, for 300/305, ONE
// POST /receipts {scopeKey, paymentIds:[{id},…], forDocumentId, customerId}
// [Idempotency-Key] → the receipt's original (+ signing release, as in C).
// A 320 already is a receipt: its payments are only allocated.
//
// Every finished step is saved (AppCache "pending_payments_<docId>", never
// purged), so a retry — also after the app was killed — re-sends the SAME
// keys and money received once is recorded once:
// * a payment that exists keeps its recorded body (amount) whatever S5 now says;
// * a changed body on a key the server already used → IDEMPOTENCY_CONFLICT →
//   the earlier bodies are replayed (same key → the same paymentId);
// * a lost allocation response is detected by the document's paid total.

import 'dart:convert';

import '../state/cache.dart';
import '../util/labels/document_he.dart';
import 'client.dart';
import 'documents_api.dart' show fetchDocument, notifyDocumentsChanged;
import 'models/models.dart';
import 'signing_api.dart';

final _api = ApiClient.instance;

/// Runs [call]; a P1 money code the shared Hebrew table (errors_he, INT) does
/// not know yet gets its text from [DocumentHe.serverErrors].
Future<T> withMoneyErrors<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on ApiException catch (e) {
    final he = DocumentHe.serverErrors[e.code];
    if (he == null) rethrow;
    throw ApiException(e.status, e.code, he, serverMessage: e.serverMessage);
  }
}

/// A payment on 305/300 gets a receipt; on 320 it is only allocated.
bool paymentNeedsReceipt(String documentType) =>
    documentType == 'TAX_INVOICE' || documentType == 'TRANSACTION_INVOICE';

const Set<String> _payable = {
  'TRANSACTION_INVOICE',
  'TAX_INVOICE',
  'TAX_INVOICE_RECEIPT',
};
const Set<String> _issued = {'FINALIZED', 'SIGNED', 'ARCHIVED', 'SENT'};

/// S5 is offered on an issued 300/305/320 with an open balance.
bool canRecordPaymentOn(DocumentDetail doc) =>
    _payable.contains(doc.documentType) &&
    _issued.contains(doc.status) &&
    doc.voidedAt == null &&
    doc.balanceMinor > BigInt.zero;

class PaymentsOutcome {
  const PaymentsOutcome({
    required this.paymentIds,
    this.receiptId,
    this.receiptStatus,
    this.receiptNumber,
    this.signingPending = false,
  });

  final List<String> paymentIds;

  /// The new receipt (300/305 only).
  final String? receiptId;

  /// FINALIZED | … (as POST /receipts outcome.status).
  final String? receiptStatus;
  final String? receiptNumber;

  /// The receipt waits for the signing release (user cancelled Face ID).
  final bool signingPending;
}

String _cacheName(String documentId) => 'pending_payments_$documentId';

/// True when an earlier S5 on [documentId] stopped half-way.
Future<bool> hasPendingPayments(String documentId) async =>
    await AppCache.read(_cacheName(documentId)) is Map<String, dynamic>;

/// Records [entries] on [doc] (see the file header). [askPassphrase] is used
/// when the receipt's signing is locked; without it the receipt is left
/// "ממתין לחתימה" ([PaymentsOutcome.signingPending]).
Future<PaymentsOutcome> recordPayments(
  DocumentDetail doc,
  List<PaymentEntry> entries, {
  PassphrasePrompt? askPassphrase,
}) => withMoneyErrors(
  () => _recordPayments(doc, entries, askPassphrase: askPassphrase),
);

Future<PaymentsOutcome> _recordPayments(
  DocumentDetail doc,
  List<PaymentEntry> entries, {
  PassphrasePrompt? askPassphrase,
}) async {
  final name = _cacheName(doc.id);
  final saved = await AppCache.read(name);
  final p = saved is Map<String, dynamic>
      ? saved
      : <String, dynamic>{
          'receiptKey': ApiClient.newIdempotencyKey(),
          'slots': <Object>[],
        };
  Future<void> save() => AppCache.write(name, p);
  final old = [
    for (final s in (p['slots'] as List? ?? const []))
      Map<String, dynamic>.from(s as Map),
  ];
  // Slots that never reached the server follow the current input; recorded
  // payments stay whatever S5 says now.
  final slots = [
    for (var i = 0; i < old.length; i++)
      if (i < entries.length || old[i]['paymentId'] != null) old[i],
  ];
  p['slots'] = slots;
  for (var i = 0; i < entries.length; i++) {
    if (i >= slots.length) slots.add({'key': ApiClient.newIdempotencyKey()});
  }
  p['paidBefore'] ??= doc.paidTotalMinor.toString();
  await save();

  // 1. POST /payments for every slot.
  for (var i = 0; i < slots.length; i++) {
    final s = slots[i];
    if (s['paymentId'] != null) continue;
    final body = entries[i].toJson();
    final tried = [...(s['tried'] as List? ?? const [])];
    if (!tried.any((b) => jsonEncode(b) == jsonEncode(body))) tried.add(body);
    s['tried'] = tried;
    await save(); // before the call: a lost response still leaves this body on record
    Map<String, dynamic>? json;
    try {
      json = await _api.post('/payments', body, s['key'] as String);
      s['body'] = body;
    } on ApiException catch (e) {
      if (e.code != 'IDEMPOTENCY_CONFLICT') rethrow;
      for (final b in tried) {
        if (jsonEncode(b) == jsonEncode(body)) continue;
        try {
          json = await _api.post('/payments', b, s['key'] as String);
          s['body'] = b;
          break;
        } on ApiException catch (e2) {
          if (e2.code != 'IDEMPOTENCY_CONFLICT') rethrow;
        }
      }
      if (json == null) rethrow;
    }
    s['paymentId'] = json['paymentId'];
    await save();
  }

  // 2. Allocate each to the document.
  var allocatedSum = BigInt.zero;
  final paidBefore = BigInt.parse(p['paidBefore'] as String);
  for (final s in slots) {
    final amount = BigInt.parse((s['body'] as Map)['amountMinor'] as String);
    allocatedSum += amount;
    if (s['allocated'] == true) continue;
    try {
      await _api.post('/documents/${doc.id}/payments', {
        'paymentId': s['paymentId'],
        'amountMinor': amount.toString(),
      });
    } on ApiException catch (e) {
      // A lost response of an allocation that did happen: the paid total
      // already includes this payment.
      if (e.code != 'PAYMENT_OVERALLOCATED' ||
          (await fetchDocument(doc.id)).paidTotalMinor <
              paidBefore + allocatedSum) {
        rethrow;
      }
    }
    s['allocated'] = true;
    await save();
  }
  final ids = [for (final s in slots) s['paymentId'] as String];

  // 3. One receipt for all of them (300/305).
  var signingPending = false;
  if (paymentNeedsReceipt(doc.documentType)) {
    if (p['receiptId'] == null) {
      final json = await _api.post('/receipts', {
        'paymentIds': [
          for (final id in ids) {'id': id},
        ],
        'scopeKey': doc.numberingScopeKey ?? 'default',
        'forDocumentId': doc.id,
        'customerId': ?doc.customerId,
      }, p['receiptKey'] as String);
      final outcome = json['outcome'] as Map<String, dynamic>? ?? const {};
      p['receiptId'] = json['receiptDocumentId'];
      p['receiptStatus'] = outcome['status'];
      p['receiptNumber'] = outcome['documentNumber']?.toString();
      await save();
    }
    if (p['receiptStatus'] == 'FINALIZED' && p['receiptArtifact'] != true) {
      final id = p['receiptId'] as String;
      if (askPassphrase != null) {
        signingPending = !await issueSignedOriginal(
          id,
          askPassphrase: askPassphrase,
        );
      } else {
        signingPending =
            await createOriginalArtifact(id) == ArtifactSigning.locked;
      }
      p['receiptArtifact'] =
          true; // sealed; a pending signature is D row 6 of the receipt
      await save();
    }
  }
  await AppCache.remove(name);
  notifyDocumentsChanged();
  return PaymentsOutcome(
    paymentIds: ids,
    receiptId: p['receiptId'] as String?,
    receiptStatus: p['receiptStatus'] as String?,
    receiptNumber: p['receiptNumber'] as String?,
    signingPending: signingPending,
  );
}

/// Forgets a half-done S5 (only when nothing reached the server).
Future<void> discardPendingPayments(String documentId) async {
  final saved = await AppCache.read(_cacheName(documentId));
  if (saved is Map<String, dynamic> &&
      (saved['slots'] as List? ?? const []).any(
        (s) => (s as Map)['paymentId'] != null,
      )) {
    return; // money already recorded: the next "רשום" must finish it
  }
  await AppCache.remove(_cacheName(documentId));
}

/// BE-11: GET /payments ledger, newest first (default 50 per page).
Future<PaymentPage> fetchPaymentsPage({
  String? from,
  String? to,
  String? method,
  int offset = 0,
  int limit = 50,
  bool includeVoided = false,
}) async {
  final json = await _api.get(
    '/payments',
    query: {
      'from': ?from,
      'to': ?to,
      'method': ?method,
      'offset': '$offset',
      'limit': '$limit',
      if (includeVoided) 'includeVoided': '1',
    },
  );
  final rows = [
    for (final r in (json['payments'] as List? ?? const []))
      PaymentRow.fromJson(r as Map<String, dynamic>),
  ];
  return PaymentPage(
    total: jInt(json['total'] ?? rows.length),
    offset: offset,
    rows: rows,
  );
}

/// BE-11 rows only (first page).
Future<List<PaymentRow>> fetchPayments({String? from, String? to}) async =>
    (await fetchPaymentsPage(from: from, to: to)).rows;

/// BE-11: POST /payments/:id/void {reason} → {id, voidedAt, reused}
/// (idempotent). `payment:record`. A payment inside a 320 or a receipt →
/// 409 PAYMENT_LOCKED_IN_DOCUMENT (the remedy is a credit / the computer).
Future<void> voidPayment(String paymentId, String reason) async {
  final r = reason.trim();
  if (r.isEmpty) throw ArgumentError.value(reason, 'reason', 'required');
  await withMoneyErrors(
    () => _api.post('/payments/$paymentId/void', {'reason': r}),
  );
  notifyDocumentsChanged();
}
