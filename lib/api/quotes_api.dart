// Quotes (SPEC-v2 §6.C, §6.D 11–15, §8.2.4). Owner: squad B; squad C imports
// it for D ("הפוך לחשבונית", "הלקוח דחה", "שלח שוב").
//
// Server: GET /quotes (V1 header rows, ≤200, totals WITHOUT VAT), POST
// /quotes/:id/status {to} (V1), and BE-06 (P1, v2/quotes.ts): POST /quotes
// (+ per-line taxRateBasisPoints, itemId), GET /quotes/:id {quote, lines},
// PUT /quotes/:id (DRAFT or SENT; SENT stays SENT), POST /quotes/:id/convert
// (per-line rates win; the body rate is a fallback), POST /quotes/:id/clone,
// GET /quotes/:id/pdf, POST /quotes/:id/share-link → {url: …/d/:token}.
// [fetchQuote] still falls back on the list row for a server without BE-06.

import 'dart:typed_data';

import 'client.dart';
import 'documents_api.dart' show notifyDocumentsChanged;
import 'models/models.dart';

final ApiClient _api = ApiClient.instance;

Future<List<Quote>> fetchQuotes() async {
  final json = await _api.get('/quotes');
  return [
    for (final q in (json['quotes'] as List? ?? const []))
      if (q is Map<String, dynamic>) Quote.fromJson(q),
  ];
}

/// GET /quotes/:id (BE-06); before BE-06 the header row from GET /quotes.
Future<Quote?> fetchQuote(String id) async {
  try {
    return Quote.fromJson(await _api.get('/quotes/$id'));
  } on ApiException catch (e) {
    if (e.isNetwork || (e.status != 404 && e.code != 'NOT_FOUND')) rethrow;
  }
  for (final q in await fetchQuotes()) {
    if (q.id == id) return q;
  }
  return null;
}

/// POST /quotes → id. [lines] carry NET unit prices (no VAT on quotes).
Future<String> createQuote({
  required String? customerId,
  required List<QuoteLine> lines,
  required String validUntil,
  String? notes,
}) async {
  final json = await _api.post('/quotes', {
    'customerId': customerId,
    'currency': 'ILS',
    'validUntil': validUntil,
    if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    'lines': [for (final l in lines) l.toJson()],
  });
  notifyDocumentsChanged();
  return json['id'] as String;
}

/// PUT /quotes/:id (BE-06): same body as [createQuote]. Allowed while DRAFT
/// or SENT; the status stays. Returns the status.
Future<String> updateQuote(
  String id, {
  required String? customerId,
  required List<QuoteLine> lines,
  required String validUntil,
  String? notes,
}) async {
  final json = await _api.put('/quotes/$id', {
    'customerId': customerId,
    'currency': 'ILS',
    'validUntil': validUntil,
    'notes': (notes ?? '').trim().isEmpty ? null : notes!.trim(),
    'lines': [for (final l in lines) l.toJson()],
  });
  notifyDocumentsChanged();
  return json['status'] as String? ?? 'DRAFT';
}

/// POST /quotes/:id/clone (BE-06) → the new DRAFT id (valid 14 days).
Future<String> cloneQuote(String id) async {
  final json = await _api.post('/quotes/$id/clone', const {});
  notifyDocumentsChanged();
  return json['id'] as String;
}

/// POST /quotes/:id/share-link (BE-06) → `/d/:token`; the customer gets the
/// same token on `/q/:token` (quote page + "אני מאשר/ת", BE-21). A converted
/// quote cannot be shared (409).
Future<String> createQuoteShareLink(String id) async {
  final json = await _api.post('/quotes/$id/share-link', const {});
  return quoteAcceptUrl(json['url'] as String);
}

/// `<origin>/d/<token>` → `<origin>/q/<token>` (API-MOBILE: share /q/ for quotes).
String quoteAcceptUrl(String url) =>
    url.replaceFirst(RegExp(r'/d/(?=[^/]+/?$)'), '/q/');

/// GET /quotes/:id/pdf (BE-06; rendered on demand, never stored).
Future<Uint8List> fetchQuotePdf(String id) => _api.getBytes('/quotes/$id/pdf');

/// POST /quotes/:id/status. The server field is `to` (spec §6.C wrote
/// `status`). A quote already there (lost response, double tap) is fine.
Future<void> setQuoteStatus(String id, String to) async {
  try {
    await _api.post('/quotes/$id/status', {'to': to});
  } on ApiException catch (e) {
    if (e.code != 'QUOTE_INVALID_TRANSITION') rethrow;
    final q = await fetchQuote(id);
    if (q?.status != to) rethrow;
  }
  notifyDocumentsChanged();
}

/// POST /quotes/:id/convert → the new DRAFT document id.
/// [documentType]: TAX_INVOICE (305) or, for exempt / nonprofit,
/// TRANSACTION_INVOICE (300); [taxRateBasisPoints]: the business rate (exempt 0).
/// A retry after a lost response returns the document the first call made.
Future<String> convertQuote(
  String id, {
  required String documentType,
  required int taxRateBasisPoints,
}) async {
  try {
    final json = await _api.post('/quotes/$id/convert', {
      'documentType': documentType,
      'taxRateBasisPoints': taxRateBasisPoints,
    });
    notifyDocumentsChanged();
    return json['documentId'] as String;
  } on ApiException catch (e) {
    if (e.code != 'QUOTE_INVALID_TRANSITION') rethrow;
    final done = (await fetchQuote(id))?.convertedDocumentId;
    if (done == null) rethrow;
    return done;
  }
}

/// "הפוך לחשבונית" (§6.D 11–13, AT-20/20b): DRAFT → convert; SENT → ACCEPTED
/// then convert (one tap, two calls); ACCEPTED → convert; CONVERTED → the
/// existing document.
Future<String> convertQuoteToInvoice(
  Quote quote, {
  required String documentType,
  required int taxRateBasisPoints,
}) async {
  if (quote.status == 'CONVERTED' && quote.convertedDocumentId != null) {
    return quote.convertedDocumentId!;
  }
  if (quote.status == 'SENT') await setQuoteStatus(quote.id, 'ACCEPTED');
  return convertQuote(
    quote.id,
    documentType: documentType,
    taxRateBasisPoints: taxRateBasisPoints,
  );
}
