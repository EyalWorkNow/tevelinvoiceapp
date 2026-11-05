// Common Hebrew wording (INT). F11: every action label comes from
// lib/util/labels/* only — imperative, one verb per action ("שלח", "הפק",
// "בקש תשלום"…; never "שליחה"/"רישום"/"לבקש").

/// Shared action verbs and shell words. Domain wording lives in the domain
/// file (compose_he, document_he, …).
abstract final class CommonHe {
  // Tabs (§5; tab 4 = "עסק", §19 q1).
  static const tabHome = 'בית';
  static const tabPeople = 'לקוחות';
  static const tabBusiness = 'ניהול';
  static const tabCreate = 'יצירה';

  // Imperative verbs (F11).
  static const send = 'שלח';
  static const issue = 'הפק';
  static const paid = 'קיבלתי תשלום';
  static const requestPayment = 'בקש תשלום';
  static const approve = 'אשר';
  static const reject = 'דחה';
  static const save = 'שמור';
  static const share = 'שתף';
  static const retry = 'נסה שוב';
  static const cont = 'המשך';
  static const done = 'סיום';
  static const cancel = 'ביטול';
  static const close = 'סגור';
  static const open = 'פתח';
  static const more = 'עוד';

  // Standard states (§6 header).
  static const offlineButton = 'אין חיבור';
  static const offlineBanner = 'אין חיבור – מציג נתונים אחרונים';
  static const permissionsUpdated = 'ההרשאות שלך עודכנו';
  static const continueOnComputer = 'המשך במחשב';
  static const allHandled = 'הכל מטופל ✓';
}

/// 'YYYY-MM-DD' → 'היום' / 'אתמול' / 'לפני 3 ימים' / '12.10.2026'.
/// [now] is injectable for tests.
String relativeDateHe(String? isoDate, {DateTime? now}) {
  if (isoDate == null || isoDate.isEmpty) return '';
  final date = DateTime.tryParse(isoDate);
  if (date == null) return isoDate;
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(date.year, date.month, date.day);
  final days = today.difference(day).inDays;
  if (days == 0) return 'היום';
  if (days == 1) return 'אתמול';
  if (days > 1 && days < 7) return 'לפני $days ימים';
  return formatDateHe(isoDate);
}

/// 'YYYY-MM-DD' → '12.10.2026' (Israeli order).
String formatDateHe(String? isoDate) {
  if (isoDate == null) return '';
  final date = DateTime.tryParse(isoDate);
  if (date == null) return isoDate;
  return '${date.day}.${date.month}.${date.year}';
}
