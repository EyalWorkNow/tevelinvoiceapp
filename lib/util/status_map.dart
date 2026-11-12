// §15.5 status mapping (INT). The ONLY place that turns a server status +
// money fields into a list status. DS's StatusPill takes [DocStatus] /
// [QuoteListStatus] only (AT-91); labels live in labels/status_he.dart.
//
// | server status                         | extra condition                          | list status      |
// | DRAFT, VALIDATING, READY_TO_FINALIZE  | —                                        | draft            |
// | PENDING_APPROVAL                      | —                                        | pendingApproval  |
// | WAITING_FOR_ALLOCATION                | attribute waitingTaxAuthority            | pendingApproval  |
// | FINALIZED/ARTIFACT_PENDING/SIGNED/ARCHIVED/SENT (ARTIFACT_PENDING → attribute waitingSignature):
// |   300/305 voidedAt, or credited ≥ total                                        | cancelled        |
// |   300/305 open > 0, due date (or issue + 30) before today                     | overdue          |
// |   300/305 open > 0                                                            | awaitingPayment  |
// |   300/305 open == 0; 320; 400/405                                             | paid             |
// |   100/500 voidedAt                                                            | cancelled        |
// |   330, 100, 500, anything else                                                | issued           |
// | quote DRAFT/SENT/ACCEPTED/CONVERTED/REJECTED|EXPIRED → draft/withCustomer/accepted/converted/notRelevant |

/// F10 list statuses of invoice-family documents.
enum DocStatus {
  draft,
  pendingApproval,
  awaitingPayment,
  overdue,
  paid,
  cancelled,
  issued,
}

/// F10 quote statuses.
enum QuoteListStatus { draft, withCustomer, accepted, converted, notRelevant }

/// Shown next to the status, never instead of it.
enum DocAttribute { waitingTaxAuthority, waitingSignature, sent, viewed }

class DocListState {
  const DocListState(this.status, [this.attributes = const {}]);

  final DocStatus status;
  final Set<DocAttribute> attributes;

  @override
  String toString() => 'DocListState($status, $attributes)';
}

const Set<String> _draftStatuses = {
  'DRAFT',
  'VALIDATING',
  'READY_TO_FINALIZE',
  'REJECTED',
};
const Set<String> _collectionTypes = {
  'TRANSACTION_INVOICE',
  'TAX_INVOICE',
}; // 300, 305
const Set<String> _paidTypes = {
  'TAX_INVOICE_RECEIPT',
  'RECEIPT',
  'DONATION_RECEIPT',
}; // 320, 400, 405
const Set<String> _voidableNonTax = {
  'SALES_ORDER',
  'PURCHASE_ORDER',
}; // 100, 500

/// 300/305: documents that carry a balance to collect (§6.D rows 8–10).
bool isCollectionType(String documentType) =>
    _collectionTypes.contains(documentType);

/// Due date passed: [dueDate] if known, otherwise issue date + 30 days (until BE-07).
bool isOverdue({String? dueDate, String? issueDate, required DateTime today}) {
  var due = DateTime.tryParse(dueDate ?? '');
  if (due == null) {
    final issued = DateTime.tryParse(issueDate ?? '');
    if (issued == null) return false;
    due = DateTime(
      issued.year,
      issued.month,
      issued.day + 30,
    ); // calendar days (DST-safe)
  }
  final t = DateTime(today.year, today.month, today.day);
  return DateTime(due.year, due.month, due.day).isBefore(t);
}

/// §15.5. [openMinor] = BE-10a openMinor, else balanceMinor; null = unknown
/// (a 300/305 with an unknown balance shows "הופק", never a guess).
DocListState docListState({
  required String status,
  required String documentType,
  required BigInt totalMinor,
  BigInt? openMinor,
  BigInt? creditedMinor,
  String? voidedAt,
  String? dueDate,
  String? issueDate,
  String? sentAt,
  String? viewedAt,
  DateTime? today,
}) {
  final attrs = <DocAttribute>{
    if (sentAt != null) DocAttribute.sent,
    if (viewedAt != null) DocAttribute.viewed,
  };
  if (_draftStatuses.contains(status)) {
    return DocListState(DocStatus.draft, attrs);
  }
  if (status == 'PENDING_APPROVAL') {
    return DocListState(DocStatus.pendingApproval, attrs);
  }
  if (status == 'WAITING_FOR_ALLOCATION') {
    return DocListState(DocStatus.pendingApproval, {
      ...attrs,
      DocAttribute.waitingTaxAuthority,
    });
  }
  if (status == 'ARTIFACT_PENDING') attrs.add(DocAttribute.waitingSignature);

  if (isCollectionType(documentType)) {
    final credited = creditedMinor ?? BigInt.zero;
    if (voidedAt != null ||
        (totalMinor > BigInt.zero && credited >= totalMinor)) {
      return DocListState(DocStatus.cancelled, attrs);
    }
    if (openMinor == null) return DocListState(DocStatus.issued, attrs);
    if (openMinor > BigInt.zero) {
      final late = isOverdue(
        dueDate: dueDate,
        issueDate: issueDate,
        today: today ?? DateTime.now(),
      );
      return DocListState(
        late ? DocStatus.overdue : DocStatus.awaitingPayment,
        attrs,
      );
    }
    return DocListState(DocStatus.paid, attrs);
  }
  if (_paidTypes.contains(documentType)) {
    return DocListState(DocStatus.paid, attrs);
  }
  if (_voidableNonTax.contains(documentType) && voidedAt != null) {
    return DocListState(DocStatus.cancelled, attrs);
  }
  return DocListState(DocStatus.issued, attrs);
}

/// §15.5 quotes.
QuoteListStatus quoteListStatus(String status) => switch (status) {
  'SENT' => QuoteListStatus.withCustomer,
  'ACCEPTED' => QuoteListStatus.accepted,
  'CONVERTED' => QuoteListStatus.converted,
  'REJECTED' || 'EXPIRED' => QuoteListStatus.notRelevant,
  _ => QuoteListStatus.draft,
};
