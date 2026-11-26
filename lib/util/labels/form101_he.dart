// "טופס 101 לעובד" (server 0134) — every Hebrew string of the employees /
// form-101 screens.

import '../../api/form101_api.dart';

abstract final class Form101He {
  static const title = 'עובדים וטופס 101';
  static const row = 'עובדים · טופס 101';
  static const signEntry = 'טופס 101 לעובד';
  static const signEntryHint = 'העובד ממלא בטלפון וחותם, והטופס חוזר אליך';
  static const intro =
      'שולחים לעובד קישור, הוא ממלא בטלפון שאלון קצר וחותם — והטופס חוזר אליך במבנה הרשמי.';
  static const viewOnly = 'צפייה בלבד: את הטפסים שולח בעל העסק.';
  static String yearChip(int y) => 'שנת המס $y';
  static const addEmployee = 'עובד חדש';
  static const emptyTitle = 'עוד אין עובדים';
  static const emptyHint =
      'מוסיפים עובד (שם וטלפון או מייל) ושולחים לו טופס 101 לשנת המס.';
  static const blankPdf = 'טופס ריק להדפסה';
  static const blankHint = 'לעובד בלי סמארטפון: פרטי המעסיק כבר ממולאים';
  static const archived = 'עובדים שעזבו';
  static const notSent = 'לא נשלח';
  static String lastYear(int y) => 'מילא/ה טופס $y';

  static String status(Form101Status s) => switch (s) {
    Form101Status.sent => 'נשלח',
    Form101Status.viewed => 'נפתח',
    Form101Status.completed => 'הוחזר חתום',
    Form101Status.expired => 'פג תוקף',
    Form101Status.cancelled => 'בוטל',
  };

  // Season (January)
  static String seasonTitle(int y) => 'הגיע הזמן ל-101 של $y';
  static String seasonBody(int n) => n == 1
      ? 'עובד אחד מילא בשנה שעברה. שולחים לו את הטופס עם הפרטים ממולאים מראש.'
      : '$n עובדים מילאו בשנה שעברה. שולחים לכולם בנגיעה, עם הפרטים ממולאים מראש.';
  static const seasonSend = 'שליחה לכולם';
  static const seasonQueueTitle = 'שליחה לעובדים';
  static String seasonQueueHint(int emailed, int left) => [
    if (emailed > 0) '$emailed נשלחו במייל.',
    if (left > 0) 'לשאר — נגיעה לכל עובד פותחת וואטסאפ עם הקישור.',
  ].join(' ');
  static const seasonEmailed = 'נשלח במייל';
  static const seasonSentWa = 'נשלח';
  static const done = 'סיום';

  // Employee editor
  static const editTitle = 'פרטי העובד';
  static const fullName = 'שם מלא';
  static const phone = 'טלפון נייד';
  static const email = 'אימייל (לא חובה)';
  static const nameRequired = 'נא למלא שם (2 תווים לפחות)';
  static const contactRequired = 'נא למלא טלפון או אימייל';
  static const save = 'שמירה';
  static const markLeft = 'העובד/ת עזב/ה';
  static const restore = 'החזרה לרשימה';
  static const saved = 'נשמר';

  // Send
  static const sendTitle = 'שליחת טופס 101';
  static const send = 'שליחת טופס 101';
  static const sendUpdate = 'שליחת טופס עדכון';
  static const updateHint =
      'באמצע השנה (נולד ילד, עבר דירה…): הטופס נפתח עם הפרטים הקודמים';
  static const year = 'שנת המס';
  static const channel = 'איך לשלוח?';
  static const viaWhatsApp = 'וואטסאפ';
  static const viaSms = 'SMS';
  static const viaEmail = 'מייל';
  static const viaShare = 'שיתוף';
  static const needPhone = 'לשליחה בוואטסאפ או SMS צריך טלפון';
  static const needEmail = 'לשליחה במייל צריך אימייל';
  static const alreadySent =
      'לעובד כבר יש טופס לשנה הזו — אפשר לשלוח שוב מתוך הטופס, או טופס עדכון';

  // Code
  static const codeTitle = 'הקישור נשלח';
  static const codeBody =
      'בכניסה לטופס העובד מתבקש קוד חד-פעמי. שולחים לו אותו בהודעה נפרדת:';
  static const codeEmailHint = 'לעובד עם מייל: אפשר גם לבקש את הקוד מהדף.';
  static const sendCodeSms = 'שליחת הקוד ב-SMS';
  static const copyCode = 'העתקה';
  static const copied = 'הועתק';
  static const newCode = 'קוד חדש';

  static String linkText(String business, int year, String url) =>
      'שלום, זה הקישור למילוי טופס 101 לשנת $year עבור $business: $url\nבכניסה תתבקש/י קוד אימות שישלח בנפרד.';
  static String codeText(String business, String code) =>
      'קוד הכניסה לטופס 101 של $business: $code';

  // Detail
  static String detailTitle(String name) => 'טופס 101 · $name';
  static String kindLine(Form101Kind k, int year) =>
      k == Form101Kind.update ? 'טופס עדכון · $year' : 'טופס שנתי · $year';
  static String expiresOn(String d) => 'הקישור בתוקף עד $d';
  static String stepOf(int n) => 'מילא/ה $n שלבים עד עכשיו';
  static const viewPdf = 'צפייה בטופס החתום';
  static const sharePdf = 'שיתוף הטופס';
  static const toAccountant = 'שליחה לרואה החשבון';
  static String sentToAccountant(String to) => 'נשלח ל-$to';
  static const noAccountant =
      'אין מייל של רואה החשבון בפרטי העסק. מוסיפים אותו בפרטי העסק → רואה החשבון.';
  static const resend = 'שליחה שוב';
  static const resendHint =
      'קישור חדש וקוד חדש, בתוקף ל-14 יום. מה שמולא נשמר.';
  static const cancel = 'ביטול הבקשה';
  static const cancelTitle = 'לבטל את הטופס?';
  static const cancelBody = 'הקישור יפסיק לעבוד. אפשר לשלוח טופס חדש אחר כך.';
  static const cancelYes = 'ביטול הטופס';
  static const cancelNo = 'חזרה';
  static const cancelled = 'הטופס בוטל';
  static const attachments = 'צרופות';
  static const audit = 'מעקב ואימות';
  static String retain(String d) =>
      'נשמר מוצפן עד $d · רק לבעלים ולרואה החשבון';
  static const history = 'טפסים קודמים';

  static String event(Form101Event e) => switch (e.type) {
    'SENT' => 'נשלח${_via(e.channel)}',
    'RESENT' => 'נשלח שוב${_via(e.channel)}',
    'VIEWED' => 'העובד/ת פתח/ה את הקישור',
    'CODE_EMAILED' => 'קוד נשלח למייל',
    'CODE_FAILED' => 'שליחת קוד למייל נכשלה',
    'VERIFIED' => 'אומת/ה בקוד · ${e.detail ?? ''}',
    'COMPLETED' => 'נחתם · ${e.detail ?? ''}',
    'CANCELLED' => 'בוטל',
    'OWNER_VIEWED' => 'נצפה ע״י ${e.actorName ?? ''}',
    'PDF_VIEWED' => 'הטופס נפתח ע״י ${e.actorName ?? ''}',
    'ATTACHMENT_VIEWED' => 'צרופה נפתחה ע״י ${e.actorName ?? ''}',
    'SENT_TO_ACCOUNTANT' => 'נשלח לרואה החשבון · ${e.detail ?? ''}',
    _ => e.type,
  };

  static String _via(String? c) => switch (c) {
    'EMAIL' => ' במייל',
    'WHATSAPP' => ' בוואטסאפ',
    'SMS' => ' ב-SMS',
    'SHARE' => ' בשיתוף',
    _ => '',
  };

  static String attachment(String kind) => switch (kind) {
    'ID' => 'תעודת זהות וספח',
    'PASSPORT' => 'דרכון',
    'STAY_PERMIT' => 'אישור שהייה',
    'SEPARATION' => 'אישור פקיד שומה (פרוד/ה)',
    'DISABILITY' => 'אישור נכות / עיוורון',
    'DISABILITY_ALLOWANCE' => 'אישור תגמול חודשי',
    'SETTLEMENT_1312A' => 'טופס 1312א',
    'IMMIGRANT_CERT' => 'תעודת עולה',
    'SUPPORT_RULING' => 'פסק דין מזונות',
    'DISABLED_CHILD' => 'אישור גמלת ילד נכה',
    'ALIMONY_RULING' => 'פסק דין מזונות לבן/בת זוג לשעבר',
    'DISCHARGE_CERT' => 'תעודת שחרור',
    'FORM_119' => 'טופס 119',
    'RESERVIST_CERT' => 'אישור מילואים',
    'NO_INCOME_PROOF' => 'הוכחה שלא הייתה הכנסה',
    'ASSESSOR_APPROVAL' => 'אישור תיאום מס',
    _ => 'מסמך נוסף',
  };

  static const loadFailed = 'לא הצלחנו לטעון';
  static const sendFailed = 'השליחה לא הצליחה';
}
