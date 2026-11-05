import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/util/vat.dart';

BigInt b(int v) => BigInt.from(v);

/// Brute force: every net in a wide window around the estimate.
BigInt? bruteNet(BigInt gross, int bp) {
  final est = gross * b(10000) ~/ b(10000 + bp);
  for (var d = -20; d <= 20; d++) {
    final net = est + b(d);
    if (net <= BigInt.zero) continue;
    if (totalForNet(net, bp) == gross) return net;
  }
  return null;
}

void main() {
  group('roundHalfAwayFromZeroDiv (server policy)', () {
    test('half rounds away from zero', () {
      expect(roundHalfAwayFromZeroDiv(b(5), b(10)), b(1));
      expect(roundHalfAwayFromZeroDiv(b(15), b(10)), b(2));
      expect(roundHalfAwayFromZeroDiv(b(14), b(10)), b(1));
      expect(roundHalfAwayFromZeroDiv(b(-5), b(10)), b(-1));
      expect(roundHalfAwayFromZeroDiv(b(-15), b(10)), b(-2));
      expect(roundHalfAwayFromZeroDiv(b(-14), b(10)), b(-1));
      expect(roundHalfAwayFromZeroDiv(b(0), b(10)), b(0));
    });
  });

  group('calculateLine (server line-calculation.ts)', () {
    test('1 × ₪1,000 at 18% = 1,180', () {
      final l = calculateLine(quantityMicros: oneQuantity, unitPriceMinor: b(100000), taxRateBasisPoints: 1800);
      expect(l.subtotalMinor, b(100000));
      expect(l.taxMinor, b(18000));
      expect(l.totalMinor, b(118000));
    });
    test('fractional quantity rounds the gross, then VAT rounds', () {
      // 1.5 × 333 = 499.5 → 500; VAT 18% of 500 = 90.
      final l = calculateLine(
          quantityMicros: b(1500000), unitPriceMinor: b(333), taxRateBasisPoints: 1800);
      expect(l.subtotalMinor, b(500));
      expect(l.taxMinor, b(90));
    });
    test('discount is subtracted before VAT', () {
      final l = calculateLine(
          quantityMicros: oneQuantity,
          unitPriceMinor: b(10000),
          discountMinor: b(1000),
          taxRateBasisPoints: 1800);
      expect(l.subtotalMinor, b(9000));
      expect(l.taxMinor, b(1620));
    });
    test('VAT half agora rounds up', () {
      // 25 × 18% = 4.5 → 5
      expect(calculateLine(quantityMicros: oneQuantity, unitPriceMinor: b(25), taxRateBasisPoints: 1800).taxMinor,
          b(5));
    });
  });

  group('splitGross', () {
    test('₪1,180 incl. 18% → net ₪1,000 exactly', () {
      final s = splitGross(b(118000), 1800);
      expect(s.exact, isTrue);
      expect(s.netMinor, b(100000));
      expect(s.taxMinor, b(18000));
      expect(s.totalMinor, b(118000));
    });

    test('zero rate and non-positive amounts pass through', () {
      expect(splitGross(b(12345), 0).netMinor, b(12345));
      expect(splitGross(b(12345), 0).taxMinor, BigInt.zero);
      expect(splitGross(BigInt.zero, 1800).netMinor, BigInt.zero);
    });

    test('₪100 at 18% is not reachable with one line → nearest, lower on tie', () {
      // net 84.74 → 99.99; net 84.75 → 100.01
      expect(bruteNet(b(10000), 1800), isNull);
      final s = splitGross(b(10000), 1800);
      expect(s.exact, isFalse);
      expect(s.totalMinor, b(9999));
      expect(s.netMinor, b(8474));
    });

    test('1000 random amounts: exact whenever any net exists, else 1 agora away', () {
      final rnd = Random(20261030);
      var exact = 0;
      for (var i = 0; i < 1000; i++) {
        // mix of small, typical and very large amounts
        final magnitude = [100, 10000, 1000000, 100000000, 99999999999][i % 5];
        final gross = b(1 + rnd.nextInt(magnitude > 1 << 31 ? 1 << 31 : magnitude)) *
            (magnitude > 1 << 31 ? b(37) : BigInt.one);
        for (final bp in [1800, 1700, 1750, 0]) {
          final s = splitGross(gross, bp);
          // the split is what the server will compute for that net
          final line = calculateLine(quantityMicros: oneQuantity, unitPriceMinor: s.netMinor, taxRateBasisPoints: bp);
          expect(line.totalMinor, s.totalMinor, reason: 'gross $gross bp $bp');
          expect(line.taxMinor, s.taxMinor);
          final brute = bruteNet(gross, bp);
          if (brute != null) {
            expect(s.exact, isTrue, reason: 'gross $gross bp $bp should be exact');
            expect(s.totalMinor, gross);
            if (bp == 1800) exact++;
          } else {
            expect(s.exact, isFalse);
            expect((s.totalMinor - gross).abs(), BigInt.one, reason: 'gross $gross bp $bp');
          }
        }
      }
      // sanity: the large majority of amounts are exact
      expect(exact, greaterThan(800));
    });

    test('every amount ₪0.01–₪300.00 at 18% (exhaustive)', () {
      for (var g = 1; g <= 30000; g++) {
        final s = splitGross(b(g), 1800);
        final brute = bruteNet(b(g), 1800);
        expect(s.exact, brute != null, reason: 'gross $g');
        if (s.exact) expect(s.totalMinor, b(g));
      }
    });
  });

  group('quantity + rate text', () {
    test('parseQuantityMicros', () {
      expect(parseQuantityMicros('1'), b(1000000));
      expect(parseQuantityMicros('1.5'), b(1500000));
      expect(parseQuantityMicros('0.000001'), b(1));
      expect(parseQuantityMicros('0'), isNull);
      expect(parseQuantityMicros(''), isNull);
      expect(parseQuantityMicros('1.0000001'), isNull);
      expect(parseQuantityMicros('abc'), isNull);
    });
    test('formatQuantity', () {
      expect(formatQuantity(b(1000000)), '1');
      expect(formatQuantity(b(1500000)), '1.5');
      expect(formatQuantity(b(2250000)), '2.25');
    });
    test('formatRate', () {
      expect(formatRate(1800), '18%');
      expect(formatRate(1750), '17.5%');
      expect(formatRate(0), '0%');
    });
  });
}
