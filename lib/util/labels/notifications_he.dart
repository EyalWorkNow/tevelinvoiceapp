// Home bell + global search (tester feedback 2026-11-18).

abstract final class NotificationsHe {
  static const title = 'עדכונים';
  static const bellTooltip = 'עדכונים';
  static String bellA11y(int unread) => switch (unread) {
    <= 0 => 'עדכונים, אין חדשים',
    1 => 'עדכונים, עדכון חדש אחד',
    _ => 'עדכונים, $unread חדשים',
  };
  static const markAllRead = 'סמן הכול כנקרא';
  static const empty = 'אין עדכונים עדיין';
  static const emptyBody =
      'כאן יופיעו עדכונים כמו לקוח שאישר הצעת מחיר, מסמך שנחתם או תשלום שהתקבל.';
  static const loadMore = 'הצג עדכונים קודמים';
  static const today = 'היום';
  static const yesterday = 'אתמול';
  static const unreadDot = 'חדש';
}

abstract final class SearchHe {
  static const fieldHint = 'חיפוש לקוח, מסמך או הצעת מחיר';
  static const screenHint = 'למשל: הצעת מחיר של כהן';
  static const noResults = 'לא מצאנו תוצאות';
  static const noResultsBody = 'נסו שם לקוח, מספר מסמך או סכום.';
  static const customers = 'לקוחות';
  static const documents = 'מסמכים';
  static const quotes = 'הצעות מחיר';
  static const signRequests = 'מסמכים לחתימה';
  static const quote = 'הצעת מחיר';
  static const signRequest = 'מסמך לחתימה';
  static const examples = ['הצעת מחיר של…', 'בקשת תשלום ל…', 'קבלה 450'];
}

/// Per-category notification preferences (owner 2026-11-18).
abstract final class NotificationPrefsHe {
  static const title = 'סוגי התראות';
  static const row = 'סוגי התראות';
  static const rowHint = 'בחירה אילו התראות לקבל';
  static const gearTooltip = 'הגדרות התראות';
  static const intro =
      'בחרו על מה לקבל התראות לטלפון. ההגדרה שלכם בלבד, ולא משנה מה מקבלים אחרים בצוות.';
  static const alwaysOn = 'תמיד פעיל — לשמירה על החשבון';
  static const saved = 'ההגדרה נשמרה';

  /// §30A marketing consent (invoice#61). Default off.
  static const marketing = 'עדכונים ומבצעים מתבל';
  static const marketingHint =
      'הודעות שיווקיות מתבל: מבצעים, הטבות ותכונות חדשות. כבוי עד שתפעילו, ואפשר לבטל בכל רגע.';
}
