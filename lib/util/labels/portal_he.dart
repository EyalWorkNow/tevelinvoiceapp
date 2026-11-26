// "האזור האישי של הלקוח" (server 0135).

abstract final class PortalHe {
  static const sendLink = 'שלח קישור לאזור האישי';
  static const sheetTitle = 'האזור האישי';
  static String sheetSubtitle(String name) =>
      'קישור קבוע ל$name: המסמכים, היתרה לתשלום, הצעות לאישור, מסמכים לחתימה וקביעת פגישה — במקום אחד.';
  static String codeHint(String email) =>
      'הכניסה בקוד חד-פעמי שנשלח למייל $email. בלי הקוד אי אפשר לראות כלום.';
  static const loading = 'מכין את הקישור…';
  static const sendWhatsapp = 'שליחה בוואטסאפ';
  static const share = 'שיתוף';
  static const copy = 'העתקת הקישור';
  static const copied = 'הקישור הועתק';
  static const done = 'סגירה';
  static String lastLogin(String when) => 'נכנס לאחרונה: $when';
  static const neverLoggedIn = 'הלקוח עוד לא נכנס';
  static const emailMissing =
      'כדי לשלוח קישור צריך מייל ללקוח — הקוד לכניסה נשלח אליו.';

  // Customer details row.
  static const rowLabel = 'אזור אישי';
  static const rowActive = 'פעיל';
  static const manageTitle = 'הקישור לאזור האישי';
  static const resend = 'שליחה שוב';
  static const regenerate = 'קישור חדש';
  static const regenerateHint = 'הקישור הקודם יפסיק לעבוד';
  static const revoke = 'ביטול הקישור';
  static const revokeConfirmTitle = 'לבטל את הקישור?';
  static const revokeConfirmBody =
      'הלקוח לא יוכל להיכנס לאזור האישי, גם אם כבר פתח אותו. אפשר לשלוח קישור חדש בכל רגע.';
  static const regenerateConfirmTitle = 'ליצור קישור חדש?';
  static const regenerateConfirmBody =
      'הקישור הקודם יפסיק לעבוד מיד, וצריך לשלוח ללקוח את החדש.';
  static const revoked = 'הקישור בוטל';

  /// "24.11.2026 14:05" from ISO-8601 UTC (local time).
  static String when(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)}.${t.year} ${two(t.hour)}:${two(t.minute)}';
  }
}
