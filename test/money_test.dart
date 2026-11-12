import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/util/money.dart';

BigInt b(int v) => BigInt.from(v);

void main() {
  group('formatMoney', () {
    test('formats agorot with grouping and 2 decimals', () {
      expect(formatMoney(b(118000)), '₪1,180.00');
      expect(formatMoney(b(5)), '₪0.05');
      expect(formatMoney(b(0)), '₪0.00');
      expect(formatMoney(b(123456789)), '₪1,234,567.89');
      expect(
        formatMoney(BigInt.parse('99999999999999999999')),
        '₪999,999,999,999,999,999.99',
      );
    });
    test('negative and trimmed', () {
      expect(formatMoney(b(-5000)), '-₪50.00');
      expect(formatMoney(b(118000), trimZeroAgorot: true), '₪1,180');
      expect(formatMoney(b(118050), trimZeroAgorot: true), '₪1,180.50');
    });
    test('formatWhole', () {
      expect(formatWhole(b(1248099)), '12,480');
      expect(formatWhole(b(-100000)), '-1,000');
    });
  });

  group('parseAmount', () {
    test('valid inputs', () {
      expect(parseAmount(''), BigInt.zero);
      expect(parseAmount('1180'), b(118000));
      expect(parseAmount('1,180.5'), b(118050));
      expect(parseAmount('₪ 12.05'), b(1205));
      expect(parseAmount('.5'), b(50));
      expect(parseAmount('7.'), b(700));
    });
    test('invalid inputs', () {
      expect(parseAmount('1.234'), isNull);
      expect(parseAmount('abc'), isNull);
      expect(parseAmount('1.2.3'), isNull);
      expect(parseAmount('-5'), isNull);
    });
  });

  group('keypadApply', () {
    String type(String keys) => keys.split('').fold('', keypadApply);

    test('digits, dot, decimals', () {
      expect(type('1180'), '1180');
      expect(type('12.345'), '12.34');
      expect(type('1..2'), '1.2');
      expect(type('.5'), '0.5');
    });
    test('no leading zeros', () {
      expect(type('007'), '7');
      expect(type('0.07'), '0.07');
    });
    test('delete and clear', () {
      expect(keypadApply('118', 'del'), '11');
      expect(keypadApply('', 'del'), '');
      expect(keypadApply('118.5', 'clear'), '');
      expect(keypadApply('1', 'x'), '1');
    });
    test('max whole digits', () {
      expect(type('1234567890'), '123456789');
      expect(type('123456789.99'), '123456789.99');
    });
    test('round trip with agorot', () {
      expect(keypadToAgorot('1180.5'), b(118050));
      expect(agorotToKeypadText(b(118050)), '1180.5');
      expect(agorotToKeypadText(b(118005)), '1180.05');
      expect(agorotToKeypadText(b(118000)), '1180');
      expect(agorotToKeypadText(BigInt.zero), '');
      for (final v in [1, 9, 10, 99, 100, 101, 123456, 99999999999]) {
        expect(keypadToAgorot(agorotToKeypadText(b(v))), b(v), reason: '$v');
      }
    });
    test('formatKeypadText keeps the partial fraction', () {
      expect(formatKeypadText(''), '₪0');
      expect(formatKeypadText('1180.'), '₪1,180.');
      expect(formatKeypadText('1180.5'), '₪1,180.5');
      expect(formatKeypadText('0.'), '₪0.');
    });
  });
}
