// C6 · "מוכן לרו״ח" + "בקש תיקון/זיכוי" (QA 2026-11-16, persona 06).
// Item titles and hints come from the server (titleHe / hintHe); these are
// the app's own words around them.

abstract final class ReadinessHe {
  static const title = 'מוכן לרו״ח';
  static String scoreOf(int score) => '$score מתוך 100';
  static const ready = 'מוכן';
  static const almost = 'כמעט';
  static const notReady = 'לא מוכן';

  /// Badge word for [score] against [threshold] (≥ threshold = מוכן; within
  /// 20 points = כמעט).
  static String badge(int score, int threshold) => score >= threshold
      ? ready
      : score >= threshold - 20
      ? almost
      : notReady;

  static String missing(int n) => n == 1
      ? 'נשאר דבר אחד לפני שהרו״ח סוגר/ת את התקופה'
      : 'נשארו $n דברים לפני שהרו״ח סוגר/ת את התקופה';
  static const allGood = 'הכול מוכן. אפשר לשלוח לרו״ח.';
  static String passed(int n) =>
      n == 1 ? 'בדיקה אחת תקינה' : '$n בדיקות תקינות';
  static const showPassed = 'הצג בדיקות תקינות';
  static const hidePassed = 'הסתר בדיקות תקינות';

  // "שלח לרו״ח" below the threshold: an explicit confirm.
  static const sendAnywayTitle = 'התקופה עוד לא מוכנה';
  static String sendAnywayBody(int score, int open) =>
      'הציון $score מתוך 100, ו${open == 1 ? 'נשאר דבר אחד' : 'נשארו $open דברים'} לטיפול. '
      'הרו״ח יצטרך/תצטרך לשאול עליהם. לשלוח בכל זאת?';
  static const sendAnyway = 'שלח בכל זאת';
  static const fixFirst = 'אטפל קודם';

  // Accountant board (S14).
  static const loadingScore = 'בודק…';
  static const sortedLeastReady = 'ממוין לפי הכי פחות מוכן';
  static const showMore = 'טען עוד עסקים';
  static String scoreSemantics(int score, String badge) =>
      'מוכן לרו״ח: $score מתוך 100, $badge';

  // "בקש תיקון/זיכוי" (accountant, on a document).
  static const requestAction = 'בקש תיקון/זיכוי';
  static const requestTitle = 'בקשת תיקון מהעסק';
  static const requestBody =
      'הבעלים יקבל/תקבל כרטיס "לטיפול" עם טופס הזיכוי ממולא. '
      'את המסמך עצמו מפיק/ה רק מי שמורשה.';
  static const reasonLabel = 'מה צריך לתקן?';
  static const reasonHint = 'למשל: המחיר צריך להיות 400 ₪ לפני מע״מ';
  static const reasonRequired = 'כתבו מה צריך לתקן';
  static const amountLabel = 'סכום לזיכוי (לא חובה)';
  static const amountHint = 'ריק = הבעלים יחליט/תחליט';
  static const send = 'שלח בקשה';
  static const sent = 'הבקשה נשלחה לבעלים';

  // Owner inbox card.
  static String cardTitle(int count, String? customer) => count == 1
      ? 'הרו״ח ביקש/ה לתקן מסמך${customer == null ? '' : ' של $customer'}'
      : 'הרו״ח ביקש/ה לתקן $count מסמכים';
  static const cardAction = 'הפק זיכוי';
  static const requestedBy = 'הרו״ח ביקש/ה';
  static const dismissRequest = 'סגור את הבקשה בלי תיקון';
  static const dismissed = 'הבקשה נסגרה';
}
