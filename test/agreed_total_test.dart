// Owner Q1 (2026-11-16): "I type 2 and it writes 1.99".
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/screens/compose/compose_state.dart';
import 'package:invoice/util/cancel_policy.dart';
import 'package:invoice/util/composer_config.dart';
import 'package:invoice/util/money_input.dart';
import 'package:invoice/util/vat.dart';

BigInt b(int v) => BigInt.from(v);
final unit = oneQuantity;

LineAmounts sent(GrossLine g, BigInt qty) => calculateLine(
  quantityMicros: qty,
  unitPriceMinor: g.unitPriceMinor,
  discountMinor: g.discountMinor,
  taxRateBasisPoints: 1800,
  agreedTotalMinor: g.agreedTotalMinor,
);

void main() {
  test('root cause: no net price totals ₪2.00 at 18% with per-line VAT', () {
    expect(totalForNet(b(169), 1800), b(199));
    expect(totalForNet(b(170), 1800), b(201));
    final split = splitGross(b(200), 1800);
    expect(split.exact, isFalse);
    expect(split.totalMinor, b(199)); // what the owner saw
  });

  for (final (gross, net, vat) in [
    (200, 169, 31),
    (9990, 8466, 1524),
    (118000, 100000, 18000),
    (10, 8, 2),
  ]) {
    test('one unit typed ₪${gross / 100} incl. VAT stays exactly that', () {
      final g = grossLine(
        quantityMicros: unit,
        grossUnitMinor: b(gross),
        basisPoints: 1800,
        agreed: true,
      );
      final r = sent(g, unit);
      expect(r.totalMinor, b(gross));
      expect(r.subtotalMinor, b(net));
      expect(r.taxMinor, b(vat));
      expect(agreedTaxAllowed(r.subtotalMinor, r.taxMinor, 1800), isTrue);
    });
  }

  test('every amount ₪0.01–₪1,000 (one unit, 18% and 17%) is exact', () {
    for (final rate in [1800, 1700]) {
      for (var g = 1; g <= 100000; g++) {
        final l = grossLine(
          quantityMicros: unit,
          grossUnitMinor: b(g),
          basisPoints: rate,
          agreed: true,
        );
        final r = calculateLine(
          quantityMicros: unit,
          unitPriceMinor: l.unitPriceMinor,
          discountMinor: l.discountMinor,
          taxRateBasisPoints: rate,
          agreedTotalMinor: l.agreedTotalMinor,
        );
        expect(r.totalMinor, b(g), reason: '$g @ $rate');
        if (l.agreedTotalMinor != null) {
          expect(agreedTaxAllowed(r.subtotalMinor, r.taxMinor, rate), isTrue);
          expect(l.discountMinor, BigInt.zero, reason: '$g');
        }
      }
    }
  });

  test('a discount (incl. VAT) still lands on the exact typed total', () {
    final g = grossLine(
      quantityMicros: unit,
      grossUnitMinor: b(1000),
      grossDiscountMinor: b(150),
      basisPoints: 1800,
      agreed: true,
    );
    expect(sent(g, unit).totalMinor, b(850));
    expect(g.discountMinor >= BigInt.zero, isTrue);
  });

  test('several units: exact when a net unit price fits, else nearest', () {
    // 5 × ₪11.80 → net 10.00 × 5: exact.
    final five = b(5) * unit;
    final g5 = grossLine(
      quantityMicros: five,
      grossUnitMinor: b(1180),
      basisPoints: 1800,
      agreed: true,
    );
    expect(sent(g5, five).totalMinor, b(5900));
    // 3 × ₪2.00: the subtotal moves in steps of 3 agorot and no step has a
    // VAT within the agora of ₪6.00 → the nearest standard line (open item).
    final three = b(3) * unit;
    final g3 = grossLine(
      quantityMicros: three,
      grossUnitMinor: b(200),
      basisPoints: 1800,
      agreed: true,
    );
    expect((sent(g3, three).totalMinor - b(600)).abs() <= b(3), isTrue);
  });

  test(
    'an older server (no agreed totals) keeps the nearest standard line',
    () {
      final g = grossLine(
        quantityMicros: unit,
        grossUnitMinor: b(200),
        basisPoints: 1800,
        agreed: false,
      );
      expect(g.agreedTotalMinor, isNull);
      expect(g.unitPriceMinor, b(169));
    },
  );

  test('the server rule rejects VAT beyond the agora', () {
    expect(agreedTaxAllowed(b(169), b(31), 1800), isTrue); // 30.42 → 31
    expect(agreedTaxAllowed(b(169), b(30), 1800), isTrue);
    expect(agreedTaxAllowed(b(169), b(32), 1800), isFalse);
    expect(agreedTaxAllowed(b(169), b(29), 1800), isFalse);
    // A rejected agreed total falls back to the standard result.
    expect(
      calculateLine(
        quantityMicros: unit,
        unitPriceMinor: b(169),
        taxRateBasisPoints: 1800,
        agreedTotalMinor: b(205),
      ).totalMinor,
      b(199),
    );
  });

  test('a catalog net price shows its roundest gross', () {
    expect(grossForNet(b(169), 1800), b(200));
    expect(grossForNet(b(100000), 1800), b(118000));
  });

  group('Composer', () {
    ComposeState compose({bool agreed = true}) => ComposeState(
      kind: DocKind.taxInvoiceReceipt,
      businessType: 'OSEK_MURSHE',
      vatBasisPoints: 1800,
    )..agreedTotals = agreed;

    for (final (typed, total) in [
      ('2', 200),
      ('99.9', 9990),
      ('1180', 118000),
      ('0.1', 10),
    ]) {
      test('typed $typed (incl. VAT) → document total $total', () {
        final s = compose()..amountText = typed;
        expect(s.totalMinor, b(total));
        expect(s.headlineIsTyped, isTrue);
        expect(s.requestLines.single['agreedTotalMinor'] ?? '$total', '$total');
      });
    }

    test('extra line ₪2.00 incl. VAT keeps ₪2.00', () {
      final s = compose()
        ..amountText = '10'
        ..extraLines.add(
          ComposeLine(description: 'x', quantityText: '1', priceText: '2'),
        );
      expect(s.totalMinor, b(1200));
    });

    test('typed before VAT is untouched (net 2.00 → 2.36)', () {
      final s = compose()
        ..inclusive = false
        ..amountText = '2';
      expect(s.totalMinor, b(236));
      expect(s.requestLines.single.containsKey('agreedTotalMinor'), isFalse);
    });

    test('a duplicate of an agreed line comes back as the typed gross', () {
      final s = compose()
        ..loadLines([
          DocumentLine(
            position: 1,
            description: 'שירות',
            quantityMicros: unit,
            unitPriceMinor: b(169),
            discountMinor: BigInt.zero,
            subtotalMinor: b(169),
            taxRateBasisPoints: 1800,
            taxAmountMinor: b(31),
            totalMinor: b(200),
          ),
        ]);
      expect(s.inclusive, isTrue);
      expect(s.amountText, '2');
      expect(s.totalMinor, b(200));
    });
  });

  test('a partial credit of ₪2.00 credits ₪2.00', () {
    final lines = creditLines(
      source: [
        CreditSourceLine(
          description: 'x',
          quantityMicros: unit,
          unitPriceMinor: b(100000),
          discountMinor: BigInt.zero,
          taxRateBasisPoints: 1800,
          totalMinor: b(118000),
        ),
      ],
      totalMinor: b(118000),
      alreadyCreditedMinor: BigInt.zero,
      amountMinor: b(200),
      partialDescription: 'זיכוי',
      agreedTotals: true,
    );
    expect(lines.single['unitPriceMinor'], '169');
    expect(lines.single['agreedTotalMinor'], '200');
  });

  test('a full credit of an agreed line carries its total', () {
    final lines = creditLines(
      source: [
        CreditSourceLine(
          description: 'x',
          quantityMicros: unit,
          unitPriceMinor: b(169),
          discountMinor: BigInt.zero,
          taxRateBasisPoints: 1800,
          totalMinor: b(200),
        ),
      ],
      totalMinor: b(200),
      alreadyCreditedMinor: BigInt.zero,
      amountMinor: b(200),
      partialDescription: 'זיכוי',
    );
    expect(lines.single['agreedTotalMinor'], '200');
  });

  group('DecimalTextInputFormatter', () {
    String? n(String t, [int d = 2]) =>
        DecimalTextInputFormatter(maxDecimals: d).normalize(t);
    test('money text', () {
      expect(n('2'), '2');
      expect(n('99.90'), '99.90');
      expect(n('12,5'), '12.5'); // decimal comma key
      expect(n('1,180.50'), '1180.50');
      expect(n('₪ 1180'), '1180');
      expect(n('1.999'), isNull);
      expect(n('1.2.3'), isNull);
      expect(n('-5'), isNull);
      expect(n('abc'), isNull);
      expect(n('1.123456', 6), '1.123456');
    });
    test('an invalid edit leaves the field as it was', () {
      const f = DecimalTextInputFormatter.money;
      const old = TextEditingValue(text: '1.99');
      expect(
        f.formatEditUpdate(old, const TextEditingValue(text: '1.999')).text,
        '1.99',
      );
      expect(
        f.formatEditUpdate(old, const TextEditingValue(text: '1,5')).text,
        '1.5',
      );
    });
  });
}
