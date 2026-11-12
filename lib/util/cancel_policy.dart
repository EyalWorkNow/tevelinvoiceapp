// §8.3 cancel policy by document type (squad C). One pure table; the server
// enforces the same rules (BE-03a credit source types, BE-36 void).
//
// | source              | S8 action                 | result                     | condition                  | exempt dealer |
// | 305 TAX_INVOICE     | "הפק זיכוי" (full/partial)| 330                        | doc.cancel; ≤ total−credited| n/a           |
// | 320 TAX_INVOICE_RECEIPT | "הפק זיכוי"           | 330, payment stays         | same                       | n/a           |
// | 300 TRANSACTION_INVOICE | "בטל מסמך" (BE-36)    | voidedAt                   | no payments                | same          |
// | 100 SALES_ORDER / 500 PURCHASE_ORDER | "בטל מסמך" | voidedAt                 | —                          | same          |
// | 400/405 receipts    | none (W: cancel on the computer)                                                  |
// | 330 credit          | none                                                                               |
// | quote               | none ("הלקוח דחה" in §6.D row 12)                                                 |

enum CancelAction {
  /// 330 credit note (305/320).
  credit,

  /// BE-36 void (300/100/500): no document, the source is marked cancelled.
  voidDocument,

  /// Not in the app.
  none,
}

const Set<String> _creditable = {'TAX_INVOICE', 'TAX_INVOICE_RECEIPT'};
const Set<String> _voidable = {
  'TRANSACTION_INVOICE',
  'SALES_ORDER',
  'PURCHASE_ORDER',
};
const Set<String> _issued = {
  'FINALIZED',
  'ARTIFACT_PENDING',
  'SIGNED',
  'ARCHIVED',
  'SENT',
};

/// The S8 action for a document type (ignores status and permissions).
/// An exempt dealer has no 305/320, so it never gets [CancelAction.credit]
/// (the server answers CREDIT_SOURCE_TYPE_INVALID).
CancelAction cancelActionFor(String documentType, {required bool vatExempt}) {
  if (_creditable.contains(documentType))
    return vatExempt ? CancelAction.none : CancelAction.credit;
  if (_voidable.contains(documentType)) return CancelAction.voidDocument;
  return CancelAction.none;
}

/// Facts of one document that the policy needs.
class CancelFacts {
  CancelFacts({
    required this.documentType,
    required this.status,
    required this.totalMinor,
    BigInt? creditedMinor,
    BigInt? paidMinor,
    this.voidedAt,
  }) : creditedMinor = creditedMinor ?? BigInt.zero,
       paidMinor = paidMinor ?? BigInt.zero;

  final String documentType;
  final String status;
  final BigInt totalMinor;
  final BigInt creditedMinor;

  /// Payments allocated to the document (paid_total_minor).
  final BigInt paidMinor;
  final String? voidedAt;

  /// What is left to credit (§8.3: amount ≤ total − credited).
  BigInt get creditableMinor {
    final left = totalMinor - creditedMinor;
    return left > BigInt.zero ? left : BigInt.zero;
  }
}

/// Whether "בטל / זכה" appears in D ⋯ (F5: hidden, never disabled).
/// [canCancel] = Cap.docCancel. [voidAvailable] = BE-36 void is deployed
/// (P1); without it only 305/320 show the item (§8.3 "P0").
bool showCancelItem(
  CancelFacts doc, {
  required bool canCancel,
  required bool vatExempt,
  bool voidAvailable = true,
}) {
  if (!canCancel || !_issued.contains(doc.status) || doc.voidedAt != null)
    return false;
  switch (cancelActionFor(doc.documentType, vatExempt: vatExempt)) {
    case CancelAction.credit:
      return doc.creditableMinor > BigInt.zero;
    case CancelAction.voidDocument:
      return voidAvailable;
    case CancelAction.none:
      return false;
  }
}

/// 300 with payments cannot be voided in the app (cancel the receipt on the
/// computer first). 100/500 carry no payments.
bool voidBlockedByPayments(CancelFacts doc) =>
    doc.documentType == 'TRANSACTION_INVOICE' && doc.paidMinor > BigInt.zero;

// ---- credit lines (§8.2.5) --------------------------------------------------

/// One source line, as much as the credit needs.
class CreditSourceLine {
  const CreditSourceLine({
    required this.description,
    required this.quantityMicros,
    required this.unitPriceMinor,
    required this.discountMinor,
    required this.taxRateBasisPoints,
    required this.totalMinor,
    this.itemId,
  });

  final String description;
  final BigInt quantityMicros;
  final BigInt unitPriceMinor;
  final BigInt discountMinor;
  final int taxRateBasisPoints;

  /// Line total including VAT.
  final BigInt totalMinor;
  final String? itemId;
}

/// Body lines for POST /documents/:id/credit.
///
/// * Full credit ([amountMinor] == total and nothing credited yet): the source
///   lines, each at its own VAT rate.
/// * Otherwise (partial, or the rest after an earlier credit): [amountMinor]
///   INCLUDING VAT is split between the source's VAT-rate groups in proportion
///   to the groups' totals; one line per group ("זיכוי חלקי לחשבונית N"); net =
///   round(part / (1 + rate)); the rounding remainder of the split goes to the
///   largest group. ₪200 of 1,000 + 18% → 169.49 + VAT 30.51.
List<Map<String, Object>> creditLines({
  required List<CreditSourceLine> source,
  required BigInt totalMinor,
  required BigInt alreadyCreditedMinor,
  required BigInt amountMinor,
  required String partialDescription,
}) {
  if (amountMinor <= BigInt.zero)
    throw ArgumentError.value(amountMinor, 'amountMinor');
  if (amountMinor == totalMinor && alreadyCreditedMinor == BigInt.zero) {
    return [
      for (final l in source)
        {
          'description': l.description,
          'quantityMicros': l.quantityMicros.toString(),
          'unitPriceMinor': l.unitPriceMinor.toString(),
          'discountMinor': l.discountMinor.toString(),
          'taxRateBasisPoints': l.taxRateBasisPoints,
          'itemId': ?l.itemId,
        },
    ];
  }
  // VAT-rate groups, in first-seen order.
  final groups = <int, BigInt>{};
  for (final l in source) {
    groups[l.taxRateBasisPoints] =
        (groups[l.taxRateBasisPoints] ?? BigInt.zero) + l.totalMinor;
  }
  final sum = groups.values.fold(BigInt.zero, (a, b) => a + b);
  if (groups.isEmpty || sum <= BigInt.zero) {
    groups
      ..clear()
      ..[0] = amountMinor;
  }
  final base = sum > BigInt.zero ? sum : amountMinor;
  final parts = <int, BigInt>{
    for (final e in groups.entries) e.key: amountMinor * e.value ~/ base,
  };
  final remainder =
      amountMinor - parts.values.fold(BigInt.zero, (a, b) => a + b);
  final largest = groups.entries
      .reduce((a, b) => b.value > a.value ? b : a)
      .key;
  parts[largest] = parts[largest]! + remainder;

  return [
    for (final e in parts.entries)
      if (e.value > BigInt.zero)
        {
          'description': partialDescription,
          'quantityMicros': '1000000',
          'unitPriceMinor': netOfVat(e.value, e.key).toString(),
          'discountMinor': '0',
          'taxRateBasisPoints': e.key,
        },
  ];
}

/// round(gross / (1 + rate)), half up, in agorot. 20000 @ 1800bp → 16949.
BigInt netOfVat(BigInt grossMinor, int rateBasisPoints) {
  final denominator = BigInt.from(10000 + rateBasisPoints);
  final scaled = grossMinor * BigInt.from(10000) * BigInt.two + denominator;
  return scaled ~/ (denominator * BigInt.two);
}

/// VAT on [netMinor] the way the server rounds a line (half up).
BigInt vatOn(BigInt netMinor, int rateBasisPoints) =>
    (netMinor * BigInt.from(rateBasisPoints) * BigInt.two +
        BigInt.from(10000)) ~/
    BigInt.from(20000);
