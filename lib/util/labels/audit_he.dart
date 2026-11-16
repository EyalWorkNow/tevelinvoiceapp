// "יומן פעולות" (C5, QA 2026-11-16 persona 05 pain 3 + persona 06).
// Verbs carry both forms ("הפיק/ה") like the rest of the app: the server
// knows names, not grammatical gender.

abstract final class AuditHe {
  static const title = 'יומן פעולות';
  static const row = 'יומן פעולות';
  static const intro =
      'מי עשה מה בעסק, ומתי. אי אפשר למחוק או לשנות רישום ביומן.';
  static const chipAll = 'הכל';
  static const chipDocuments = 'מסמכים';
  static const chipPayments = 'תשלומים';
  static const chipTeam = 'צוות והרשאות';
  static const chipSettings = 'הגדרות';
  static const empty = 'אין פעולות להצגה';
  static const emptyHint = 'פעולות חדשות יופיעו כאן ברגע שיקרו.';
  static const forbidden = 'יומן הפעולות פתוח לבעלים, לשותף ולרואה החשבון';
  static const loadMore = 'הצג פעולות קודמות';
  static const sensitive = 'שינוי רגיש';
  static const system = 'המערכת';
  static const customerSide = 'הלקוח';
  static const someone = 'משתמש';
  static const today = 'היום';
  static const yesterday = 'אתמול';
  static const reason = 'סיבה';
  static const unknown = 'לא ידוע';

  /// before → after field names (server `changes[].field`).
  static const Map<String, String> fields = {
    'approvals': 'חובת אישור',
    'thresholdMinor': 'סף אישור',
    'cashierCapMinor': 'תקרת קופאי/ת',
    'numberingStart': 'מספר התחלה',
    'role': 'תפקיד',
    'permissions': 'הרשאות נוספות',
    'logo': 'לוגו',
    'accentColor': 'צבע',
    'footerNote': 'הערת תחתית',
    'bank': 'פרטי הבנק',
    'owner': 'בעלות',
  };
  static const on = 'מופעל';
  static const off = 'כבוי';
  static const changed = 'שונו';

  static String from(String before, String after) => 'מ-$before ל-$after';
}
