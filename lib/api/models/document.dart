// Documents (squad B; C reads). GET /documents rows, GET /documents/:id.
// BE-10a adds creditedMinor/openMinor/createdBy/submittedBy/sentAt; BE-37 adds
// rejection; BE-36 adds voidedAt; BE-07 adds dueDate + notes; BE-08 adds
// convertedFromDocumentId; BE-11 adds payments + linkedDocuments; BE-12 adds
// timeline. All optional here so the app runs against a server without them.

import 'json.dart';

/// Server document type name → Israeli tax-authority code (§8.1).
const Map<String, int> docTypeCodes = {
  'SALES_ORDER': 100,
  'TRANSACTION_INVOICE': 300,
  'TAX_INVOICE': 305,
  'TAX_INVOICE_RECEIPT': 320,
  'CREDIT_DOCUMENT': 330,
  'RECEIPT': 400,
  'DONATION_RECEIPT': 405,
  'PURCHASE_ORDER': 500,
};

/// BE-37 `rejection:{reason, by, at}`.
class Rejection {
  const Rejection({required this.reason, this.by, this.at});

  static Rejection? fromJsonOrNull(Object? v) {
    if (v is! Map<String, dynamic>) return null;
    return Rejection(
      reason: jStr(v['reason']) ?? '',
      by: jStr(v['by']),
      at: jStr(v['at']),
    );
  }

  final String reason;
  final String? by;
  final String? at;
}

/// A document row. GET /documents → {total, documents:[camelCase]};
/// also parses the snake_case dashboard `recent` rows.
class DocumentSummary {
  const DocumentSummary({
    required this.id,
    required this.documentType,
    required this.status,
    this.documentNumber,
    this.customerId,
    this.customerName,
    this.issueDate,
    this.dueDate,
    required this.currency,
    required this.totalMinor,
    this.balanceMinor,
    this.creditedMinor,
    this.openMinorRaw,
    this.createdBy,
    this.submittedBy,
    this.sentAt,
    this.voidedAt,
    this.rejection,
    this.notes,
    this.overdue,
    this.amountHidden = false,
  });

  factory DocumentSummary.fromJson(
    Map<String, dynamic> json,
  ) => DocumentSummary(
    id: json['id'] as String,
    documentType: jPick(json, ['documentType', 'document_type']) as String,
    status: json['status'] as String,
    documentNumber: jStr(jPick(json, ['documentNumber', 'document_number'])),
    customerId: jStr(jPick(json, ['customerId', 'customer_id'])),
    customerName: jStr(jPick(json, ['customerName', 'customer_name'])),
    issueDate: jStr(jPick(json, ['issueDate', 'issue_date'])),
    dueDate: jStr(jPick(json, ['dueDate', 'due_date'])),
    currency: jStr(json['currency']) ?? 'ILS',
    totalMinor: jBig(jPick(json, ['totalMinor', 'total_minor'])),
    amountHidden: jPick(json, ['totalMinor', 'total_minor']) == null,
    balanceMinor: jBigOrNull(jPick(json, ['balanceMinor', 'balance_minor'])),
    creditedMinor: jBigOrNull(jPick(json, ['creditedMinor', 'credited_minor'])),
    openMinorRaw: jBigOrNull(jPick(json, ['openMinor', 'open_minor'])),
    createdBy: jStr(jPick(json, ['createdBy', 'created_by'])),
    submittedBy: jStr(jPick(json, ['submittedBy', 'submitted_by'])),
    sentAt: jStr(jPick(json, ['sentAt', 'sent_at'])),
    voidedAt: jStr(jPick(json, ['voidedAt', 'voided_at'])),
    rejection: Rejection.fromJsonOrNull(json['rejection']),
    notes: jStr(json['notes']),
    overdue: json['overdue'] is bool ? json['overdue'] as bool : null,
  );

  final String id;
  final String documentType;
  final String status;
  final String? documentNumber;
  final String? customerId;
  final String? customerName;

  /// BE-07 note (≤500); BE-10 `overdue` (server: due date, else issue + 30).
  final String? notes;
  final bool? overdue;

  /// 'YYYY-MM-DD' (null for drafts without a date).
  final String? issueDate;
  final String? dueDate;
  final String currency;
  final BigInt totalMinor;

  /// The server redacted the amounts (read gating: no money:read and not the
  /// caller's own row). [totalMinor] is then a placeholder 0 — never show it.
  final bool amountHidden;

  /// Null when unknown (dashboard rows).
  final BigInt? balanceMinor;
  final BigInt? creditedMinor;

  /// Server `openMinor` (BE-10a). Use [openMinor], which falls back on balance.
  final BigInt? openMinorRaw;
  final String? createdBy;
  final String? submittedBy;
  final String? sentAt;
  final String? voidedAt;
  final Rejection? rejection;

  /// §15.5: openMinor from BE-10a, else balanceMinor.
  BigInt? get openMinor => openMinorRaw ?? balanceMinor;

  bool get isPaid => openMinor != null && openMinor == BigInt.zero;
  bool get isOpen => openMinor != null && openMinor! > BigInt.zero;

  Map<String, dynamic> toJson() => {
    'id': id,
    'documentType': documentType,
    'status': status,
    'documentNumber': documentNumber,
    'customerId': customerId,
    'customerName': customerName,
    'issueDate': issueDate,
    'dueDate': dueDate,
    'currency': currency,
    'totalMinor': amountHidden ? null : totalMinor.toString(),
    'balanceMinor': balanceMinor?.toString(),
    'creditedMinor': creditedMinor?.toString(),
    'openMinor': openMinorRaw?.toString(),
    'createdBy': createdBy,
    'submittedBy': submittedBy,
    'sentAt': sentAt,
    'voidedAt': voidedAt,
    if (rejection != null)
      'rejection': {
        'reason': rejection!.reason,
        'by': rejection!.by,
        'at': rejection!.at,
      },
  };
}

/// GET /documents/:id → {document, lines} (both snake_case).
class DocumentDetail {
  const DocumentDetail({
    required this.id,
    required this.documentType,
    required this.status,
    this.documentNumber,
    required this.currency,
    this.issueDate,
    this.dueDate,
    required this.subtotalMinor,
    required this.taxTotalMinor,
    required this.totalMinor,
    required this.paidTotalMinor,
    required this.balanceMinor,
    this.creditedMinor,
    this.allocationNumber,
    this.customerId,
    this.numberingScopeKey,
    this.createdBy,
    this.submittedBy,
    this.voidedAt,
    this.rejection,
    this.notes,
    this.supplierId,
    this.convertedFromDocumentId,
    this.overdue,
    this.payments = const [],
    this.linkedDocuments = const [],
    this.timeline = const [],
    required this.lines,
    this.amountHidden = false,
  });

  factory DocumentDetail.fromJson(Map<String, dynamic> json) {
    final d = json['document'] as Map<String, dynamic>;
    return DocumentDetail(
      id: d['id'] as String,
      documentType: d['document_type'] as String,
      status: d['status'] as String,
      documentNumber: jStr(d['document_number']),
      currency: jStr(d['currency']) ?? 'ILS',
      issueDate: jStr(d['issue_date']),
      dueDate: jStr(d['due_date']),
      subtotalMinor: jBig(d['subtotal_minor']),
      taxTotalMinor: jBig(d['tax_total_minor']),
      totalMinor: jBig(d['total_minor']),
      paidTotalMinor: jBig(d['paid_total_minor']),
      balanceMinor: jBig(d['balance_minor']),
      creditedMinor: jBigOrNull(d['credited_minor']),
      allocationNumber: jStr(d['allocation_number']),
      customerId: jStr(d['customer_id']),
      numberingScopeKey: jStr(d['numbering_scope_key']),
      createdBy: jStr(jPick(d, ['created_by', 'createdBy'])),
      submittedBy: jStr(jPick(json, ['submittedBy']) ?? d['submitted_by']),
      voidedAt: jStr(d['voided_at']),
      rejection: Rejection.fromJsonOrNull(json['rejection'] ?? d['rejection']),
      notes: jStr(d['notes']),
      supplierId: jStr(jPick(d, ['supplier_id', 'supplierId'])),
      convertedFromDocumentId: jStr(
        jPick(d, ['converted_from_document_id', 'convertedFromDocumentId']),
      ),
      overdue: d['overdue'] is bool ? d['overdue'] as bool : null,
      payments: [
        for (final p in (d['payments'] as List? ?? const []))
          if (p is Map<String, dynamic>) DocumentPaymentRef.fromJson(p),
      ],
      linkedDocuments: [
        for (final l in (d['linkedDocuments'] as List? ?? const []))
          if (l is Map<String, dynamic>) LinkedDocument.fromJson(l),
      ],
      timeline: [
        for (final t in (d['timeline'] as List? ?? const []))
          if (t is Map<String, dynamic>) TimelineEntry.fromJson(t),
      ],
      lines: [
        for (final l in (json['lines'] as List? ?? const []))
          DocumentLine.fromJson(l as Map<String, dynamic>),
      ],
      amountHidden: d['total_minor'] == null,
    );
  }

  /// BE-03: someone else's document without `money:read` → every money field
  /// (header and lines) is null on the wire and parsed as 0 here. Show no
  /// amount ('—'), and never copy these zeros into a new document.
  final bool amountHidden;

  final String id;
  final String documentType;
  final String status;
  final String? documentNumber;
  final String currency;
  final String? issueDate;
  final String? dueDate;
  final BigInt subtotalMinor;
  final BigInt taxTotalMinor;
  final BigInt totalMinor;
  final BigInt paidTotalMinor;
  final BigInt balanceMinor;
  final BigInt? creditedMinor;
  final String? allocationNumber;
  final String? customerId;
  final String? numberingScopeKey;
  final String? createdBy;
  final String? submittedBy;
  final String? voidedAt;
  final Rejection? rejection;

  /// BE-07 note printed on the document (≤500).
  final String? notes;

  /// 500 purchase order.
  final String? supplierId;

  /// BE-08: the source of a linked clone (300/100 → 305) until it is finalized.
  final String? convertedFromDocumentId;
  final bool? overdue;

  /// BE-11 payments allocated to this document.
  final List<DocumentPaymentRef> payments;

  /// BE-11 receipts / credits / conversions around this document.
  final List<LinkedDocument> linkedDocuments;

  /// BE-12 audit timeline (oldest first as the server sends it).
  final List<TimelineEntry> timeline;
  final List<DocumentLine> lines;

  /// §15.5 / BE-36: max(0, balance − credited) (balance already net after BE-36).
  BigInt get openMinor => balanceMinor;

  bool get isDraft => status == 'DRAFT' || status == 'REJECTED';

  /// Has a stored original PDF (share-link / send / credit need this).
  bool get hasOriginal =>
      status == 'ARCHIVED' || status == 'SENT' || status == 'SIGNED';
}

/// A document line (snake_case from GET /documents/:id).
class DocumentLine {
  const DocumentLine({
    required this.position,
    this.itemId,
    required this.description,
    required this.quantityMicros,
    required this.unitPriceMinor,
    required this.discountMinor,
    required this.subtotalMinor,
    required this.taxRateBasisPoints,
    required this.taxAmountMinor,
    required this.totalMinor,
  });

  factory DocumentLine.fromJson(Map<String, dynamic> json) => DocumentLine(
    position: jInt(json['position']),
    itemId: jStr(json['item_id']),
    description: jStr(json['description']) ?? '',
    quantityMicros: jBig(json['quantity_micros']),
    unitPriceMinor: jBig(json['unit_price_minor']),
    discountMinor: jBig(json['discount_minor']),
    subtotalMinor: jBig(json['subtotal_minor']),
    taxRateBasisPoints: jInt(json['tax_rate_basis_points'] ?? 0),
    taxAmountMinor: jBig(json['tax_amount_minor']),
    totalMinor: jBig(json['total_minor']),
  );

  final int position;
  final String? itemId;
  final String description;

  /// Quantity × 1,000,000 (1 unit = 1000000).
  final BigInt quantityMicros;
  final BigInt unitPriceMinor;
  final BigInt discountMinor;
  final BigInt subtotalMinor;
  final int taxRateBasisPoints;
  final BigInt taxAmountMinor;
  final BigInt totalMinor;
}

/// BE-11 `payments[]` of GET /documents/:id.
class DocumentPaymentRef {
  const DocumentPaymentRef({
    required this.id,
    required this.method,
    required this.amountMinor,
    this.allocatedMinor,
    this.paymentDate,
    this.reference,
    this.receiptDocumentId,
    this.voidedAt,
  });

  factory DocumentPaymentRef.fromJson(Map<String, dynamic> j) =>
      DocumentPaymentRef(
        id: jStr(j['id']) ?? '',
        method: jStr(j['method']) ?? 'OTHER',
        amountMinor: jBig(j['amountMinor']),
        allocatedMinor: jBigOrNull(j['allocatedMinor']),
        paymentDate: jStr(j['paymentDate']),
        reference: jStr(j['reference']),
        receiptDocumentId: jStr(j['receiptDocumentId']),
        voidedAt: jStr(j['voidedAt']),
      );

  final String id;
  final String method;
  final BigInt amountMinor;
  final BigInt? allocatedMinor;
  final String? paymentDate;
  final String? reference;
  final String? receiptDocumentId;
  final String? voidedAt;
}

/// BE-11 `linkedDocuments[]`. [relation] describes the OTHER document from
/// this one's point of view: RECEIPT | CREDIT | CONVERTED_TO (it points here)
/// or RECEIPT_FOR | CREDIT_FOR | CONVERTED_FROM (this one points there).
class LinkedDocument {
  const LinkedDocument({
    required this.id,
    required this.relation,
    this.type,
    this.number,
  });

  factory LinkedDocument.fromJson(Map<String, dynamic> j) => LinkedDocument(
    id: jStr(j['id']) ?? '',
    relation: jStr(j['relation']) ?? '',
    type: jStr(jPick(j, ['type', 'documentType'])),
    number: jStr(jPick(j, ['number', 'documentNumber'])),
  );

  final String id;
  final String relation;
  final String? type;
  final String? number;
}

/// BE-12 `timeline[]`: {at, event (raw audit type), by, byEmail, detail}.
class TimelineEntry {
  const TimelineEntry({
    required this.at,
    required this.event,
    this.by,
    this.byEmail,
    this.detail = const {},
  });

  factory TimelineEntry.fromJson(Map<String, dynamic> j) => TimelineEntry(
    at: jStr(j['at']) ?? '',
    event: jStr(j['event']) ?? '',
    by: jStr(j['by']),
    byEmail: jStr(j['byEmail']),
    detail: j['detail'] is Map<String, dynamic>
        ? j['detail'] as Map<String, dynamic>
        : const {},
  );

  final String at;
  final String event;
  final String? by;
  final String? byEmail;
  final Map<String, dynamic> detail;
}
