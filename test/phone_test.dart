import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/util/phone.dart';

void main() {
  test('Israeli mobiles in every common spelling → 9725…', () {
    for (final raw in [
      '0501234567',
      '050-123-4567',
      '050 123 4567',
      '(050) 1234567',
      '+972501234567',
      '+972 50-123-4567',
      '+972 (0)50 123 4567',
      '00972501234567',
      '972501234567',
      '501234567',
      ' ‏050-1234567 ',
    ]) {
      expect(waPhone(raw), '972501234567', reason: raw);
    }
  });

  test('landlines and 07X numbers', () {
    expect(waPhone('03-1234567'), '97231234567');
    expect(waPhone('02 6543210'), '97226543210');
    expect(waPhone('077-1234567'), '972771234567');
  });

  test('foreign numbers written with + or 00 are kept', () {
    expect(waPhone('+1 415 555 0100'), '14155550100');
    expect(waPhone('0044 20 7946 0958'), '442079460958');
  });

  test('unusable input → null', () {
    for (final raw in [
      null,
      '',
      '   ',
      'abc',
      '050-123',
      '05012345678',
      '1234',
      '+972 12',
    ]) {
      expect(waPhone(raw), isNull, reason: '$raw');
    }
  });

  test('wa.me uri with and without a phone, text percent-encoded', () {
    final withPhone = whatsAppUri(
      phone: '972501234567',
      text: 'שלום דנה: https://x.test/d/a?b=1&c',
    );
    expect(
      withPhone.toString(),
      startsWith('https://wa.me/972501234567?text=%D7%A9%D7%9C%D7%95%D7%9D'),
    );
    expect(
      withPhone.queryParameters['text'],
      'שלום דנה: https://x.test/d/a?b=1&c',
    );
    final picker = whatsAppUri(text: 'hi there');
    expect(picker.toString(), 'https://wa.me/?text=hi%20there');
  });
}
