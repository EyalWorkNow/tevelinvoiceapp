// Agorot (BigInt) <-> display text, and keypad input. Never double.

final BigInt _hundred = BigInt.from(100);

/// 118000 → '₪1,180.00'. [trimZeroAgorot]: 118000 → '₪1,180'.
/// Negative values get a leading minus: '-₪50.00'.
String formatMoney(
  BigInt agorot, {
  bool trimZeroAgorot = false,
  String symbol = '₪',
}) {
  final negative = agorot.isNegative;
  final abs = agorot.abs();
  final whole = _groupThousands((abs ~/ _hundred).toString());
  final cents = (abs % _hundred).toInt();
  final fraction = (trimZeroAgorot && cents == 0)
      ? ''
      : '.${cents.toString().padLeft(2, '0')}';
  return '${negative ? '-' : ''}$symbol$whole$fraction';
}

/// 1180000 → '1,180,000' (no symbol, no fraction) — for big hero numbers.
String formatWhole(BigInt agorot) =>
    '${agorot.isNegative ? '-' : ''}${_groupThousands((agorot.abs() ~/ _hundred).toString())}';

String _groupThousands(String digits) {
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Parses user text ('1180', '1,180.5', '₪ 12.05') into agorot.
/// Returns null for invalid input or more than 2 decimals. '' → 0.
BigInt? parseAmount(String input) {
  final text = input.replaceAll(RegExp(r'[₪,\s]'), '');
  if (text.isEmpty) return BigInt.zero;
  final match = RegExp(r'^(\d*)(?:\.(\d{0,2}))?$').firstMatch(text);
  if (match == null) return null;
  final whole = match.group(1)!.isEmpty ? '0' : match.group(1)!;
  final frac = (match.group(2) ?? '').padRight(2, '0');
  return BigInt.parse(whole) * _hundred + BigInt.parse(frac);
}

/// Maximum integer digits the keypad accepts (₪999,999,999).
const int keypadMaxWholeDigits = 9;

/// Applies one keypad [key] ('0'–'9', '.', 'del', 'clear') to the typed text and returns
/// the new text. Rules: one dot, at most 2 decimals, no leading zeros,
/// at most [keypadMaxWholeDigits] whole digits. Invalid keys are ignored.
String keypadApply(String current, String key) {
  if (key == 'clear') return '';
  if (key == 'del') {
    return current.isEmpty ? '' : current.substring(0, current.length - 1);
  }
  final dot = current.indexOf('.');
  if (key == '.') {
    if (dot >= 0) return current;
    return current.isEmpty ? '0.' : '$current.';
  }
  if (!RegExp(r'^\d$').hasMatch(key)) return current;
  if (dot >= 0) {
    return current.length - dot - 1 >= 2 ? current : '$current$key';
  }
  if (current == '0') return key;
  if (current.length >= keypadMaxWholeDigits) return current;
  return '$current$key';
}

/// Keypad text → display while typing: '1180.5' → '₪1,180.5' (keeps the
/// partial fraction the user typed).
String formatKeypadText(String text, {String symbol = '₪'}) {
  if (text.isEmpty) return '${symbol}0';
  final dot = text.indexOf('.');
  final whole = dot < 0 ? text : text.substring(0, dot);
  final fraction = dot < 0 ? '' : text.substring(dot);
  return '$symbol${_groupThousands(whole.isEmpty ? '0' : whole)}$fraction';
}

/// Keypad text → agorot ('1180.5' → 118050).
BigInt keypadToAgorot(String text) => parseAmount(text) ?? BigInt.zero;

/// Agorot → keypad text (118050 → '1180.5', 118000 → '1180').
String agorotToKeypadText(BigInt agorot) {
  if (agorot <= BigInt.zero) return '';
  final whole = (agorot ~/ _hundred).toString();
  final cents = (agorot % _hundred).toInt();
  if (cents == 0) return whole;
  final frac = cents.toString().padLeft(2, '0');
  return '$whole.${frac.endsWith('0') ? frac.substring(0, 1) : frac}';
}
