// תנאי תשלום (server: packages/postgres/src/payment-terms.ts, migration 0110).
//
//   IMMEDIATE                 מיידי        due = the issue date
//   EOM                       שוטף         the last day of the issue month
//   EOM_30 / 45 / 60 / 90     שוטף+N       end of the issue month + N days
//   EOM_DAYS (custom N)       שוטף+N
//   NET_DAYS (custom N)       N ימים מתאריך המסמך
//
// Israeli convention: שוטף+30 for 15/01 is 31/01 + 30 = 02/03 (01/03 in a
// leap year), never "the end of next month". The date is the Israel civil
// date ([israelTodayDate]); calendar arithmetic only (no Duration: DST-safe).

import 'israel_date.dart';

const List<String> presetPaymentTerms = [
  'IMMEDIATE',
  'EOM',
  'EOM_30',
  'EOM_45',
  'EOM_60',
  'EOM_90',
];
const String customEomTerms = 'EOM_DAYS';
const String customNetTerms = 'NET_DAYS';

bool isCustomTerms(String? code) =>
    code == customEomTerms || code == customNetTerms;

/// The days a preset adds after the end of the month (null = not שוטף).
int? _eomDays(String code) => switch (code) {
  'EOM' => 0,
  'EOM_30' => 30,
  'EOM_45' => 45,
  'EOM_60' => 60,
  'EOM_90' => 90,
  _ => null,
};

/// "שוטף+30", "מיידי", "תוך 14 ימים"… ; null code → null.
String? paymentTermsLabel(String? code, {int? days}) {
  if (code == null) return null;
  if (code == 'IMMEDIATE') return 'מיידי';
  if (code == 'EOM') return 'שוטף';
  if (code == customNetTerms) {
    return days == null ? 'מותאם' : 'תוך $days ימים';
  }
  final n = code == customEomTerms ? days : _eomDays(code);
  if (n == null) return null;
  return n == 0 ? 'שוטף' : 'שוטף+$n';
}

/// The due date of a document issued on [issueDate] under [code] / [days].
/// Unknown / no terms → [fallback] (the Composer's §7 default: שוטף+30).
DateTime dueDateFor(
  String? code,
  DateTime issueDate, {
  int? days,
  String fallback = 'EOM_30',
}) {
  final y = issueDate.year, m = issueDate.month, d = issueDate.day;
  DateTime eomPlus(int n) => DateTime(y, m + 1, n);
  if (code == 'IMMEDIATE') return DateTime(y, m, d);
  if (code == customNetTerms && days != null) return DateTime(y, m, d + days);
  if (code == customEomTerms && days != null) return eomPlus(days);
  final n = code == null ? null : _eomDays(code);
  if (n != null) return eomPlus(n);
  return code == fallback ? eomPlus(30) : dueDateFor(fallback, issueDate);
}

/// [dueDateFor] for a document issued today (Israel), 'YYYY-MM-DD'.
String dueDateTodayFor(String? code, {int? days, DateTime? now}) =>
    isoDate(dueDateFor(code, israelTodayDate(now), days: days));
