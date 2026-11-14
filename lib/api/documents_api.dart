// Read side of documents (home squad): dashboard, list, detail, PDF bytes,
// plus deleting a draft from S6. Pure helpers at the bottom are unit-tested.

import 'package:flutter/foundation.dart';

import 'client.dart';
import 'models/models.dart';

final _api = ApiClient.instance;

/// Bumped by any screen that issues / pays / cancels / deletes a document, so
/// the home feed refreshes silently. Call [notifyDocumentsChanged].
final ValueNotifier<int> documentsVersion = ValueNotifier(0);
void notifyDocumentsChanged() => documentsVersion.value++;

/// GET /documents → `{total, documents}`. The server returns at most 100 rows.
class DocumentPage {
  const DocumentPage(this.total, this.documents);

  factory DocumentPage.fromJson(Map<String, dynamic> json) =>
      DocumentPage((json['total'] as num?)?.toInt() ?? 0, [
        for (final d in (json['documents'] as List? ?? const []))
          DocumentSummary.fromJson(d as Map<String, dynamic>),
      ]);

  final int total;
  final List<DocumentSummary> documents;

  /// More documents exist than the server returned (100-row cap).
  bool get capped => total > documents.length;
}

Future<Map<String, dynamic>> fetchDashboardJson() => _api.get('/dashboard');

/// GET /documents with the server filters the app uses.
Future<Map<String, dynamic>> fetchDocumentsJson({
  bool unpaid = false,
  String? issuedFrom,
  String? documentNumber,
  String? customerId,
}) {
  return _api.get(
    '/documents',
    query: {
      if (unpaid) 'unpaid': '1',
      'issuedFrom': ?issuedFrom,
      'documentNumber': ?documentNumber,
      'customerId': ?customerId,
    },
  );
}

Future<DocumentPage> fetchDocuments({
  bool unpaid = false,
  String? issuedFrom,
  String? documentNumber,
  String? customerId,
}) async => DocumentPage.fromJson(
  await fetchDocumentsJson(
    unpaid: unpaid,
    issuedFrom: issuedFrom,
    documentNumber: documentNumber,
    customerId: customerId,
  ),
);

Future<DocumentDetail> fetchDocument(String id) async =>
    DocumentDetail.fromJson(await _api.get('/documents/$id'));

/// The document's customer (there is no GET /customers/:id; the list is small).
Future<Customer?> fetchDocumentCustomer(String id) async {
  final json = await _api.get('/customers');
  for (final c in (json['customers'] as List? ?? const [])) {
    final customer = Customer.fromJson(c as Map<String, dynamic>);
    if (customer.id == id) return customer;
  }
  return null;
}

/// ORIGINAL PDF bytes. A finalized document without a stored original
/// (404 ARTIFACT_REQUIRED) gets it generated once with POST /artifact.
Future<Uint8List> fetchDocumentPdf(
  String id, {
  bool createIfMissing = true,
}) async {
  try {
    return await _api.getBytes('/documents/$id/pdf');
  } on ApiException catch (e) {
    if (!createIfMissing || e.code != 'ARTIFACT_REQUIRED') rethrow;
    await _api.post('/documents/$id/artifact');
    notifyDocumentsChanged(); // status FINALIZED → ARCHIVED
    return _api.getBytes('/documents/$id/pdf');
  }
}

/// DELETE /documents/:id (drafts only).
Future<void> deleteDraft(String id) async {
  await _api.delete('/documents/$id');
  notifyDocumentsChanged();
}

// ---- pure helpers ---------------------------------------------------------

/// Types that carry a real balance (the server also reports balance_minor on
/// receipts and credit notes, equal to their total — not "unpaid").
const Set<String> invoiceTypes = {
  'TRANSACTION_INVOICE',
  'TAX_INVOICE',
  'TAX_INVOICE_RECEIPT',
};

const Set<String> receiptTypes = {
  'RECEIPT',
  'DONATION_RECEIPT',
  'TAX_INVOICE_RECEIPT',
};

/// Statuses after a successful finalize (numbered documents).
const Set<String> issuedStatuses = {'FINALIZED', 'ARCHIVED', 'SIGNED', 'SENT'};

bool isDraftStatus(String status) => status == 'DRAFT' || status == 'REJECTED';

/// Balance only where it means "left to pay": issued invoice types.
/// Elsewhere (receipts, credit notes, drafts) it becomes null, so tiles show
/// no paid/open colour.
DocumentSummary withMeaningfulBalance(DocumentSummary d) {
  if (invoiceTypes.contains(d.documentType) && !isDraftStatus(d.status)) {
    return d;
  }
  return DocumentSummary(
    id: d.id,
    documentType: d.documentType,
    status: d.status,
    documentNumber: d.documentNumber,
    customerId: d.customerId,
    customerName: d.customerName,
    issueDate: d.issueDate,
    currency: d.currency,
    totalMinor: d.totalMinor,
  );
}

/// Same rule for the detail screen: the balance to show, or null.
BigInt? meaningfulBalance(DocumentDetail d) =>
    invoiceTypes.contains(d.documentType) && !d.isDraft ? d.balanceMinor : null;

/// Unpaid invoices (from GET /documents?unpaid=1).
List<DocumentSummary> unpaidInvoices(List<DocumentSummary> docs) => [
  for (final d in docs)
    if (invoiceTypes.contains(d.documentType) &&
        (d.balanceMinor ?? BigInt.zero) > BigInt.zero)
      d,
];

/// Month income from this month's documents, by business type:
/// VAT businesses (accrual) count invoices minus credit notes; exempt
/// businesses (OSEK_PATUR / NONPROFIT, cash basis) count receipts.
/// Returns (amount, document count).
(BigInt, int) monthIncome(
  List<DocumentSummary> monthDocs, {
  required bool vatExempt,
}) {
  var sum = BigInt.zero;
  var count = 0;
  for (final d in monthDocs) {
    if (!issuedStatuses.contains(d.status)) continue;
    final t = d.documentType;
    if (vatExempt
        ? (t == 'RECEIPT' || t == 'DONATION_RECEIPT')
        : invoiceTypes.contains(t)) {
      sum += d.totalMinor;
      count++;
    } else if (t == 'CREDIT_DOCUMENT') {
      sum -= d.totalMinor.abs();
      count++;
    }
  }
  return (sum, count);
}

/// First day of [now]'s month as 'YYYY-MM-01'.
String monthStartIso(DateTime now) =>
    '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-01';

enum DocFilter { all, unpaid, invoices, receipts }

/// Expanded list: chip filter + search by customer name or document number.
/// [unpaid] is the GET /documents?unpaid=1 list (used for [DocFilter.unpaid]).
List<DocumentSummary> filterDocuments(
  List<DocumentSummary> all,
  List<DocumentSummary> unpaid,
  DocFilter filter,
  String query,
) {
  final base = switch (filter) {
    DocFilter.all => all,
    DocFilter.unpaid => unpaidInvoices(unpaid),
    DocFilter.invoices => [
      for (final d in all)
        if (invoiceTypes.contains(d.documentType) ||
            d.documentType == 'CREDIT_DOCUMENT')
          d,
    ],
    DocFilter.receipts => [
      for (final d in all)
        if (receiptTypes.contains(d.documentType)) d,
    ],
  };
  final q = query.trim();
  if (q.isEmpty) return base;
  final lower = q.toLowerCase();
  return [
    for (final d in base)
      if ((d.customerName ?? '').toLowerCase().contains(lower) ||
          (d.documentNumber ?? '').startsWith(q))
        d,
  ];
}

/// '1000000' micros → '1', '2500000' → '2.5'.
String formatQuantity(BigInt micros) {
  final million = BigInt.from(1000000);
  final whole = micros ~/ million;
  final frac = (micros % million).abs();
  if (frac == BigInt.zero) return whole.toString();
  final digits = frac
      .toString()
      .padLeft(6, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return '$whole.$digits';
}
