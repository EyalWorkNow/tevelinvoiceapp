// "מסמך לחתימה" (server 0116) — every Hebrew string of lib/screens/sign/.

import '../../api/models/sign_request.dart';

abstract final class SignHe {
  static const entry = 'מסמך לחתימה';
  static const listTitle = 'מסמכים לחתימה';
  static const newRequest = 'מסמך חדש לחתימה';
  static const emptyTitle = 'עוד לא נשלחו מסמכים לחתימה';
  static const emptyBody =
      'מעלים PDF או מצלמים מסמך, מסמנים איפה הלקוח חותם — והוא ממלא וחותם מהטלפון.';
  static const chipAll = 'הכל';
  static const chipWaiting = 'ממתינים';
  static const chipSigned = 'נחתמו';
  static const chipDrafts = 'טיוטות';

  static const sourceTitle = 'מאיפה המסמך?';
  static const sourcePdf = 'קובץ PDF';
  static const sourceCamera = 'צילום מסמך';
  static const sourceGallery = 'תמונות מהגלריה';
  static const titleLabel = 'שם המסמך';
  static const titleHint = 'למשל: הסכם שירות';
  static const titleRequired = 'נא לתת למסמך שם';
  static const next = 'המשך';
  static const uploading = 'מעלה את המסמך…';
  static const uploadFailed = 'לא הצלחנו להעלות את המסמך';
  static const notPdf = 'הקובץ אינו PDF תקין';
  static const tooLarge = 'הקובץ גדול מ-10MB';
  static const tooManyPages = 'אפשר עד 50 עמודים במסמך';
  static const pickFailed = 'לא הצלחנו לפתוח את הקובץ';
  static const imagesFailed = 'לא הצלחנו להמיר את התמונות ל-PDF';

  // Editor
  static const editorTitle = 'מיקום שדות';
  static const editorHint = 'בוחרים סוג שדה ונוגעים במקום במסמך';
  static const editorSave = 'המשך לשליחה';
  static const editorSaved = 'השדות נשמרו';
  static const noFields = 'צריך להוסיף לפחות שדה אחד';
  static const tooManyFields = 'אפשר עד 100 שדות';
  static const fieldSheetTitle = 'הגדרות שדה';
  static const fieldLabel = 'כותרת (תוצג ללקוח)';
  static const fieldPlaceholder = 'טקסט עזרה';
  static const fieldRequired = 'שדה חובה';
  static const fieldDelete = 'מחיקת השדה';
  static const fieldDone = 'סיום';
  static String pageOf(int i, int n) => 'עמוד ${i + 1} מתוך $n';
  static const pageFailed = 'העמוד לא נטען. נגיעה לניסיון חוזר';
  static const leaveTitle = 'לצאת בלי לשמור?';
  static const leaveBody = 'השדות שסימנת לא יישמרו.';
  static const leave = 'יציאה';
  static const stay = 'להמשיך לערוך';

  static String kind(SignFieldKind k) => switch (k) {
    SignFieldKind.signature => 'חתימה',
    SignFieldKind.text => 'טקסט',
    SignFieldKind.date => 'תאריך',
    SignFieldKind.checkbox => 'תיבת סימון',
    SignFieldKind.initials => 'ראשי תיבות',
  };

  // Send
  static const sendTitle = 'שליחה לחתימה';
  static const signerSection = 'למי שולחים?';
  static const pickCustomer = 'בחירת לקוח קיים';
  static const signerName = 'שם החותם/ת';
  static const signerEmail = 'אימייל';
  static const signerPhone = 'טלפון';
  static const message = 'הודעה ללקוח (לא חובה)';
  static const expiry = 'תוקף הקישור';
  static String expiryOn(String date) => 'עד $date';
  static const notifyOnView = 'עדכנו אותי כשהלקוח פותח את המסמך';
  static const sendEmail = 'שליחה באימייל';
  static const sendWhatsApp = 'וואטסאפ';
  static const sendShare = 'שיתוף קישור';
  static const nameRequired = 'נא למלא את שם החותם/ת';
  static const emailRequired = 'לשליחה באימייל צריך כתובת אימייל';
  static const phoneRequired = 'לוואטסאפ צריך מספר טלפון תקין';
  static const sentEmail = 'המסמך נשלח לחתימה באימייל';
  static const emailFailed = 'המייל לא נשלח, אפשר לשתף את הקישור';
  static const sent = 'המסמך מוכן לחתימה';
  static String shareText(String title, String url) =>
      'שלום, מצורף מסמך לחתימה: $title\n$url';

  // Detail
  static const detailTitle = 'מסמך לחתימה';
  static const signer = 'החותם/ת';
  static const timeline = 'מה קרה עם המסמך';
  static const viewSigned = 'צפייה במסמך החתום';
  static const shareSigned = 'שיתוף המסמך החתום';
  static const viewOriginal = 'המסמך המקורי';
  static const editFields = 'עריכת שדות ושליחה';
  static const remind = 'שליחת תזכורת';
  static const remindTitle = 'איך להזכיר?';
  static const reminded = 'התזכורת נשלחה';
  static const cancel = 'ביטול הבקשה';
  static const cancelConfirmTitle = 'לבטל את הבקשה לחתימה?';
  static const cancelConfirmBody = 'הקישור ששלחת יפסיק לעבוד.';
  static const cancelYes = 'ביטול הבקשה';
  static const cancelNo = 'השארה';
  static const cancelled = 'הבקשה בוטלה';
  static String filledOf(int filled, int total) =>
      'מולאו $filled מתוך $total שדות';
  static const sealedYes = 'המסמך החתום נחתם גם בחותמת הדיגיטלית של העסק';
  static const sealedNo = 'המסמך נשמר ללא חותמת דיגיטלית של העסק';
  static String sha(String s) =>
      'טביעת אצבע (SHA-256): ${s.length > 16 ? s.substring(0, 16) : s}…';
  static String ip(String ip) => 'IP $ip';

  static String status(SignStatus s) => switch (s) {
    SignStatus.draft => 'טיוטה',
    SignStatus.sent => 'נשלח',
    SignStatus.viewed => 'נצפה',
    SignStatus.completed => 'נחתם',
    SignStatus.expired => 'פג תוקף',
    SignStatus.cancelled => 'בוטל',
  };

  static String event(String type) => switch (type) {
    'CREATED' => 'המסמך הועלה',
    'SENT' => 'נשלח לחתימה',
    'REMINDED' => 'נשלחה תזכורת',
    'VIEWED' => 'הלקוח פתח את המסמך',
    'COMPLETED' => 'מולא ונחתם',
    'CANCELLED' => 'הבקשה בוטלה',
    'SEALED' => 'נוספה חותמת דיגיטלית של העסק',
    _ => type,
  };

  static String channel(String? c) => switch (c) {
    'EMAIL' => 'באימייל',
    'WHATSAPP' => 'בוואטסאפ',
    'SHARE' => 'בקישור',
    _ => '',
  };
}
