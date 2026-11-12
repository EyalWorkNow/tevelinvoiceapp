// R7 · "מספרי הקצאה חסרים": 305/320 of the last 12 months that needed an
// allocation number and have none. Existing endpoints only (no server change):
//   GET /customers                      → vatDealerStatus per customer
//   GET /documents?documentType=&issuedFrom=&minTotal=&limit=&offset=
//   GET /documents/:id/allocation       → state + allocationNumber (per row)
//   GET /documents/:id                  → only on a server without SHAAM
//                                          (NOT_EVALUATED): local evaluation
// Gap (docs/features/allocation-meter-he.md): the list rows carry neither the
// amount before VAT nor the allocation number, so each candidate costs one call.

import 'client.dart';
import 'customers_api.dart' show fetchCustomers;
import 'documents_api.dart';
import 'issue_api.dart' show todayIso;
import 'models/models.dart';
import '../util/allocation_meter.dart';

final _api = ApiClient.instance;

class MissingAllocation {
  const MissingAllocation(this.document, this.state, {this.local = false});

  final DocumentSummary document;

  /// Server allocation state (NOT_EVALUATED when [local]).
  final String state;

  /// Decided by the app's own threshold function (server without SHAAM).
  final bool local;
}

class AllocationScanResult {
  const AllocationScanResult({
    required this.missing,
    required this.checked,
    required this.partial,
  });

  final List<MissingAllocation> missing;

  /// Documents whose allocation state was looked at.
  final int checked;

  /// Not everything could be checked (row / candidate cap, or a failed call).
  final bool partial;
}

/// Customer statuses that can never make the obligation apply.
const Set<String> _notDealer = {
  'PRIVATE',
  'EXEMPT_DEALER',
  'NONPROFIT',
  'FOREIGN',
  'NON_DEDUCTOR',
};

const Set<String> _scanStatuses = {
  ...issuedStatuses,
  'ARTIFACT_PENDING',
  'WAITING_FOR_ALLOCATION',
};

/// 'YYYY-MM-DD' twelve months before [now].
String scanFromIso(DateTime now) =>
    todayIso(DateTime(now.year - 1, now.month, now.day));

/// Rows worth asking the server about (pure, tested): issued, not voided,
/// a threshold in effect on the issue date, total (≥ amount before VAT) above
/// it, and a customer that is not known to be a non-dealer.
List<DocumentSummary> allocationCandidates(
  List<DocumentSummary> rows,
  Map<String, String?> dealerByCustomer,
) => [
  for (final d in rows)
    if (_scanStatuses.contains(d.status) &&
        d.voidedAt == null &&
        !d.amountHidden &&
        allocationDocumentTypes.contains(d.documentType) &&
        d.issueDate != null &&
        thresholdOn(d.issueDate!) != null &&
        d.totalMinor > BigInt.from(thresholdOn(d.issueDate!)!.thresholdMinor) &&
        !_notDealer.contains(dealerByCustomer[d.customerId]))
      d,
];

Future<AllocationScanResult> scanMissingAllocations({
  DateTime? now,
  int maxRowsPerType = 2000,
  int maxCandidates = 200,
}) async {
  final from = scanFromIso(now ?? DateTime.now());
  final low = lowestThresholdSince(from);
  if (low == null) {
    return const AllocationScanResult(missing: [], checked: 0, partial: false);
  }
  var partial = false;
  final dealer = <String, String?>{};
  try {
    for (final c in await fetchCustomers()) {
      dealer[c.id] = c.vatDealerStatus;
    }
  } on ApiException {
    partial = true; // still correct: the server decides per document
  }

  final rows = <DocumentSummary>[];
  for (final type in allocationDocumentTypes) {
    var offset = 0;
    while (true) {
      final page = DocumentPage.fromJson(
        await fetchDocumentsJson(
          documentType: type,
          issuedFrom: from,
          minTotalMinor: BigInt.from(low + 1),
          limit: 500,
          offset: offset,
        ),
      );
      rows.addAll(page.documents);
      offset += page.documents.length;
      if (page.documents.isEmpty || offset >= page.total) break;
      if (offset >= maxRowsPerType) {
        partial = true;
        break;
      }
    }
  }

  var candidates = allocationCandidates(rows, dealer);
  if (candidates.length > maxCandidates) {
    candidates = candidates.sublist(0, maxCandidates);
    partial = true;
  }

  final missing = <MissingAllocation>[];
  var checked = 0;
  const batch = 4;
  for (var i = 0; i < candidates.length; i += batch) {
    final chunk = candidates.skip(i).take(batch);
    final found = await Future.wait(
      chunk.map((d) => _check(d, dealer[d.customerId])),
    );
    for (final f in found) {
      if (f == null) {
        partial = true;
        continue;
      }
      checked++;
      if (f.$1 != null) missing.add(f.$1!);
    }
  }
  missing.sort(
    (a, b) =>
        (b.document.issueDate ?? '').compareTo(a.document.issueDate ?? ''),
  );
  return AllocationScanResult(
    missing: missing,
    checked: checked,
    partial: partial,
  );
}

/// (missing-or-null,) per document; null = the check failed.
Future<(MissingAllocation?,)?> _check(DocumentSummary d, String? dealer) async {
  try {
    final j = await _api.get('/documents/${d.id}/allocation');
    final state = j['state'] as String? ?? 'NOT_EVALUATED';
    final number = j['allocationNumber']?.toString();
    if (allocationMissing(state, number)) {
      return (MissingAllocation(d, state),);
    }
    if (state != 'NOT_EVALUATED' || j['evaluation'] != null) return (null,);
    // A server without SHAAM never evaluates: decide with the app's rules.
    final detail = await fetchDocument(d.id);
    if (detail.allocationNumber != null || detail.amountHidden) return (null,);
    final required = allocationRequired(
      documentType: detail.documentType,
      customerVatDealerStatus: dealer,
      amountBeforeVatMinor: detail.subtotalMinor,
      vatMinor: detail.taxTotalMinor,
      issueDate: detail.issueDate ?? '',
    );
    return (required ? MissingAllocation(d, state, local: true) : null,);
  } on ApiException {
    return null;
  }
}
