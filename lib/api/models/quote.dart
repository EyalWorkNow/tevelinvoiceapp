// Quotes (squad B). GET /quotes rows (camelCase, `totalMinor` WITHOUT VAT).
// BE-06 GET /quotes/:id → {quote:{…, netMinor, taxMinor, totalMinor (WITH
// VAT), hasLinesWithoutRate, sentAt}, lines:[…, taxRateBasisPoints, itemId]}.
// §6.C, §8.2.4.

import 'dart:convert';
import 'dart:typed_data';

import 'json.dart';

/// One quote line (BE-06; P0 keeps the lines only in the Composer's memory).
class QuoteLine {
  const QuoteLine({
    required this.description,
    required this.quantityMicros,
    required this.unitPriceMinor,
    this.discountMinor,
    this.taxRateBasisPoints,
    this.itemId,
    this.agreedTotalMinor,
  });

  factory QuoteLine.fromJson(Map<String, dynamic> j) => QuoteLine(
    description: jStr(j['description']) ?? '',
    quantityMicros:
        jBigOrNull(jPick(j, ['quantityMicros', 'quantity_micros'])) ??
        _quantityFromText(jStr(j['quantity'])),
    unitPriceMinor: jBig(jPick(j, ['unitPriceMinor', 'unit_price_minor'])),
    discountMinor: jBigOrNull(jPick(j, ['discountMinor', 'discount_minor'])),
    taxRateBasisPoints: jIntOrNull(
      jPick(j, ['taxRateBasisPoints', 'tax_rate_basis_points']),
    ),
    itemId: jStr(jPick(j, ['itemId', 'item_id'])),
    agreedTotalMinor: jBigOrNull(
      jPick(j, ['agreedTotalMinor', 'agreed_total_minor']),
    ),
  );

  final String description;
  final BigInt quantityMicros;

  /// Net unit price (quotes are stored without VAT).
  final BigInt unitPriceMinor;
  final BigInt? discountMinor;
  final int? taxRateBasisPoints;
  final String? itemId;

  /// Owner Q1: the VAT-included total the user typed (server
  /// `agreedTotalMinor`); null = the standard calculation.
  final BigInt? agreedTotalMinor;

  /// POST /quotes line body.
  Map<String, dynamic> toJson() => {
    'description': description,
    'quantityMicros': quantityMicros.toString(),
    'unitPriceMinor': unitPriceMinor.toString(),
    if (discountMinor != null && discountMinor! > BigInt.zero)
      'discountMinor': discountMinor.toString(),
    if (taxRateBasisPoints != null) 'taxRateBasisPoints': taxRateBasisPoints,
    if (itemId != null) 'itemId': itemId,
    if (agreedTotalMinor != null)
      'agreedTotalMinor': agreedTotalMinor.toString(),
  };
}

/// '1.000000' (numeric(18,6) text) → micros.
BigInt _quantityFromText(String? text) {
  if (text == null || text.isEmpty) return BigInt.from(1000000);
  final parts = text.split('.');
  final frac = (parts.length > 1 ? parts[1] : '')
      .padRight(6, '0')
      .substring(0, 6);
  return BigInt.parse(parts[0]) * BigInt.from(1000000) + BigInt.parse(frac);
}

/// GET /quotes row; GET /quotes/:id {quote, lines} after BE-06.
class Quote {
  const Quote({
    required this.id,
    required this.status,
    this.customerId,
    this.customerName,
    required this.totalMinor,
    this.currency = 'ILS',
    this.validUntil,
    this.notes,
    this.convertedDocumentId,
    this.createdAt,
    this.lines = const [],
    BigInt? netMinor,
    this.taxMinor,
    this.hasLinesWithoutRate = true,
    this.sentAt,
    this.detailed = false,
    this.amountHidden = false,
    this.quoteNumber,
    this.expired = false,
    this.signature,
  }) : netMinor = netMinor ?? totalMinor;

  factory Quote.fromJson(Map<String, dynamic> json) {
    final detailed = json['quote'] is Map<String, dynamic>;
    final q = detailed ? json['quote'] as Map<String, dynamic> : json;
    final rawTotal = jPick(q, ['totalMinor', 'total_minor']);
    final total = jBig(rawTotal);
    return Quote(
      id: q['id'] as String,
      status: jStr(q['status']) ?? 'DRAFT',
      customerId: jStr(jPick(q, ['customerId', 'customer_id'])),
      customerName: jStr(jPick(q, ['customerName', 'customer_name'])),
      totalMinor: total,
      netMinor: detailed ? jBigOrNull(q['netMinor']) ?? total : total,
      taxMinor: detailed ? jBigOrNull(q['taxMinor']) : null,
      hasLinesWithoutRate: detailed ? q['hasLinesWithoutRate'] == true : true,
      sentAt: jStr(q['sentAt']),
      detailed: detailed,
      amountHidden: rawTotal == null,
      currency: jStr(q['currency']) ?? 'ILS',
      validUntil: jStr(jPick(q, ['validUntil', 'valid_until'])),
      notes: jStr(q['notes']),
      convertedDocumentId: jStr(
        jPick(q, ['convertedDocumentId', 'converted_document_id']),
      ),
      createdAt: jStr(jPick(q, ['createdAt', 'created_at'])),
      quoteNumber: jStr(jPick(q, ['quoteNumber', 'quote_number'])),
      expired: q['expired'] == true,
      signature: QuoteSignature.tryParse(json['signature'] ?? q['signature']),
      lines: [
        for (final l in (json['lines'] as List? ?? const []))
          if (l is Map<String, dynamic>) QuoteLine.fromJson(l),
      ],
    );
  }

  final String id;

  /// DRAFT | SENT | ACCEPTED | REJECTED | EXPIRED | CONVERTED
  final String status;
  final String? customerId;
  final String? customerName;

  /// List row: the lines WITHOUT VAT (= [netMinor]). [detailed] (BE-06):
  /// WITH the VAT of the lines that carry a rate.
  final BigInt totalMinor;

  /// Σ net lines after discounts.
  final BigInt netMinor;

  /// BE-06 only; null on a list row.
  final BigInt? taxMinor;

  /// Some line has no rate (V1 quote): VAT is decided on convert — show net.
  final bool hasLinesWithoutRate;

  /// First share-link creation (BE-06).
  final String? sentAt;

  /// Parsed from GET /quotes/:id (lines and VAT totals are real).
  final bool detailed;

  /// BE-03: someone else's quote without `money:read` → every money field
  /// (totals and line prices) is null on the wire and parsed as 0. Show no
  /// amount; the Composer never edits it in place or copies its prices.
  final bool amountHidden;

  /// Running number per business (server 0107); null before it.
  final String? quoteNumber;

  /// DRAFT/SENT past [validUntil] (server, Israel calendar). The status stays.
  final bool expired;

  /// Editable in the Composer (BE-06: PUT while DRAFT or SENT).
  bool get editable => status == 'DRAFT' || status == 'SENT';

  /// Never shared: no link was ever made ([sentAt]) and still a draft —
  /// the only quote DELETE /quotes/:id accepts.
  bool get deletable => status == 'DRAFT' && sentAt == null;
  final String currency;
  final String? validUntil;
  final String? notes;
  final String? convertedDocumentId;
  final String? createdAt;

  /// Empty on a list row.
  final List<QuoteLine> lines;

  /// GET /quotes/:id "פרטי חתימה"; null on a list row or an older server.
  final QuoteSignature? signature;
}

/// GET /quotes/:id `signature`: who sent it, the hand-drawn and the PAdES
/// signatures, and the customer's acceptance.
class QuoteSignature {
  const QuoteSignature({
    this.sentByName,
    this.sentAt,
    this.handwritten = false,
    this.digital,
    this.acceptance,
  });

  static QuoteSignature? tryParse(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final sentBy = raw['sentBy'];
    final digital = raw['digital'];
    final acceptance = raw['acceptance'];
    return QuoteSignature(
      sentByName: sentBy is Map<String, dynamic>
          ? jStr(sentBy['fullName'])
          : null,
      sentAt: jStr(raw['sentAt']),
      handwritten: raw['handwritten'] == true,
      digital: digital is Map<String, dynamic>
          ? QuoteDigitalSignature(
              level: jStr(digital['level']) ?? 'SECURE',
              certSubject: jStr(digital['certSubject']),
              certSerial: jStr(digital['certSerial']),
              signedAt: jStr(digital['signedAt']),
            )
          : null,
      acceptance: acceptance is Map<String, dynamic>
          ? QuoteAcceptance(
              fullName: jStr(acceptance['fullName']) ?? '',
              acceptedAt: jStr(acceptance['acceptedAt']),
              drawnSignaturePng: _png(acceptance['drawnSignaturePngBase64']),
            )
          : null,
    );
  }

  static Uint8List? _png(Object? b64) {
    if (b64 is! String || b64.isEmpty) return null;
    try {
      final comma = b64.indexOf(',');
      final bytes = base64Decode(comma >= 0 ? b64.substring(comma + 1) : b64);
      return bytes.isEmpty ? null : bytes;
    } on FormatException {
      return null;
    }
  }

  final String? sentByName;
  final String? sentAt;

  /// The sender's hand-drawn signature is printed on the PDF.
  final bool handwritten;
  final QuoteDigitalSignature? digital;
  final QuoteAcceptance? acceptance;
}

class QuoteDigitalSignature {
  const QuoteDigitalSignature({
    required this.level,
    this.certSubject,
    this.certSerial,
    this.signedAt,
  });

  /// SECURE | CERTIFIED
  final String level;
  final String? certSubject;
  final String? certSerial;
  final String? signedAt;
}

class QuoteAcceptance {
  const QuoteAcceptance({
    required this.fullName,
    this.acceptedAt,
    this.drawnSignaturePng,
  });

  final String fullName;
  final String? acceptedAt;

  /// The signature the customer drew on the public page (PNG), if any.
  final Uint8List? drawnSignaturePng;
}
