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

/// Owner Q1 ("I type 2 and it writes 1.99") + walkthrough 2026-11-17 #1
/// ("3 × ₪2.00 came out ₪5.98"): the line whose document total is exactly
/// the gross the user typed, for any quantity and discount.
///
/// [quantityMicros] × [grossUnitMinor] − [grossDiscountMinor] is the target.
/// The server keeps it through `agreedTotalMinor`: the line VAT becomes
/// target − net subtotal, accepted when it is the floor or the ceiling of the
/// exact VAT on that subtotal ([agreedTaxAllowed]). So the net subtotal must
/// be one of the (1–2) values S with |target − S × (1 + r)| < 1 agora.
///
/// The net subtotal is round(quantity × unit price) − discount, the unit
/// price in whole agorot: the uniform format prints it with 2 decimals
/// (D110 1265 X9V2) and checks 1267 = 1264 × 1265 + 1266 (validator.ts), so
/// a sub-agora unit price cannot be printed. With one unit the net of the
/// typed price fits; with several units (₪2.00 × 3: net 1.69 × 3 = 5.07,
/// 1.70 × 3 = 5.10, accepted 5.08 / 5.09) the line carries the agorot left
/// over as a line discount (D110 1266, §2.4(יב)): 3 × 1.70 − 0.01 = 5.09 +
/// VAT 0.91 = ₪6.00. The discount is always below the quantity in agorot.
///
/// Without server support ([agreed] false), the nearest standard line (the
/// old behaviour).
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
  if (!agreed || target <= BigInt.zero || grossUnitMinor <= BigInt.zero) {
    return nearest;
  }
  BigInt total(GrossLine l) => calculateLine(
    quantityMicros: quantityMicros,
    unitPriceMinor: l.unitPriceMinor,
    discountMinor: l.discountMinor,
    taxRateBasisPoints: basisPoints,
  ).totalMinor;
  if (nearestDiscount <= _lineGross(quantityMicros, nearestUnit) &&
      total(nearest) == target) {
    return nearest;
  }

  // Net subtotals the server accepts with the target total, ascending.
  final wantNet = netOfGross(target, basisPoints);
  final accepted = [
    for (var d = -2; d <= 2; d++)
      if (wantNet + BigInt.from(d) > BigInt.zero &&
          agreedTaxAllowed(
            wantNet + BigInt.from(d),
            target - wantNet - BigInt.from(d),
            basisPoints,
          ))
        wantNet + BigInt.from(d),
  ];
  if (accepted.isEmpty) return nearest; // never at a sane rate

  // The printed unit price: the net of the typed one ("₪2.00 → 1.69").
  final typedUnit = netOfGross(grossUnitMinor, basisPoints);
  GrossLine? at(BigInt unit, {required bool preferWantNet}) {
    if (unit <= BigInt.zero) return null;
    final lineGross = _lineGross(quantityMicros, unit);
    final fits = accepted.where((s) => s <= lineGross).toList();
    if (fits.isEmpty) return null;
    // A typed discount: its net is target-net away (the VAT included in the
    // price); otherwise the smallest leftover.
    final subtotal = preferWantNet && fits.contains(wantNet)
        ? wantNet
        : fits.last;
    return GrossLine(
      unitPriceMinor: unit,
      discountMinor: lineGross - subtotal,
      agreedTotalMinor: target,
    );
  }

  if (gDiscount > BigInt.zero) {
    // Keep the typed unit price; the discount takes the line to the target.
    final keep = at(typedUnit, preferWantNet: true);
    if (keep != null) return keep;
  }
  // The smallest unit price covering the lowest accepted subtotal, and the
  // next ones (fractional quantities); the least leftover wins, then the
  // unit price nearest the typed one.
  final floorUnit = (accepted.first * _quantityScale) ~/ quantityMicros;
  GrossLine? best;
  for (final unit in [
    typedUnit,
    for (var d = -1; d <= 3; d++) floorUnit + BigInt.from(d),
  ]) {
    final candidate = at(unit, preferWantNet: false);
    if (candidate == null) continue;
    if (best == null ||
        candidate.discountMinor < best.discountMinor ||
        (candidate.discountMinor == best.discountMinor &&
            (candidate.unitPriceMinor - typedUnit).abs() <
                (best.unitPriceMinor - typedUnit).abs())) {
      best = candidate;
    }
  }
  return best ?? nearest;
}

BigInt _lineGross(BigInt quantityMicros, BigInt unitPriceMinor) =>
    roundHalfAwayFromZeroDiv(quantityMicros * unitPriceMinor, _quantityScale);

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
