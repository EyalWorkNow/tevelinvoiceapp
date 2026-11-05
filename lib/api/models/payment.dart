// Payments (squad C · §6 S5, §9). POST /payments bodies; BE-11 adds the
// GET /payments history (P1) — [PaymentRow] reads it when present.

import 'json.dart';

/// One payment typed in S5. Money is BigInt agorot.
class PaymentEntry {
  const PaymentEntry({
    required this.method,
    required this.amountMinor,
    required this.paymentDate,
    this.reference,
    this.bankNumber,
    this.branchNumber,
    this.accountNumber,
  });

  /// CASH | BANK_TRANSFER | CREDIT_CARD | CHECK | DIRECT_DEBIT | OTHER
  final String method;
  final BigInt amountMinor;

  /// YYYY-MM-DD. For a cheque: the date on the cheque (§9.1).
  final String paymentDate;

  /// CHECK only: the cheque number (digits). Never written for
  /// "העברה / ביט" (§9.1: it is part of the idempotency hash).
  final String? reference;
  final String? bankNumber;
  final String? branchNumber;
  final String? accountNumber;

  bool get isCheck => method == 'CHECK';

  /// POST /payments body.
  Map<String, Object> toJson() => {
        'method': method,
        'amountMinor': amountMinor.toString(),
        'currency': 'ILS',
        'paymentDate': paymentDate,
        if (isCheck && reference != null && reference!.isNotEmpty) 'reference': reference!,
        if (isCheck && bankNumber != null && bankNumber!.isNotEmpty) 'bankNumber': bankNumber!,
        if (isCheck && branchNumber != null && branchNumber!.isNotEmpty) 'branchNumber': branchNumber!,
        if (isCheck && accountNumber != null && accountNumber!.isNotEmpty) 'accountNumber': accountNumber!,
      };

  PaymentEntry copyWith({
    String? method,
    BigInt? amountMinor,
    String? paymentDate,
    String? reference,
    String? bankNumber,
    String? branchNumber,
    String? accountNumber,
  }) =>
      PaymentEntry(
        method: method ?? this.method,
        amountMinor: amountMinor ?? this.amountMinor,
        paymentDate: paymentDate ?? this.paymentDate,
        reference: reference ?? this.reference,
        bankNumber: bankNumber ?? this.bankNumber,
        branchNumber: branchNumber ?? this.branchNumber,
        accountNumber: accountNumber ?? this.accountNumber,
      );

  /// §9.1 "+ צ'ק נוסף": same bank/branch/account, cheque number + 1, one
  /// month later (clamped to the month's last day).
  PaymentEntry nextCheck() {
    final n = int.tryParse(reference ?? '');
    final d = DateTime.tryParse(paymentDate);
    String? date;
    if (d != null) {
      final lastDay = DateTime(d.year, d.month + 2, 0).day;
      final next = DateTime(d.year, d.month + 1, d.day > lastDay ? lastDay : d.day);
      date = isoDay(next);
    }
    return PaymentEntry(
      method: 'CHECK',
      amountMinor: amountMinor,
      paymentDate: date ?? paymentDate,
      reference: n == null ? reference : (n + 1).toString().padLeft(reference!.length, '0'),
      bankNumber: bankNumber,
      branchNumber: branchNumber,
      accountNumber: accountNumber,
    );
  }
}

/// 'YYYY-MM-DD' of [d].
String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// BE-11 `GET /payments` ledger row. Every field but id/method/amount optional.
class PaymentRow {
  const PaymentRow({
    required this.id,
    required this.method,
    required this.amountMinor,
    this.paymentDate,
    this.reference,
    this.customerId,
    this.customerName,
    this.receiptDocumentId,
    this.receiptDocumentNumber,
    this.allocatedDocumentIds = const [],
    this.voidedAt,
    this.voidReason,
  });

  factory PaymentRow.fromJson(Map<String, dynamic> json) => PaymentRow(
        id: json['id'] as String,
        method: jStr(json['method']) ?? 'OTHER',
        amountMinor: jBig(jPick(json, ['amountMinor', 'amount_minor'])),
        paymentDate: jStr(jPick(json, ['paymentDate', 'payment_date'])),
        reference: jStr(json['reference']),
        customerId: jStr(json['customerId']),
        customerName: jStr(json['customerName']),
        receiptDocumentId: jStr(jPick(json, ['receiptDocumentId', 'receipt_document_id'])),
        receiptDocumentNumber: jStr(json['receiptDocumentNumber']),
        allocatedDocumentIds: [
          for (final a in (json['allocations'] as List? ?? const []))
            if (a is Map && a['documentId'] != null) a['documentId'].toString()
        ],
        voidedAt: jStr(jPick(json, ['voidedAt', 'voided_at'])),
        voidReason: jStr(json['voidReason']),
      );

  final String id;
  final String method;
  final BigInt amountMinor;
  final String? paymentDate;
  final String? reference;
  final String? customerId;
  final String? customerName;
  final String? receiptDocumentId;
  final String? receiptDocumentNumber;
  final List<String> allocatedDocumentIds;
  final String? voidedAt;
  final String? voidReason;

  bool get isVoided => voidedAt != null;

  /// BE-11: only a payment in no receipt can be voided (the server also
  /// refuses one allocated to an issued document → PAYMENT_LOCKED_IN_DOCUMENT).
  bool get mayVoid => !isVoided && receiptDocumentId == null;
}

/// One page of GET /payments.
class PaymentPage {
  const PaymentPage({required this.total, required this.offset, required this.rows});

  final int total;
  final int offset;
  final List<PaymentRow> rows;

  bool get hasMore => offset + rows.length < total;
}

// ---- GET /documents/:id V2 extras (BE-07, BE-11, BE-12) ----------------------
// The shared DocumentDetail (squad B) carries the V1/P0 fields; D reads these
// from the same JSON.

/// `payments[]` of a document: allocated to it, or covered by it (a receipt).
class DocPayment {
  const DocPayment({
    required this.id,
    required this.method,
    required this.amountMinor,
    this.allocatedMinor,
    this.paymentDate,
    this.reference,
    this.receiptDocumentId,
    this.voidedAt,
  });

  factory DocPayment.fromJson(Map<String, dynamic> j) => DocPayment(
        id: j['id'].toString(),
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

/// `linkedDocuments[]`. [relation] is what the OTHER document is to this one:
/// RECEIPT | CREDIT | CONVERTED_TO (it points here), RECEIPT_FOR | CREDIT_FOR |
/// CONVERTED_FROM (this one points there).
class DocLink {
  const DocLink({
    required this.id,
    required this.documentType,
    required this.relation,
    this.documentNumber,
    this.status,
    this.totalMinor,
  });

  factory DocLink.fromJson(Map<String, dynamic> j) => DocLink(
        id: j['id'].toString(),
        documentType: jStr(j['type']) ?? '',
        relation: jStr(j['relation']) ?? '',
        documentNumber: jStr(j['number']),
        status: jStr(j['status']),
        totalMinor: jBigOrNull(j['totalMinor']),
      );

  final String id;
  final String documentType;
  final String relation;
  final String? documentNumber;
  final String? status;
  final BigInt? totalMinor;
}

/// `timeline[]` (BE-12): the document's audit trail, oldest first.
class TimelineEvent {
  const TimelineEvent({required this.at, required this.event, this.byEmail, this.detail = const {}});

  factory TimelineEvent.fromJson(Map<String, dynamic> j) => TimelineEvent(
        at: jStr(j['at']) ?? '',
        event: jStr(j['event']) ?? '',
        byEmail: jStr(j['byEmail']),
        detail: jMap(j['detail']),
      );

  final String at;

  /// Raw audit type, e.g. document.finalized, document.shared, document.sent.
  final String event;
  final String? byEmail;
  final Map<String, dynamic> detail;
}

/// The V2 fields of GET /documents/:id that [DocumentDetail] does not carry.
class DocumentExtras {
  const DocumentExtras({
    this.payments = const [],
    this.linked = const [],
    this.timeline = const [],
    this.hasTimeline = false,
    this.notes,
    this.overdue,
    this.openMinor,
    this.convertedFromDocumentId,
  });

  factory DocumentExtras.fromJson(Map<String, dynamic> json) {
    final d = jMap(json['document']);
    List<T> list<T>(Object? v, T Function(Map<String, dynamic>) f) =>
        [for (final e in (v is List ? v : const [])) if (e is Map<String, dynamic>) f(e)];
    return DocumentExtras(
      payments: list(d['payments'], DocPayment.fromJson),
      linked: list(d['linkedDocuments'], DocLink.fromJson),
      timeline: list(d['timeline'], TimelineEvent.fromJson),
      hasTimeline: d['timeline'] is List,
      notes: jStr(d['notes']),
      overdue: d['overdue'] is bool ? d['overdue'] as bool : null,
      openMinor: jBigOrNull(d['open_minor']),
      convertedFromDocumentId: jStr(d['converted_from_document_id']),
    );
  }

  static const empty = DocumentExtras();

  final List<DocPayment> payments;
  final List<DocLink> linked;
  final List<TimelineEvent> timeline;

  /// The server sent `timeline` (BE-12 is live): [sentAt] is then exact.
  final bool hasTimeline;
  final String? notes;
  final bool? overdue;
  final BigInt? openMinor;
  final String? convertedFromDocumentId;

  static const _sentEvents = {'document.shared', 'document.sent'};

  /// First share link or e-mail (= BE-10a `sentAt`).
  String? get sentAt {
    for (final e in timeline) {
      if (_sentEvents.contains(e.event)) return e.at;
    }
    return null;
  }

  /// The customer opened the public page.
  String? get viewedAt {
    for (final e in timeline) {
      if (e.event == 'document.share_downloaded') return e.at;
    }
    return null;
  }

  /// A share link was made and not revoked after it ("בטל קישור" in S6).
  bool get hasLiveShareLink {
    var live = false;
    for (final e in timeline) {
      if (e.event == 'document.shared') live = true;
      if (e.event == 'document.share_revoked') live = false;
    }
    return live;
  }

  /// A document made FROM this one (100/300 → 305), finalized.
  DocLink? get convertedTo {
    for (final l in linked) {
      if (l.relation == 'CONVERTED_TO') return l;
    }
    return null;
  }

  List<DocPayment> get livePayments => [for (final p in payments) if (p.voidedAt == null) p];
}
