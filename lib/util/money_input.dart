// Owner Q1 (2026-11-16): every price / amount / quantity field opens the
// numeric keypad only, and what is typed is exactly what is stored: digits
// and one decimal point, at most 2 agorot digits (quantities: 6). A comma
// typed as the decimal key (some iOS keypads) becomes a point; parseAmount
// strips commas, so "1,5" would otherwise silently become ₪15.

import 'package:flutter/services.dart';

/// The numeric keypad with a decimal key (no letters, no minus).
const TextInputType moneyKeyboard = TextInputType.numberWithOptions(
  decimal: true,
);

/// Digits + one '.', at most [maxDecimals] after it. Anything else leaves
/// the field as it was.
class DecimalTextInputFormatter extends TextInputFormatter {
  const DecimalTextInputFormatter({this.maxDecimals = 2});

  /// Money (agorot).
  static const money = DecimalTextInputFormatter();

  /// Quantities (quantityMicros: 6 decimals).
  static const quantity = DecimalTextInputFormatter(maxDecimals: 6);

  final int maxDecimals;

  /// Text as typed or pasted → canonical text, or null when it is not a
  /// number this field takes. '1,180.50' → '1180.50', '12,5' → '12.5',
  /// '₪ 99.9' → '99.9'.
  String? normalize(String text) {
    var t = text.replaceAll(RegExp('[\\s₪\\u200e\\u200f\\u202a-\\u202e]'), '');
    if (t.contains('.')) {
      t = t.replaceAll(',', ''); // thousands separators
    } else if (RegExp(r'^\d*,\d*$').hasMatch(t) &&
        t.length - t.indexOf(',') - 1 <= maxDecimals) {
      t = t.replaceAll(',', '.'); // the keypad's decimal comma
    } else {
      t = t.replaceAll(',', '');
    }
    final m = RegExp(r'^(\d*)(\.(\d*))?$').firstMatch(t);
    if (m == null) return null;
    if ((m.group(3) ?? '').length > maxDecimals) return null;
    return t;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = normalize(newValue.text);
    if (text == null) return oldValue;
    if (text == newValue.text) return newValue;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// The formatters of a money field.
const List<TextInputFormatter> moneyFormatters = [
  DecimalTextInputFormatter.money,
];

/// The formatters of a quantity field.
const List<TextInputFormatter> quantityFormatters = [
  DecimalTextInputFormatter.quantity,
];
