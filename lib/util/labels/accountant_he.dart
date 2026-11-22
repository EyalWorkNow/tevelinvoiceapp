// Accountant multi-business (spec "רואה חשבון באפליקציית תבל", 2026-11-22).

import '../../state/caps.dart' show isFullAccountantRole;

abstract final class AccountantHe {
  // 1 · "הלקוחות שלי" row on the accountant home.
  static const myClients = 'הלקוחות שלי';
  static String clients(int n) => n == 1 ? 'לקוח אחד' : '$n לקוחות';
  static String needAttention(int n) =>
      n == 1 ? 'אחד דורש טיפול' : '$n דורשים טיפול';
  static const allClear = 'הכול מסודר';

  // 2 · add a client / access requests.
  static const addClient = '＋ הוספת לקוח';
  static const addFirstClient = '＋ הוספת לקוח ראשון';
  static const addClientTitle = 'הוספת לקוח';
  static const addClientHint =
      'נשלח לבעל העסק בקשה לאשר לך גישה. עד האישור לא תראה שום נתון של העסק.';
  static const contactLabel = 'מייל או טלפון נייד של בעל העסק';
  static const contactInvalid = 'צריך מייל או מספר נייד (05X-XXXXXXX)';
  static const roleLabel = 'סוג הגישה';
  static const roleRep = 'רו״ח מייצג';
  static const roleFull = 'רו״ח מלא';
  static const roleRepHint =
      'צפייה, אישור הוצאות, דוחות וייצוא. בלי הפקת מסמכים.';
  static const roleFullHint = 'כמעט כל מה שבעל העסק יכול, כולל הפקת מסמכים.';
  static String roleName(String role) =>
      isFullAccountantRole(role) ? roleFull : roleRep;
  static const send = 'שליחת בקשה';
  static const sending = 'שולח…';
  static const sentTitle = 'הבקשה מוכנה';
  static String emailedTo(String contact) => 'נשלח מייל אל $contact';
  static const sendWhatsapp = 'שליחה בוואטסאפ';
  static const copyLink = 'העתקת הקישור';
  static const linkCopied = 'הקישור הועתק';
  static const done = 'סיום';
  static const rateLimited =
      'כבר נשלחו 3 בקשות לאותו נמען היום. אפשר לנסות שוב מחר.';
  static const pending = 'ממתין לאישור';
  static const declined = 'הבקשה לא אושרה';
  static const expired = 'פג תוקף הבקשה';
  static const resend = 'שליחה שוב';
  static const cancel = 'ביטול';
  static const cancelled = 'הבקשה בוטלה';
  static String pendingCount(int n) =>
      n == 1 ? 'בקשה אחת ממתינה לאישור' : '$n בקשות ממתינות לאישור';

  // 3 · badges.
  static String tasksSemantics(int n) =>
      n == 1 ? 'משימה אחת לטיפול' : '$n משימות לטיפול';
  static const reviewedSemantics = 'התקופה הקודמת נבדקה';

  // 5 · "אני רו״ח".
  static const iAmAccountant = 'אני רו״ח ומלווה עסקים';
  static const officeTitle = 'שם המשרד';
  static const officeHint = 'השם מופיע לבעלי העסק בבקשת הגישה.';
  static const officeLabel = 'שם המשרד';
  static const officeRequired = 'צריך שם משרד';
  static const officeSave = 'המשך';
  static const officeSaved = 'שם המשרד נשמר';
  static const emptyTitle = 'עוד אין לקוחות';
  static const emptyBody =
      'שלחו לבעל עסק בקשת גישה. כשהוא מאשר, העסק מופיע כאן.';
  static const settings = 'הגדרות';

  // 6 · period review.
  static const markReviewed = 'סימון כנבדק';
  static const reviewed = 'נבדק';
  static const unmarkReviewed = 'ביטול הסימון';
  static const reviewedSaved = 'התקופה סומנה כנבדקת';
  static const reviewedRemoved = 'הסימון בוטל';

  // 7 · leave.
  static const leave = 'הפסקת ליווי';
  static String leaveTitle(String business) => 'להפסיק ללוות את $business?';
  static const leaveBody =
      'לא תהיה לך יותר גישה לעסק. שום נתון לא נמחק, ובעל העסק יקבל הודעה.';
  static const leaveConfirm = 'הפסקת ליווי';
  static const leaveCancel = 'ביטול';
  static const left = 'הליווי הופסק';

  // 8 · reminder to the owner.
  static const remind = 'תזכורת לבעלים';
  static String reminderText(String business, List<String> parts) =>
      'שלום, כאן רו״ח של $business. כדי שאוכל לסגור את התקופה חסרים: '
      '${parts.join(', ')}. תודה!';
  static String expenses(int n) =>
      n == 1 ? 'הוצאה אחת לאישור' : '$n הוצאות לאישור';
  static String paymentsWithoutReceipt(int n) =>
      n == 1 ? 'תשלום אחד בלי קבלה' : '$n תשלומים בלי קבלה';
  static String taxInvoicesDue(int n) =>
      n == 1 ? 'חשבונית מס אחת ממתינה' : '$n חשבוניות מס ממתינות';
  static String numberingGaps(int n) =>
      n == 1 ? 'פער אחד במספור המסמכים' : '$n פערים במספור המסמכים';
  static String correctionsAnswered(int n) =>
      n == 1 ? 'בקשת תיקון אחת שנענתה' : '$n בקשות תיקון שנענו';

  // Owner side: approve the access request (/m/access/:token).
  static const approveTitle = 'בקשת גישה מרו״ח';
  static String asks(String name) => '$name מבקש/ת גישה לעסק שלך';
  static const canDoTitle = 'מה הרו״ח יוכל לעשות';
  static const canRep = [
    'לראות מסמכים, הוצאות ודוחות של העסק',
    'לאשר הוצאות ולבקש ממך תיקון או זיכוי',
    'להוריד דוחות וקבצים לדיווח',
  ];
  static const canFull = [
    'לראות מסמכים, הוצאות ודוחות של העסק',
    'להפיק חשבוניות וקבלות בשם העסק',
    'לאשר הוצאות ולהוריד דוחות וקבצים לדיווח',
  ];
  static const pickBusiness = 'לאיזה עסק?';
  static const approve = 'אישור גישה';
  static const decline = 'סירוב';
  static const approved = 'הרו״ח נוסף לצוות';
  static const declinedDone = 'הבקשה נדחתה';
  static const removeAnytime = 'אפשר להסיר את הרו״ח מדף הצוות בכל רגע.';
  static const notFound =
      'הבקשה כבר לא בתוקף. אפשר לבקש מהרו״ח לשלוח בקשה חדשה.';
  static const noManagedBusiness =
      'אין לך עסק שאפשר לנהל בו צוות, ולכן אי אפשר לאשר את הבקשה מהחשבון הזה.';
  static const alreadyMember = 'הרו״ח כבר בצוות של העסק הזה';

  // 4 · push.
  static const pushApproved = 'בעל העסק אישר את בקשת הגישה';
  static const pushCorrection = 'בקשת התיקון טופלה';
  static const pushDigest = 'הוצאות מחכות לאישור';
  static const pushLeft = 'רו״ח הפסיק ללוות את העסק';
  static const prefsTitle = 'התראות לרו״ח';
  static const prefApproved = 'בקשת גישה אושרה';
  static const prefApprovedHint = 'כשבעל עסק מאשר לך גישה';
  static const prefCorrection = 'בקשת תיקון טופלה';
  static const prefCorrectionHint = 'כשבעל העסק ביצע זיכוי או דחה בקשה שפתחת';
  static const prefDigest = 'הוצאות מחכות לאישור';
  static const prefDigestHint = 'פעם ביום ב-09:00, הודעה אחת לכל העסקים';
}
