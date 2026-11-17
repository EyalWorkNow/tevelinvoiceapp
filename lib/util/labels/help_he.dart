// "עזרה" — the help assistant chat (owner request 2026-11-18).

abstract final class HelpHe {
  /// An e-mail inside Hebrew text, isolated left-to-right (else ".com.123@123").
  static String _ltr(String email) => '\u2066$email\u2069';

  static const title = 'עזרה';
  static const rowLabel = 'עזרה — שאלו את העוזר';
  static const rowHint = 'איך עושים, איפה נמצא, ומעבר לנציג';
  static const greeting =
      'שלום! אני העוזר של תבל. אפשר לשאול אותי איך עושים משהו באפליקציה '
      'או איפה נמצא מסך מסוים, ואסביר איך מגיעים אליו.';
  static const startersTitle = 'שאלות נפוצות';
  static const starters = [
    'איך שולחים בקשת תשלום?',
    'איך מפיקים חשבונית מס קבלה?',
    'איך שולחים מסמך לחתימה?',
    'איך מוסיפים את החתימה שלי?',
    'איך מזמינים עובד לעסק?',
    'מה זה מספר הקצאה?',
  ];
  static const inputHint = 'כתבו שאלה…';
  static const send = 'שליחה';
  static const typing = 'העוזר כותב…';
  static const privacyNotice =
      'השאלות נשלחות לעיבוד אצל DeepSeek, ספק חיצוני מחוץ לישראל. '
      'אל תכתבו פרטים אישיים.';
  static const escalate = 'העבר לנציג';
  static const escalateTitle = 'העברה לנציג';
  static String escalateBody(String supportEmail, String? contactEmail) =>
      'נשלח את השיחה לצוות התמיכה (${_ltr(supportEmail)})'
      '${contactEmail == null || contactEmail.isEmpty ? '' : ' ונחזור אליך למייל ${_ltr(contactEmail)}'}.';
  static const escalateNoteHint = 'רוצים להוסיף משהו? (לא חובה)';
  static const escalateSend = 'שליחה לנציג';
  static const cancel = 'ביטול';
  static String escalated(String? contactEmail) =>
      contactEmail == null || contactEmail.isEmpty
      ? 'הפנייה נשלחה לצוות התמיכה. נחזור אליך בהקדם.'
      : 'הפנייה נשלחה לצוות התמיכה. נחזור אליך למייל ${_ltr(contactEmail)}.';
  static String escalateFailed(String supportEmail) =>
      'לא הצלחנו לשלוח את הפנייה. אפשר לכתוב לנו ישירות ל-${_ltr(supportEmail)}';
  static String escalateLimit(String supportEmail) =>
      'שלחת היום כבר כמה פניות. אפשר לכתוב לנו ישירות ל-${_ltr(supportEmail)}';
  static const escalateEmpty = 'כתבו קודם שאלה או הוסיפו הודעה לנציג.';
  static const cannotHelpHint = 'לא מצאתי תשובה. רוצים שנעביר לנציג?';
  static const unavailableTitle = 'העוזר לא זמין כרגע';
  static String unavailableBody(String supportEmail) =>
      'אפשר להעביר את השאלה לנציג, או לכתוב לנו ל-${_ltr(supportEmail)}';
  static const offline = 'אין חיבור לאינטרנט. בדקו את החיבור ונסו שוב.';
  static const failed = 'לא הצלחנו לקבל תשובה. נסו שוב.';
  static const retry = 'נסו שוב';
  static const rateLimited = 'רגע, יותר מדי שאלות ברצף. נסו שוב בעוד דקה.';
  static String dailyLimit(String supportEmail) =>
      'הגעתם למכסת השאלות להיום. אפשר להעביר לנציג או לכתוב ל-${_ltr(supportEmail)}';
  static const chipUnavailable = 'המסך הזה עוד לא זמין בגרסה שלך';
  static const openScreen = 'פתיחת המסך';
}
