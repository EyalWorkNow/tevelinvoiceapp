// 0119 "המסמכים של העסק" (tester 2026-11-18): the business's own certificates.

abstract final class VaultHe {
  static const title = 'המסמכים של העסק';
  static const intro =
      'תעודת עוסק, אישור ניהול ספרים, אישור ניכוי במקור ועוד — במקום אחד, מוכנים לשליחה ללקוח.';
  static const add = 'הוספת מסמך';
  static const empty = 'עוד אין כאן מסמכים';
  static const emptyHint =
      'צלמו או העלו את תעודת העוסק, אישור ניהול ספרים ואישור ניכוי במקור. נזכיר לכם לפני שפג תוקף.';
  static const viewOnly =
      'אפשר לצפות ולשתף. רק הבעלים והשותפים מוסיפים ועורכים.';
  static const sourceTitle = 'מאיפה המסמך?';
  static const sourcePdf = 'קובץ PDF';
  static const sourceCamera = 'צילום';
  static const sourceGallery = 'תמונה מהגלריה';
  static const detailsTitle = 'פרטי המסמך';
  static const editTitle = 'עריכת פרטים';
  static const category = 'סוג המסמך';
  static const docTitle = 'שם המסמך';
  static const issuedOn = 'תאריך הנפקה';
  static const expiresOn = 'בתוקף עד';
  static const noDate = 'לא צוין';
  static const clearDate = 'ניקוי התאריך';
  static const remind = 'תזכורת לפני שפג התוקף';
  static String remindDays(int d) => d == 0
      ? 'ביום שפג התוקף'
      : d == 1
      ? 'יום אחד לפני'
      : '$d ימים לפני';
  static const save = 'שמירה';
  static const uploading = 'מעלה…';
  static const uploaded = 'המסמך נשמר';
  static const saved = 'הפרטים נשמרו';
  static const deleted = 'המסמך הוסר';
  static const view = 'צפייה';
  static const share = 'שליחה';
  static const edit = 'עריכה';
  static const delete = 'הסרה';
  static const deleteTitle = 'להסיר את המסמך?';
  static const deleteBody =
      'המסמך לא יופיע יותר ברשימה. עותק נשמר ביומן הפעולות של העסק.';
  static const select = 'בחירה לשליחה';
  static const cancelSelect = 'ביטול';
  static String sendSelected(int n) =>
      n == 1 ? 'שליחת מסמך אחד' : 'שליחת $n מסמכים';
  static String shareText(String business) => 'מצורפים המסמכים של $business.';
  static const tooLarge = 'הקובץ גדול מדי. הגודל המרבי הוא 15 MB';
  static const notPdf = 'יש לבחור קובץ PDF תקין';
  static const infected = 'הקובץ נחסם בבדיקת אבטחה. נסו קובץ אחר.';
  static const noExpiry = 'ללא תוקף';
  static String expiresIn(int days) => days == 0
      ? 'פג היום'
      : days == 1
      ? 'פג מחר'
      : 'פג בעוד $days ימים';
  static String expiredAgo(int days) =>
      days == 1 ? 'פג אתמול' : 'פג לפני $days ימים';
  static String validUntil(String date) => 'בתוקף עד $date';
  static const permission = 'צפייה במסמכי העסק';
  static const permissionHint =
      'תעודת עוסק, ניהול ספרים, ניכוי במקור — צפייה ושליחה ללקוח, בלי עריכה';
}
