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
import '../../util/israel_date.dart' show israelToday, israelTodayDate;

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

/// C3 "פיצול תשלום": one payment line (method + amount; a cheque keeps its
/// details and its own date — a post-dated cheque).
class SplitLine {
  SplitLine({
    this.method = 'CASH',
    this.amountText = '',
    this.bankNumber = '',
    this.branchNumber = '',
    this.accountNumber = '',
    this.checkNumber = '',
    String? date,
  }) : date = date ?? todayIso();

  factory SplitLine.fromJson(Map<String, dynamic> j) => SplitLine(
    method: j['method'] as String? ?? 'CASH',
    amountText: j['amountText'] as String? ?? '',
    bankNumber: j['bankNumber'] as String? ?? '',
    branchNumber: j['branchNumber'] as String? ?? '',
    accountNumber: j['accountNumber'] as String? ?? '',
    checkNumber: j['checkNumber'] as String? ?? '',
    date: j['date'] as String?,
  );

  String method;

  /// As typed ("6000", "1,250.50").
  String amountText;
  String bankNumber;
  String branchNumber;
  String accountNumber;
  String checkNumber;

  /// 'YYYY-MM-DD' (today; a cheque may carry a later date).
  String date;

  BigInt get amountMinor => parseAmount(amountText) ?? BigInt.zero;

  bool get checkValid =>
      method != 'CHECK' ||
      [
        bankNumber,
        branchNumber,
        accountNumber,
        checkNumber,
      ].every((v) => RegExp(r'^\d+$').hasMatch(v.trim()));

  bool get valid =>
      method.isNotEmpty && amountMinor > BigInt.zero && checkValid;

  /// §9.1 "+ צ'ק נוסף": same bank, cheque number + 1, a month later.
  SplitLine nextCheck(String amount) {
    final n = int.tryParse(checkNumber.trim());
    final d = DateTime.tryParse(date);
    var next = date;
    if (d != null) {
      final lastDay = DateTime(d.year, d.month + 2, 0).day;
      next = todayIso(
        DateTime(d.year, d.month + 1, d.day > lastDay ? lastDay : d.day),
      );
    }
    return SplitLine(
      method: 'CHECK',
      amountText: amount,
      bankNumber: bankNumber,
      branchNumber: branchNumber,
      accountNumber: accountNumber,
      checkNumber: n == null
          ? ''
          : (n + 1).toString().padLeft(checkNumber.trim().length, '0'),
      date: next,
    );
  }

  PaymentInput toPayment() => PaymentInput(
    method: method,
    amountMinor: amountMinor,
    paymentDate: date,
    bankNumber: method == 'CHECK' ? bankNumber.trim() : null,
    branchNumber: method == 'CHECK' ? branchNumber.trim() : null,
    accountNumber: method == 'CHECK' ? accountNumber.trim() : null,
    checkNumber: method == 'CHECK' ? checkNumber.trim() : null,
  );

  Map<String, dynamic> toJson() => {
    'method': method,
    'amountText': amountText,
    'bankNumber': bankNumber,
    'branchNumber': branchNumber,
    'accountNumber': accountNumber,
    'checkNumber': checkNumber,
    'date': date,
  };
}

/// The server takes at most 10 payments with one document (SA2).
const int maxSplitLines = 10;

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

  /// The payment chip ('' = not chosen yet: a paid kind cannot issue).
  String method = '';

  /// The user picked the chip: choosing another customer keeps it.
  bool methodTouched = false;
  String bankNumber = '';
  String branchNumber = '';
  String accountNumber = '';
  String checkNumber = '';
  final List<ComposeLine> extraLines = [];
  String discountText = '';

  /// C3 "פיצול תשלום" (opt-in): [splits] replace [method] + cheque fields.
  bool split = false;
  final List<SplitLine> splits = [];

  /// S3 "מע״מ: ללא" (a VAT business issuing at 0%).
  bool vatNone = false;

  /// S3 "מע״מ: לפי שורה": each extra line has its own "ללא מע״מ".
  bool vatPerLine = false;

  /// BE-07 note printed on the document / quote (≤500).
  String notes = '';

  /// BE-09 payment terms of the customer — else the business default (0110,
  /// GET /customers/:id effectivePaymentTerms): IMMEDIATE | EOM | EOM_30… |
  /// EOM_DAYS / NET_DAYS + [customerTermsDays]; null = unknown → שוטף+30.
  String? customerTerms;
  int? customerTermsDays;

  /// A due date the user picked in S3 (or the draft's): wins over the terms
  /// and survives a customer change.
  String? pickedDueDate;

  /// BE-07 due date sent with collect kinds (305 / 300), 'YYYY-MM-DD'.
  /// From the Israel civil date of today (the issue date sent).
  String get dueDate =>
      pickedDueDate ??
      dueDateForTerms(
        customerTerms,
        israelTodayDate(),
        days: customerTermsDays,
      );
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

  /// The server keeps a typed VAT-included total exactly (`agreedTotalMinor`,
  /// GET /me `lineAgreedTotal`). Off: the nearest net price (₪2 → ₪1.99).
  /// Quotes only with [quoteAgreedTotals] (GET /me `quoteLineAgreedTotal`).
  bool agreedTotals = false;

  /// The server stores agreed totals on quote lines (0107).
  bool quoteAgreedTotals = false;

  /// Lines exactly as sent to POST /documents (net unit prices; with
  /// amounts incl. VAT, `agreedTotalMinor` = the typed gross — owner Q1).
  List<Map<String, dynamic>> get requestLines {
    final rate = taxRate;
    Map<String, dynamic> line({
      required String description,
      required BigInt quantity,
      required BigInt typedPrice,
      BigInt? typedDiscount,
      required int rate,
      String? itemId,
    }) {
      final gross = _grossInput && rate > 0;
      final g = gross
          ? grossLine(
              quantityMicros: quantity,
              grossUnitMinor: typedPrice,
              grossDiscountMinor: typedDiscount,
              basisPoints: rate,
              agreed:
                  agreedTotals && (kind != DocKind.quote || quoteAgreedTotals),
            )
          : null;
      final unit = g?.unitPriceMinor ?? typedPrice;
      final discount = g?.discountMinor ?? typedDiscount ?? BigInt.zero;
      return {
        'description': description,
        'quantityMicros': quantity.toString(),
        'unitPriceMinor': unit.toString(),
        if (discount > BigInt.zero) 'discountMinor': discount.toString(),
        'taxRateBasisPoints': rate,
        if (g?.agreedTotalMinor != null)
          'agreedTotalMinor': g!.agreedTotalMinor.toString(),
        'itemId': ?itemId,
      };
    }

    return [
      if (amountMinor > BigInt.zero)
        line(
          description: mainDescription,
          quantity: oneQuantity,
          typedPrice: amountMinor,
          typedDiscount: discountInput > BigInt.zero ? discountInput : null,
          rate: rate,
        ),
      for (final l in usedExtraLines)
        if (l.isValid)
          line(
            description: l.description.trim(),
            quantity: l.quantityMicros!,
            typedPrice: l.priceMinor!,
            rate: lineRate(l),
            itemId: l.itemId,
          ),
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
            agreedTotalMinor: BigInt.tryParse(
              l['agreedTotalMinor'] as String? ?? '',
            ),
          );
    }
    return sum;
  }

  BigInt get totalMinor => totals.totalMinor;

  /// A1: the big number is the document total. It is the typed amount itself
  /// only while they are equal (one line, no discount, amounts incl. VAT or
  /// no VAT); otherwise the total, with a caption on what was typed.
  bool get headlineIsTyped => totalMinor == amountMinor;

  /// Extra lines (S3) that count in the total.
  int get extraLineCount => usedExtraLines.where((l) => l.isValid).length;
  bool get hasDiscount => discountInput > BigInt.zero;

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

  BigInt get splitPaidMinor =>
      splits.fold(BigInt.zero, (a, l) => a + l.amountMinor);

  /// "נותר: ₪X" (negative = more than the total was typed).
  BigInt get splitRemainingMinor => totalMinor - splitPaidMinor;

  /// A tax invoice-receipt / receipt says the whole amount was received: the
  /// lines must add up to the total exactly (a part payment is a 305 + S5).
  bool get splitValid =>
      splits.length >= 2 &&
      splits.length <= maxSplitLines &&
      splits.every((l) => l.valid) &&
      splitRemainingMinor == BigInt.zero;

  /// "פיצול תשלום": the current method becomes line 1 with the whole total
  /// (the user lowers it and adds the rest with "+ תשלום נוסף").
  void startSplit() {
    split = true;
    splits
      ..clear()
      ..add(
        SplitLine(
          method: method,
          amountText: agorotToKeypadText(totalMinor),
          bankNumber: method == 'CHECK' ? bankNumber : '',
          branchNumber: method == 'CHECK' ? branchNumber : '',
          accountNumber: method == 'CHECK' ? accountNumber : '',
          checkNumber: method == 'CHECK' ? checkNumber : '',
        ),
      );
    notifyListeners();
  }

  /// Back to one method (line 1's).
  void endSplit() {
    if (splits.isNotEmpty) method = splits.first.method;
    split = false;
    splits.clear();
    notifyListeners();
  }

  /// "+ תשלום נוסף" / "+ צ'ק נוסף": the rest of the total, same method;
  /// after a cheque, the next cheque (same bank, number + 1, a month later).
  void addSplitLine() {
    if (splits.length >= maxSplitLines) return;
    final last = splits.isEmpty ? null : splits.last;
    final left = splitRemainingMinor;
    final rest = left > BigInt.zero ? agorotToKeypadText(left) : '';
    if (last != null && last.method == 'CHECK') {
      final same = last.amountMinor > BigInt.zero && left >= last.amountMinor
          ? last.amountText
          : rest;
      splits.add(last.nextCheck(same));
    } else {
      splits.add(SplitLine(method: last?.method ?? method, amountText: rest));
    }
    notifyListeners();
  }

  void removeSplitLine(int i) {
    splits.removeAt(i);
    if (splits.length < 2) {
      endSplit();
    } else {
      notifyListeners();
    }
  }

  /// The split lines as sent (empty on the one-method path).
  List<PaymentInput> get splitPayments =>
      config.paid && split ? [for (final l in splits) l.toPayment()] : const [];

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
      (!config.paid ||
          (split ? splitValid : (method.isNotEmpty && checkValid))) &&
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
    'issueDate': israelToday(),
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
        agreedTotalMinor: BigInt.tryParse(
          l['agreedTotalMinor'] as String? ?? '',
        ),
      ),
  ];

  PaymentInput? get payment => !config.paid || split
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
    if (_loadGross(lines)) return;
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

  /// Owner Q1: lines that kept a typed VAT-included total (stored total ≠
  /// the standard calculation) come back as the gross that was typed, so a
  /// copy totals the same. Only when every line has a whole gross unit price
  /// and no discount (but the leftover agorot of a several-unit agreed line,
  /// see [grossLine]); otherwise the net prefill.
  bool _loadGross(List<DocumentLine> lines) {
    if (!showVat || !agreedTotals) return false;
    var any = false;
    final gross = <BigInt>[];
    for (final l in lines) {
      if (l.totalMinor <= BigInt.zero) return false;
      final standard = calculateLine(
        quantityMicros: l.quantityMicros,
        unitPriceMinor: l.unitPriceMinor,
        discountMinor: l.discountMinor,
        taxRateBasisPoints: l.taxRateBasisPoints,
      ).totalMinor;
      final leftover =
          l.quantityMicros > oneQuantity &&
          standard != l.totalMinor &&
          l.discountMinor * oneQuantity < l.quantityMicros;
      if (l.discountMinor > BigInt.zero && !leftover) return false;
      if (standard != l.totalMinor) any = true;
      final scaled = l.totalMinor * oneQuantity;
      if (scaled % l.quantityMicros != BigInt.zero) return false;
      gross.add(scaled ~/ l.quantityMicros);
    }
    if (!any) return false;
    inclusive = true;
    final first = lines.first;
    final firstIsUnit = first.quantityMicros == oneQuantity;
    description = first.description;
    if (firstIsUnit) {
      amountText = agorotToKeypadText(gross.first);
      discountText = '';
    }
    for (var i = firstIsUnit ? 1 : 0; i < lines.length; i++) {
      final l = lines[i];
      extraLines.add(
        ComposeLine(
          description: l.description,
          quantityText: formatQuantity(l.quantityMicros),
          priceText: agorotToKeypadText(gross[i]),
          itemId: l.itemId,
          vatNone: l.taxRateBasisPoints == 0,
        ),
      );
    }
    vatNone = lines.every((l) => l.taxRateBasisPoints == 0);
    vatPerLine = !vatNone && lines.any((l) => l.taxRateBasisPoints == 0);
    notifyListeners();
    return true;
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
        totalMinor: lines[i].agreedTotalMinor ?? BigInt.zero,
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
    'split': split,
    'splits': [for (final l in splits) l.toJson()],
    'vatNone': vatNone,
    'vatPerLine': vatPerLine,
    'notes': notes,
    'customerTerms': customerTerms,
    'customerTermsDays': customerTermsDays,
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
    method = j['method'] as String? ?? '';
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
    splits
      ..clear()
      ..addAll([
        for (final l in (j['splits'] as List? ?? const []))
          SplitLine.fromJson(Map<String, dynamic>.from(l as Map)),
      ]);
    split = j['split'] == true && splits.isNotEmpty;
    vatNone = j['vatNone'] == true;
    vatPerLine = j['vatPerLine'] == true;
    notes = j['notes'] as String? ?? '';
    customerTerms = j['customerTerms'] as String?;
    customerTermsDays = j['customerTermsDays'] as int?;
    pickedDueDate = j['pickedDueDate'] as String?;
    requestAllocation = j['requestAllocation'] == true;
    validUntil = j['validUntil'] as String? ?? validUntil;
    donorTaxId = j['donorTaxId'] as String? ?? '';
    notifyListeners();
  }
}
