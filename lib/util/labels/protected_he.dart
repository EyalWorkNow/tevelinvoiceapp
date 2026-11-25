// §7 "קובץ מוגן בסיסמה" wording (V2, 2026-11-25).

abstract final class ProtectedHe {
  static const toggle = 'קובץ מוגן בסיסמה';
  static const toggleHint = 'הלקוח יקבל PDF שנפתח רק עם סיסמה';
  static const always = 'תמיד ללקוח הזה';
  static const passwordLabel = 'הסיסמה לקובץ';
  static const copy = 'העתק';
  static const copied = 'הועתק';
  static const copySemantics = 'העתקת הסיסמה';
  static const cardHint =
      'הסיסמה לא נשלחת עם הקובץ. אחרי השליחה שולחים אותה בהודעה נפרדת.';
  static const sentTitle = 'הקובץ נשלח מוגן ✓';
  static const sentHint = 'עכשיו שלחו ללקוח את הסיסמה בהודעה נפרדת:';
  static const sendWhatsApp = 'שלח סיסמה בוואטסאפ';
  static const sendSms = 'שלח סיסמה ב־SMS';
  static const done = 'סיום';
  static const phoneLabel = 'מספר הטלפון של הלקוח';
  static const showRow = 'נשלח מוגן · הצג סיסמה';
  static const sheetTitle = 'סיסמת הקובץ המוגן';
  static const smsSent = 'הסיסמה נשלחה מהמכשיר';
  static const alwaysOn = 'מעכשיו כל קובץ ללקוח הזה יישלח מוגן';
  static const alwaysOff = 'הלקוח הזה כבר לא מקבל קבצים מוגנים כברירת מחדל';

  /// The separate message with the password (never in the message with the file).
  static String passwordMessage(String business, String password) =>
      'הסיסמה לפתיחת המסמך מ$business: $password';

  static String lastSent(String when, {required bool link}) =>
      '${link ? 'קישור מוגן' : 'מייל מוגן'} · $when';
}
