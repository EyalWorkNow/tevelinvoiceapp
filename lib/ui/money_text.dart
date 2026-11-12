// Money as the user sees and hears it: LTR isolates for RTL sentences,
// Hebrew words for VoiceOver (spec V2 §15.1, AT-71), and the in-app
// "הסתר סכומים" switch (F12).
//
// Spec §2.3 names lib/util/money_semantics.dart for the spoken form; that
// path is not DS-owned, so the implementation lives here and INT may
// re-export it from util (`export '../ui/money_text.dart' show spokenAmountHe;`).

import 'package:flutter/widgets.dart';

import '../util/money.dart';

const String _lri = '\u2066'; // LEFT-TO-RIGHT ISOLATE
const String _pdi = '\u2069'; // POP DIRECTIONAL ISOLATE

/// Wraps [text] (amount, phone, document number) in an LTR isolate so it
/// never reorders inside a Hebrew sentence.
String ltrIsolate(String text) => '$_lri$text$_pdi';

/// '₪1,180' wrapped in an LTR isolate, for use inside Hebrew sentences.
String moneyInline(BigInt minor, {bool trimZeroAgorot = true}) =>
    ltrIsolate(formatMoney(minor, trimZeroAgorot: trimZeroAgorot));

/// Shown instead of any amount while "הסתר סכומים" is on.
const String hiddenAmountText = '₪•••';
const String hiddenAmountSpoken = 'סכום מוסתר';

/// Hides every amount the design system draws below it when [hidden] is
/// true (spec F12). INT puts one at the app root, bound to the setting.
class AmountPrivacy extends InheritedWidget {
  const AmountPrivacy({super.key, required this.hidden, required super.child});

  final bool hidden;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AmountPrivacy>()?.hidden ??
      false;

  @override
  bool updateShouldNotify(AmountPrivacy oldWidget) =>
      hidden != oldWidget.hidden;
}

// ---------------------------------------------------------------------------
// Spoken Hebrew: 118000 → 'אלף מאה שמונים שקלים'.

const _onesM = [
  '',
  'אחד',
  'שניים',
  'שלושה',
  'ארבעה',
  'חמישה',
  'שישה',
  'שבעה',
  'שמונה',
  'תשעה',
];
const _onesF = [
  '',
  'אחת',
  'שתיים',
  'שלוש',
  'ארבע',
  'חמש',
  'שש',
  'שבע',
  'שמונה',
  'תשע',
];
const _teensM = [
  'עשרה', 'אחד עשר', 'שנים עשר', 'שלושה עשר', 'ארבעה עשר', //
  'חמישה עשר', 'שישה עשר', 'שבעה עשר', 'שמונה עשר', 'תשעה עשר',
];
const _teensF = [
  'עשר', 'אחת עשרה', 'שתים עשרה', 'שלוש עשרה', 'ארבע עשרה', //
  'חמש עשרה', 'שש עשרה', 'שבע עשרה', 'שמונה עשרה', 'תשע עשרה',
];
const _tens = [
  '',
  '',
  'עשרים',
  'שלושים',
  'ארבעים',
  'חמישים',
  'שישים',
  'שבעים',
  'שמונים',
  'תשעים',
];
const _hundreds = [
  '', 'מאה', 'מאתיים', 'שלוש מאות', 'ארבע מאות', //
  'חמש מאות', 'שש מאות', 'שבע מאות', 'שמונה מאות', 'תשע מאות',
];
const _thousandsSmall = [
  '', 'אלף', 'אלפיים', 'שלושת אלפים', 'ארבעת אלפים', 'חמשת אלפים', //
  'ששת אלפים', 'שבעת אלפים', 'שמונת אלפים', 'תשעת אלפים', 'עשרת אלפים',
];

List<String> _below1000(int n, {required bool masculine}) {
  final out = <String>[];
  if (n >= 100) out.add(_hundreds[n ~/ 100]);
  final rest = n % 100;
  if (rest >= 10 && rest < 20) {
    out.add((masculine ? _teensM : _teensF)[rest - 10]);
  } else {
    if (rest >= 20) out.add(_tens[rest ~/ 10]);
    if (rest % 10 > 0) out.add((masculine ? _onesM : _onesF)[rest % 10]);
  }
  return out;
}

List<String> _scale(int n, String one) => switch (n) {
  0 => const [],
  1 => [one],
  2 => ['שני $one'],
  _ => [..._below1000(n, masculine: true), one],
};

/// Cardinal number in Hebrew words, without conjunctions ('אלף מאה שמונים').
String hebrewNumberWords(BigInt value, {bool masculine = true}) {
  if (value == BigInt.zero) return 'אפס';
  if (value.isNegative)
    return 'מינוס ${hebrewNumberWords(-value, masculine: masculine)}';
  if (value >= BigInt.from(10).pow(12)) return value.toString();
  final n = value.toInt();
  final billions = n ~/ 1000000000;
  final millions = (n ~/ 1000000) % 1000;
  final thousands = (n ~/ 1000) % 1000;
  final rest = n % 1000;
  return [
    ..._scale(billions, 'מיליארד'),
    ..._scale(millions, 'מיליון'),
    if (thousands > 0 && thousands <= 10)
      _thousandsSmall[thousands]
    else if (thousands > 10) ...[
      ..._below1000(thousands, masculine: true),
      'אלף',
    ],
    ..._below1000(rest, masculine: masculine),
  ].join(' ');
}

/// VoiceOver label for an amount in agorot (spec AT-71):
/// 118000 → 'אלף מאה שמונים שקלים'; 150 → 'שקל אחד וחמישים אגורות'.
String spokenAmountHe(BigInt minor) {
  if (minor.isNegative) return 'מינוס ${spokenAmountHe(-minor)}';
  final shekels = minor ~/ BigInt.from(100);
  final agorot = (minor % BigInt.from(100)).toInt();
  final shekelPart = switch (shekels.toInt()) {
    0 => agorot == 0 ? 'אפס שקלים' : '',
    1 => 'שקל אחד',
    2 => 'שני שקלים',
    _ => '${hebrewNumberWords(shekels)} שקלים',
  };
  if (agorot == 0) return shekelPart;
  final agorotPart = switch (agorot) {
    1 => 'אגורה אחת',
    2 => 'שתי אגורות',
    _ => '${hebrewNumberWords(BigInt.from(agorot), masculine: false)} אגורות',
  };
  return shekelPart.isEmpty ? agorotPart : '$shekelPart ו$agorotPart';
}

/// Display text for an amount, honouring [AmountPrivacy].
String moneyText(
  BuildContext context,
  BigInt minor, {
  bool trimZeroAgorot = true,
}) => AmountPrivacy.of(context)
    ? hiddenAmountText
    : formatMoney(minor, trimZeroAgorot: trimZeroAgorot);

/// Spoken text for an amount, honouring [AmountPrivacy].
String moneySpoken(BuildContext context, BigInt minor) =>
    AmountPrivacy.of(context) ? hiddenAmountSpoken : spokenAmountHe(minor);
