// Everything the user decided in the Composer + the server-equivalent preview
// (SPEC-v2 §6.C, §8). Owner: squad B. The server recalculates on finalize;
// nothing here is final. No `if (type == …)`: differences come from
// [ComposerConfig] (composer_config.dart).

import 'package:flutter/foundation.dart';

import '../../api/issue_api.dart' show PaymentInput, todayIso;
import '../../api/models/models.dart';
import '../../util/composer_config.dart';
import '../../util/money.dart';
import '../../util/vat.dart';

/// One extra line (S3): description, quantity, unit price (as typed), the
/// catalog item it came from (BE-15) and its own "ללא מע״מ" (per-line VAT).
class ComposeLine {
  ComposeLine({
    this.description = '',
    this.quantityText = '1',
    this.priceText = '',
    this.itemId,
    this.vatNone = false,
  });

  factory ComposeLine.fromJson(Map<String, dynamic> j) => ComposeLine(
    description: j['description'] as String? ?? '',
    quantityText: j['quantityText'] as String? ?? '1',
    priceText: j['priceText'] as String? ?? '',
    itemId: j['itemId'] as String?,
    vatNone: j['vatNone'] == true,
  );

  String description;
  String quantityText;
  String priceText;
  String? itemId;

  /// Per-line VAT mode: this line at 0%.
  bool vatNone;

  BigInt? get quantityMicros => parseQuantityMicros(quantityText);
  BigInt? get priceMinor {
    final v = parseAmount(priceText);
    return v == null || v <= BigInt.zero ? null : v;
  }

  bool get isEmpty => description.trim().isEmpty && priceText.trim().isEmpty;
  bool get isValid =>
      description.trim().isNotEmpty &&
      quantityMicros != null &&
      priceMinor != null;

  Map<String, dynamic> toJson() => {
    'description': description,
    'quantityText': quantityText,
    'priceText': priceText,
    'itemId': itemId,
    'vatNone': vatNone,
  };
}

class ComposeState extends ChangeNotifier {
  ComposeState({
    required this.kind,
    required this.businessType,
    required this.vatBasisPoints,
  });

  DocKind kind;
  String businessType;
  int vatBasisPoints;

  Customer? customer;
  String amountText = '';

  /// The typed amounts include VAT (default, §6.C step 2).
  bool inclusive = true;
  String description = '';

  /// The user edited the description: choosing another customer keeps it.
  bool descriptionTouched = false;
  String method = 'CASH';
  String bankNumber = '';
  String branchNumber = '';
  String accountNumber = '';
  String checkNumber = '';
  final List<ComposeLine> extraLines = [];
  String discountText = '';

  /// S3 "מע״מ: ללא" (a VAT business issuing at 0%).
  bool vatNone = false;

  /// S3 "מע״מ: לפי שורה": each extra line has its own "ללא מע״מ".
  bool vatPerLine = false;

  /// BE-07 note printed on the document / quote (≤500).
  String notes = '';

  /// BE-09 payment terms of the customer (IMMEDIATE | EOM | EOM_30…; null =
  /// unknown → שוטף+30).
  String? customerTerms;

  /// A due date the user picked in S3 (or the draft's): wins over the terms
  /// and survives a customer change.
  String? pickedDueDate;

  /// BE-07 due date sent with collect kinds (305 / 300), 'YYYY-MM-DD'.
  String get dueDate =>
      pickedDueDate ?? dueDateForTerms(customerTerms, DateTime.now());
  bool requestAllocation = false;

  /// Quote "בתוקף עד" (+14 days).
  String validUntil = todayIso(DateTime.now().add(const Duration(days: 14)));

  /// 405: the donor's ID when the customer has none.
  String donorTaxId = '';

  void changed() => notifyListeners();

  ComposerConfig get config => configFor(kind);
  bool get showVat => kindHasVat(kind, businessType);
  int get taxRate => showVat && !vatNone ? vatBasisPoints : 0;
  bool get _grossInput => inclusive && taxRate > 0;

  /// Rate of an extra line (per-line mode can drop it to 0).
  int lineRate(ComposeLine l) => vatPerLine && l.vatNone ? 0 : taxRate;

  /// BE-07 rows (S3): a note on everything but a receipt; a due date only on
  /// documents that wait for money (305 / 300).
  bool get hasNotes => !config.receiptOnly;
  bool get hasDueDate => config.after == AfterIssue.collect;

  BigInt get amountMinor => keypadToAgorot(amountText);
  BigInt get discountInput => parseAmount(discountText) ?? BigInt.zero;
  List<ComposeLine> get usedExtraLines =>
      extraLines.where((l) => !l.isEmpty).toList();

  BigInt _net(BigInt typed, [int? rate]) {
    final r = rate ?? taxRate;
    return _grossInput && r > 0 ? splitGross(typed, r).netMinor : typed;
  }

  /// Net unit price of an extra line (what a catalog item stores).
  BigInt? lineNetPrice(ComposeLine l) =>
      l.priceMinor == null ? null : _net(l.priceMinor!, lineRate(l));

  /// Lines exactly as sent to POST /documents (net unit prices).
  List<Map<String, dynamic>> get requestLines {
    final rate = taxRate;
    final discount = _net(discountInput);
    return [
      if (amountMinor > BigInt.zero)
        {
          'description': mainDescription,
          'quantityMicros': oneQuantity.toString(),
          'unitPriceMinor': _net(amountMinor).toString(),
          if (discount > BigInt.zero) 'discountMinor': discount.toString(),
          'taxRateBasisPoints': rate,
        },
      for (final l in usedExtraLines)
        if (l.isValid)
          {
            'description': l.description.trim(),
            'quantityMicros': l.quantityMicros!.toString(),
            'unitPriceMinor': _net(l.priceMinor!, lineRate(l)).toString(),
            'taxRateBasisPoints': lineRate(l),
            if (l.itemId != null) 'itemId': l.itemId,
          },
    ];
  }

  String get mainDescription =>
      description.trim().isEmpty ? '' : description.trim();

  /// Local preview of the server totals (sum of calculateLine).
  LineAmounts get totals {
    var sum = LineAmounts.zero;
    for (final l in requestLines) {
      sum =
          sum +
          calculateLine(
            quantityMicros: BigInt.parse(l['quantityMicros'] as String),
            unitPriceMinor: BigInt.parse(l['unitPriceMinor'] as String),
            discountMinor: BigInt.tryParse(l['discountMinor'] as String? ?? ''),
            taxRateBasisPoints: l['taxRateBasisPoints'] as int,
          );
    }
    return sum;
  }

  BigInt get totalMinor => totals.totalMinor;

  /// The total discount comes off the main line: more than that line would
  /// make it negative (and the extra lines would silently pay for it).
  bool get discountValid =>
      discountInput <= BigInt.zero || _net(discountInput) <= _net(amountMinor);

  bool get checkValid =>
      method != 'CHECK' ||
      [
        bankNumber,
        branchNumber,
        accountNumber,
        checkNumber,
      ].every((v) => v.trim().isNotEmpty);

  bool get donorValid =>
      config.counterparty != Counterparty.donor ||
      (customer?.taxId?.isNotEmpty ?? false) ||
      donorTaxId.trim().isNotEmpty;

  /// The primary button exists (§6.C: amount 0 → no button).
  bool get ready =>
      totalMinor > BigInt.zero &&
      customer != null &&
      mainDescription.isNotEmpty &&
      usedExtraLines.every((l) => l.isValid) &&
      discountValid &&
      (!config.paid || checkValid) &&
      donorValid;

  bool get hasPhone => (customer?.phone ?? '').trim().isNotEmpty;

  /// POST /documents body.
  Map<String, dynamic> requestBody() => {
    'documentType': config.serverType,
    if (config.counterparty == Counterparty.supplier)
      'supplierId': customer?.id
    else
      'customerId': customer?.id,
    'currency': 'ILS',
    'fiscalContext': 'default',
    'issueDate': todayIso(),
    'lines': requestLines,
    // BE-07: absent keeps the stored value, null clears it.
    if (hasNotes) 'notes': notes.trim().isEmpty ? null : notes.trim(),
    if (hasDueDate) 'dueDate': dueDate,
  };

  /// Quote lines (net; the rate is applied on convert).
  List<QuoteLine> get quoteLines => [
    for (final l in requestLines)
      QuoteLine(
        description: l['description'] as String,
        quantityMicros: BigInt.parse(l['quantityMicros'] as String),
        unitPriceMinor: BigInt.parse(l['unitPriceMinor'] as String),
        discountMinor: BigInt.tryParse(l['discountMinor'] as String? ?? ''),
        taxRateBasisPoints: l['taxRateBasisPoints'] as int, // BE-06
        itemId: l['itemId'] as String?,
      ),
  ];

  PaymentInput? get payment => !config.paid
      ? null
      : PaymentInput(
          method: method,
          bankNumber: method == 'CHECK' ? bankNumber.trim() : null,
          branchNumber: method == 'CHECK' ? branchNumber.trim() : null,
          accountNumber: method == 'CHECK' ? accountNumber.trim() : null,
          checkNumber: method == 'CHECK' ? checkNumber.trim() : null,
        );

  /// Prefill from an existing document (duplicate, convert, draft, 300 → 305).
  /// Lines come in net: the amount is shown "לפני מע״מ" when it has VAT.
  void loadLines(List<DocumentLine> lines) {
    extraLines.clear();
    if (lines.isEmpty) return;
    inclusive = false;
    final first = lines.first;
    final firstIsUnit = first.quantityMicros == oneQuantity;
    if (firstIsUnit) {
      amountText = agorotToKeypadText(first.unitPriceMinor);
      description = first.description;
      discountText = first.discountMinor > BigInt.zero
          ? agorotToKeypadText(first.discountMinor)
          : '';
    }
    for (final l in firstIsUnit ? lines.skip(1) : lines) {
      extraLines.add(
        ComposeLine(
          description: l.description,
          quantityText: formatQuantity(l.quantityMicros),
          priceText: agorotToKeypadText(l.unitPriceMinor),
          itemId: l.itemId,
          vatNone: l.taxRateBasisPoints == 0,
        ),
      );
    }
    if (!firstIsUnit) description = first.description;
    vatNone = showVat && lines.every((l) => l.taxRateBasisPoints == 0);
    // Mixed rates (a line at 0% next to taxed ones) → per-line mode.
    vatPerLine =
        showVat && !vatNone && lines.any((l) => l.taxRateBasisPoints == 0);
    notifyListeners();
  }

  /// Quote lines (BE-06 GET /quotes/:id) → the same prefill as a document.
  void loadQuoteLines(List<QuoteLine> lines) => loadLines([
    for (var i = 0; i < lines.length; i++)
      DocumentLine(
        position: i + 1,
        itemId: lines[i].itemId,
        description: lines[i].description,
        quantityMicros: lines[i].quantityMicros,
        unitPriceMinor: lines[i].unitPriceMinor,
        discountMinor: lines[i].discountMinor ?? BigInt.zero,
        subtotalMinor: BigInt.zero,
        taxRateBasisPoints: lines[i].taxRateBasisPoints ?? vatBasisPoints,
        taxAmountMinor: BigInt.zero,
        totalMinor: BigInt.zero,
      ),
  ]);

  void setKind(DocKind next) {
    kind = next;
    if (!showVat) vatNone = false;
    notifyListeners();
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'customer': customer?.toJson(),
    'amountText': amountText,
    'inclusive': inclusive,
    'description': description,
    'method': method,
    'bankNumber': bankNumber,
    'branchNumber': branchNumber,
    'accountNumber': accountNumber,
    'checkNumber': checkNumber,
    'extraLines': [for (final l in extraLines) l.toJson()],
    'discountText': discountText,
    'vatNone': vatNone,
    'vatPerLine': vatPerLine,
    'notes': notes,
    'customerTerms': customerTerms,
    'pickedDueDate': pickedDueDate,
    'requestAllocation': requestAllocation,
    'validUntil': validUntil,
    'donorTaxId': donorTaxId,
  };

  void restore(Map<String, dynamic> j) {
    final k = j['kind'];
    for (final v in DocKind.values) {
      if (v.name == k) kind = v;
    }
    final c = j['customer'];
    customer = c is Map
        ? Customer.fromJson(Map<String, dynamic>.from(c))
        : null;
    amountText = j['amountText'] as String? ?? '';
    inclusive = j['inclusive'] != false;
    description = j['description'] as String? ?? '';
    method = j['method'] as String? ?? 'CASH';
    bankNumber = j['bankNumber'] as String? ?? '';
    branchNumber = j['branchNumber'] as String? ?? '';
    accountNumber = j['accountNumber'] as String? ?? '';
    checkNumber = j['checkNumber'] as String? ?? '';
    extraLines
      ..clear()
      ..addAll([
        for (final l in (j['extraLines'] as List? ?? const []))
          ComposeLine.fromJson(Map<String, dynamic>.from(l as Map)),
      ]);
    discountText = j['discountText'] as String? ?? '';
    vatNone = j['vatNone'] == true;
    vatPerLine = j['vatPerLine'] == true;
    notes = j['notes'] as String? ?? '';
    customerTerms = j['customerTerms'] as String?;
    pickedDueDate = j['pickedDueDate'] as String?;
    requestAllocation = j['requestAllocation'] == true;
    validUntil = j['validUntil'] as String? ?? validUntil;
    donorTaxId = j['donorTaxId'] as String? ?? '';
    notifyListeners();
  }
}
