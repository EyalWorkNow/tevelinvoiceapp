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
LineAmounts calculateLine({
  required BigInt quantityMicros,
  required BigInt unitPriceMinor,
  BigInt? discountMinor,
  required int taxRateBasisPoints,
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
  return LineAmounts(subtotal, tax);
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
