// Line arithmetic identical to the server
// (invoiceproject packages/accounting-core/src/line-calculation.ts, policy
// HALF_UP_AWAY_FROM_ZERO) + the "כולל מע״מ" gross → net search.
// The server stays the source of truth; this is for the live preview and for
// choosing a net unit price whose server-computed total is the typed gross.

final BigInt _quantityScale = BigInt.from(1000000);
final BigInt _bpScale = BigInt.from(10000);

/// One unit in quantityMicros.
final BigInt oneQuantity = _quantityScale;

/// Round half away from zero of n / d (d > 0). Same as the server's
/// roundHalfAwayFromZeroDiv.
BigInt roundHalfAwayFromZeroDiv(BigInt numerator, BigInt denominator) {
  assert(denominator > BigInt.zero);
  final negative = numerator.isNegative;
  final n = numerator.abs();
  final q = (BigInt.two * n + denominator) ~/ (BigInt.two * denominator);
  return negative ? -q : q;
}

/// Server-equivalent result of one document line.
class LineAmounts {
  const LineAmounts(this.subtotalMinor, this.taxMinor);

  final BigInt subtotalMinor;
  final BigInt taxMinor;
  BigInt get totalMinor => subtotalMinor + taxMinor;

  LineAmounts operator +(LineAmounts other) => LineAmounts(
    subtotalMinor + other.subtotalMinor,
    taxMinor + other.taxMinor,
  );

  static final LineAmounts zero = LineAmounts(BigInt.zero, BigInt.zero);
}

/// calculateLine() from the server: gross = round(qty × price), subtotal =
/// gross − discount, tax = round(subtotal × bp / 10000).
/// [agreedTotalMinor] (server `agreedTotalMinor`, owner Q1): the price the
/// customer agreed to, VAT included. When the server's tax rule allows it
/// ([agreedTaxAllowed]) the line totals exactly that, the VAT being
/// agreed − subtotal; otherwise the standard result.
LineAmounts calculateLine({
  required BigInt quantityMicros,
  required BigInt unitPriceMinor,
  BigInt? discountMinor,
  required int taxRateBasisPoints,
  BigInt? agreedTotalMinor,
}) {
  final gross = roundHalfAwayFromZeroDiv(
    quantityMicros * unitPriceMinor,
    _quantityScale,
  );
  final subtotal = gross - (discountMinor ?? BigInt.zero);
  final tax = roundHalfAwayFromZeroDiv(
    subtotal * BigInt.from(taxRateBasisPoints),
    _bpScale,
  );
  if (agreedTotalMinor != null &&
      agreedTotalMinor != subtotal + tax &&
      agreedTaxAllowed(
        subtotal,
        agreedTotalMinor - subtotal,
        taxRateBasisPoints,
      )) {
    return LineAmounts(subtotal, agreedTotalMinor - subtotal);
  }
  return LineAmounts(subtotal, tax);
}

/// The server's rule for an agreed total: the VAT is the exact VAT on the
/// net rounded down or up (|tax − subtotal × rate| < 1 agora), never more.
bool agreedTaxAllowed(BigInt subtotalMinor, BigInt taxMinor, int basisPoints) {
  if (taxMinor < BigInt.zero) return false;
  final diff = taxMinor * _bpScale - subtotalMinor * BigInt.from(basisPoints);
  return diff.abs() < _bpScale;
}

/// VAT included in a gross price ("המס הכלול במחיר"): round(G × r / (1 + r)).
BigInt vatIncludedIn(BigInt grossMinor, int basisPoints) =>
    roundHalfAwayFromZeroDiv(
      grossMinor * BigInt.from(basisPoints),
      _bpScale + BigInt.from(basisPoints),
    );

/// Net part of a gross price: G − [vatIncludedIn]. 200 @ 18% → 169.
BigInt netOfGross(BigInt grossMinor, int basisPoints) =>
    grossMinor - vatIncludedIn(grossMinor, basisPoints);

/// One document line priced VAT included, as sent to the server.
class GrossLine {
  const GrossLine({
    required this.unitPriceMinor,
    required this.discountMinor,
    required this.agreedTotalMinor,
  });

  /// Net unit price / net discount (what the document prints).
  final BigInt unitPriceMinor;
  final BigInt discountMinor;

  /// The typed gross the line must total; null when the standard
  /// calculation already gives it (or nothing can).
  final BigInt? agreedTotalMinor;
}

/// Owner Q1 ("I type 2 and it writes 1.99"): the line whose document total
/// is exactly the gross the user typed. One unit at 18% has no net price
/// whose standard total is ₪2.00 (169 → 1.99, 170 → 2.01): the VAT included
/// in ₪2.00 is round(200 × 18/118) = 31, net 169, and the server keeps the
/// typed total through `agreedTotalMinor` (VAT within the agora of the exact
/// VAT on the net). [quantityMicros] × [grossUnitMinor] − [grossDiscountMinor]
/// is the target. Without server support ([agreed] false) or when no net
/// unit price fits, the nearest standard line (the old behaviour).
GrossLine grossLine({
  required BigInt quantityMicros,
  required BigInt grossUnitMinor,
  BigInt? grossDiscountMinor,
  required int basisPoints,
  required bool agreed,
}) {
  final gDiscount = grossDiscountMinor ?? BigInt.zero;
  if (basisPoints == 0) {
    return GrossLine(
      unitPriceMinor: grossUnitMinor,
      discountMinor: gDiscount,
      agreedTotalMinor: null,
    );
  }
  final target =
      roundHalfAwayFromZeroDiv(
        quantityMicros * grossUnitMinor,
        _quantityScale,
      ) -
      gDiscount;
  // Today's line: the net of each typed amount, standard VAT.
  final nearestUnit = splitGross(grossUnitMinor, basisPoints).netMinor;
  final nearestDiscount = gDiscount > BigInt.zero
      ? splitGross(gDiscount, basisPoints).netMinor
      : BigInt.zero;
  final nearest = GrossLine(
    unitPriceMinor: nearestUnit,
    discountMinor: nearestDiscount,
    agreedTotalMinor: null,
  );
  if (!agreed || target <= BigInt.zero) return nearest;
  BigInt total(GrossLine l) => calculateLine(
    quantityMicros: quantityMicros,
    unitPriceMinor: l.unitPriceMinor,
    discountMinor: l.discountMinor,
    taxRateBasisPoints: basisPoints,
  ).totalMinor;
  if (total(nearest) == target) return nearest;

  final wantNet = netOfGross(target, basisPoints);
  if (quantityMicros == _quantityScale) {
    // One unit: net unit price of the typed amount, the discount takes the
    // rest down to the net of the target (monotone: never negative).
    final unit = netOfGross(grossUnitMinor, basisPoints);
    return GrossLine(
      unitPriceMinor: unit,
      discountMinor: unit - wantNet,
      agreedTotalMinor: target,
    );
  }
  // Several units (no discount on extra lines): a net unit price whose
  // subtotal the server accepts with the target total.
  if (gDiscount == BigInt.zero) {
    final estimate = roundHalfAwayFromZeroDiv(
      wantNet * _quantityScale,
      quantityMicros,
    );
    for (final d in [0, -1, 1, -2, 2]) {
      final unit = estimate + BigInt.from(d);
      if (unit <= BigInt.zero) continue;
      final subtotal = roundHalfAwayFromZeroDiv(
        quantityMicros * unit,
        _quantityScale,
      );
      if (agreedTaxAllowed(subtotal, target - subtotal, basisPoints)) {
        return GrossLine(
          unitPriceMinor: unit,
          discountMinor: BigInt.zero,
          agreedTotalMinor: target,
        );
      }
    }
  }
  return nearest;
}

/// Net catalog price → the gross to show while amounts include VAT. Several
/// gross prices share one net (₪1.99 and ₪2.00 are both net 169 at 18%):
/// the roundest of them, else the standard total.
BigInt grossForNet(BigInt netMinor, int basisPoints) {
  final standard = totalForNet(netMinor, basisPoints);
  if (basisPoints == 0) return standard;
  final candidates = [
    for (var d = -2; d <= 2; d++)
      if (netOfGross(standard + BigInt.from(d), basisPoints) == netMinor)
        standard + BigInt.from(d),
  ];
  for (final step in [100, 10]) {
    for (final g in candidates) {
      if (g % BigInt.from(step) == BigInt.zero) return g;
    }
  }
  return standard;
}

/// Total the server computes for a single line of quantity 1 at [netMinor].
BigInt totalForNet(BigInt netMinor, int taxRateBasisPoints) => calculateLine(
  quantityMicros: _quantityScale,
  unitPriceMinor: netMinor,
  taxRateBasisPoints: taxRateBasisPoints,
).totalMinor;

/// A gross amount split into a net unit price (quantity 1) + VAT.
class GrossSplit {
  const GrossSplit({
    required this.netMinor,
    required this.taxMinor,
    required this.exact,
  });

  /// Unit price to send (quantity 1).
  final BigInt netMinor;
  final BigInt taxMinor;
  BigInt get totalMinor => netMinor + taxMinor;

  /// False when no net price gives exactly the typed gross (the server rounds
  /// VAT per line, so ~15% of agorot totals at 18% are unreachable with one
  /// line); [totalMinor] is then the nearest reachable total (1 agora away,
  /// the lower one on a tie).
  final bool exact;
}

/// Gross (VAT included) → net unit price whose server total is exactly
/// [grossMinor]. Searches net values around gross / (1 + rate) (±2 agorot is
/// always enough: the total grows by 1 or 2 agorot per net agora).
GrossSplit splitGross(BigInt grossMinor, int taxRateBasisPoints) {
  if (taxRateBasisPoints == 0 || grossMinor <= BigInt.zero) {
    return GrossSplit(netMinor: grossMinor, taxMinor: BigInt.zero, exact: true);
  }
  final estimate = roundHalfAwayFromZeroDiv(
    grossMinor * _bpScale,
    _bpScale + BigInt.from(taxRateBasisPoints),
  );
  BigInt? best;
  BigInt? bestTotal;
  for (var d = -2; d <= 2; d++) {
    final net = estimate + BigInt.from(d);
    if (net <= BigInt.zero) continue;
    final total = totalForNet(net, taxRateBasisPoints);
    if (total == grossMinor) {
      return GrossSplit(netMinor: net, taxMinor: total - net, exact: true);
    }
    final diff = (total - grossMinor).abs();
    final bestDiff = bestTotal == null ? null : (bestTotal - grossMinor).abs();
    if (bestDiff == null ||
        diff < bestDiff ||
        (diff == bestDiff && total < bestTotal!)) {
      best = net;
      bestTotal = total;
    }
  }
  best ??= BigInt.one;
  bestTotal ??= totalForNet(best, taxRateBasisPoints);
  return GrossSplit(netMinor: best, taxMinor: bestTotal - best, exact: false);
}

/// User text '2', '1.5', '0.25' → quantityMicros (max 6 decimals, > 0). Null if invalid.
BigInt? parseQuantityMicros(String input) {
  final text = input.replaceAll(RegExp(r'[\s,]'), '');
  final match = RegExp(r'^(\d*)(?:\.(\d{0,6}))?$').firstMatch(text);
  if (text.isEmpty || match == null) return null;
  final whole = match.group(1)!.isEmpty ? '0' : match.group(1)!;
  final frac = (match.group(2) ?? '').padRight(6, '0');
  final micros = BigInt.parse(whole) * _quantityScale + BigInt.parse(frac);
  return micros > BigInt.zero ? micros : null;
}

/// quantityMicros → short text: 1000000 → '1', 1500000 → '1.5'.
String formatQuantity(BigInt micros) {
  final whole = micros ~/ _quantityScale;
  final frac = (micros % _quantityScale)
      .toString()
      .padLeft(6, '0')
      .replaceAll(RegExp(r'0+$'), '');
  return frac.isEmpty ? '$whole' : '$whole.$frac';
}

/// VAT rate for display: 1800 → '18%', 1750 → '17.5%'.
String formatRate(int basisPoints) {
  final whole = basisPoints ~/ 100;
  final frac = (basisPoints % 100)
      .toString()
      .padLeft(2, '0')
      .replaceAll(RegExp(r'0+$'), '');
  return frac.isEmpty ? '$whole%' : '$whole.$frac%';
}
