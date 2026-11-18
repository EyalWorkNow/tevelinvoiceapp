// Business / team / reports / sign-in wording (squad E). F11: imperative verbs.
// Every Hebrew string that appears on a button in A, B, R, S13, S14 lives here.

import '../../api/auth_api.dart' show MfaMethods;
import '../../state/caps.dart' show Preset;

const Map<String, String> businessTypeLabels = {
  'OSEK_PATUR': 'עוסק פטור',
  'OSEK_MURSHE': 'עוסק מורשה',
  'COMPANY': 'חברה בע"מ',
  'PARTNERSHIP': 'שותפות',
  'NONPROFIT': 'עמותה / מלכ"ר',
};

/// One sentence under each business type card (§6.A step 1).
const Map<String, String> businessTypeHints = {
  'OSEK_PATUR': 'בלי מע״מ · חשבון עסקה וקבלה',
  'OSEK_MURSHE': 'גובה מע״מ · חשבונית מס',
  'COMPANY': 'ח.פ. · חשבונית מס',
  'PARTNERSHIP': 'גובה מע״מ · חשבונית מס',
  'NONPROFIT': 'קבלות ותרומות',
};

/// V1 server role names (display only, e.g. S14 role tag fallback).
const Map<String, String> roleLabels = {
  'OWNER': 'בעלים',
  'ADMIN': 'שותף',
  'ACCOUNTANT': 'רו״ח – מלא',
  'ACCOUNTANT_REP': 'רואה חשבון',
  'EMPLOYEE': 'עובד',
  'CASHIER': 'קופאי/ת',
  'READ_ONLY': 'צפייה בלבד',
};

/// B · עסק rows and sub-pages (§6.B, §13).
abstract final class BusinessHe {
  // Owner 2026-11-16: פרטי ההרשמה וייצוא (business data page).
  static const archivePreparing = 'מכין קובץ…';
  static const archiveDownload = 'הורדת כל התוכן כ־ZIP';

  /// B1 (§13.6): the cashier cap.
  static const approvalsCashierCap = 'קופאי/ת מפיק/ה בלי אישור עד';
  static const approvalsCashierCapHint =
      'סכום כולל מע״מ. מעל הסכום הזה הקבלה נשלחת לאישורך, והתשלום ממתין איתה.';

  static String monthlySubscriptionPrice(String price) =>
      'מינוי חודשי · $price';
  static String securePaymentPrice(int amountMinor) =>
      'לתשלום מאובטח · ₪${amountMinor ~/ 100}';
  // Action labels shared by the application screens.
  static const disconnectAction = 'ניתוק';
  static const openingPreview = 'פותחים תצוגה מקדימה';
  static const savingTerminal = 'שומרים פרטי מסוף';
  static const disconnectTerminal = 'ניתוק המסוף';
  static const checkCardcom = 'בדיקה מול קארדקום';
  static const paymentPreviewTitle = 'זו תצוגה מקדימה';
  static const paymentPreviewBody =
      'המסך מציג את אפשרויות התשלום לדוגמה. לא בוצע חיוב ולא נשלחו פרטים לקארדקום.';
  static const securePayment = 'לתשלום מאובטח';
  static const continueToInvoice = 'המשך לחשבונית';
  static const enlargePreview = 'הגדלת התצוגה';
  static const retryPreview = 'התצוגה לא נטענה. נסה שוב';
  static const saveBranding = 'שמירת העיצוב';
  static const chooseLogo = 'בחירת לוגו';
  static const removeLogo = 'הסרת הלוגו';
  static const scanInvoiceAction = 'סריקה לקבלת החשבונית';
  static const preparingLink = 'מכינים קישור…';
  static const validPhoneRequired = 'יש להזין מספר טלפון תקין';
  static const messageSentFromDevice = 'ההודעה נשלחה מהמכשיר';
  static const smsUnavailable =
      'שליחת SMS אינה זמינה במכשיר הזה. אפשר לקבל את המסמך בסריקה או במייל.';
  static const smsFailed = 'ההודעה לא נשלחה. ניתן לנסות שוב.';
  static const openingMessage = 'פותחים הודעה לשליחה';
  static const keepSubscription = 'נשארים במסלול';
  static const cancelRenewalAction = 'ביטול החידוש';
  static const manageAppleSubscription = 'ניהול מינוי Apple';
  static const cancelPlanRenewal = 'ביטול חידוש המסלול';
  static const selectPlanAndPay = 'בחירת המסלול והמשך לתשלום';
  static const termsAction = 'תנאי שימוש';
  static const privacyAction = 'מדיניות פרטיות';
  static const restorePurchasesAction = 'שחזור רכישות';
  static const checkingPayment = 'בודקים את התשלום…';
  static const checkPaymentApproval = 'בדיקת אישור התשלום';
  static const backToBusiness = 'חוזרים לעסק';
  static const planLater = 'אולי אחר כך';
  static const waitingForAppStore = 'ממתינים ל־App Store…';
  static const preparingCheckout = 'מכינים את דף התשלום…';

  static const title = 'עסק';
  static const reports = 'דוחות';
  static const expenses = 'הוצאות';
  static const team = 'צוות והרשאות';
  static const profile = 'פרטי העסק';
  static const branding = 'עיצוב מסמכים ומיתוג';
  static const approvals = 'אישורים';
  static const shaam = 'רשות המסים וחתימה';
  static const account = 'החשבון שלי';
  static const desktop = 'המשך במחשב';
  static const moreSettings = 'עוד הגדרות';
  static const numbering = 'מספור ואישורים';
  static const switchBusiness = 'החלף';
  // 06·U8: leaving a form with changes.
  static const discardTitle = 'לצאת בלי לשמור?';
  static const discardBody = 'השינויים שעשית לא יישמרו.';
  static const discardAction = 'צא בלי לשמור';
  static const keepEditing = 'המשך עריכה';
  static const switchTitle = 'החלפת עסק';
  static const searchBusiness = 'חיפוש עסק';
  static const active = 'פעיל';
  static const addBusiness = '+ עסק נוסף';
  static const showMoreBusinesses = 'הצג עוד';
  // P1/P2 rows and fields
  static const reminders = 'תזכורות אוטומטיות';
  static const remindersHint = 'מייל ללקוחות שלא שילמו, לפי לוח זמנים קבוע';
  static const remindersOn = 'תזכורות אוטומטיות פועלות';
  static const remindersOff = 'תזכורות אוטומטיות כבויות';
  static const remindersConfirmTitle = 'להפעיל תזכורות אוטומטיות?';

  /// #10a: a COMP plan (no store, no charge) — nothing to renew or cancel.
  static const compPlan = 'מסלול ללא חיוב מתבל. אין חידוש לבטל.';
  // #9b: only what is due from today gets the ladder; old debts wait for a
  // separate "yes" (תזכורות גבייה אוטומטיות).
  static const remindersConfirmBody =
      'לקוח שלא שילם יקבל ממך תזכורת עם קישור למסמך, לפי לוח זמנים קבוע, '
      'על מסמכים שמועד התשלום שלהם היום או אחריו. חובות ישנים לא יקבלו תזכורת '
      'בלי שתאשר. אפשר לכבות בכל רגע.';
  static const remindersConfirmAction = 'הפעל';
  static const ccOwner = 'עותק של כל מסמך אליי';
  static const ccOwnerHint = 'כל מסמך שנשלח ללקוח במייל יגיע גם אליך';
  static const accountantAuto = 'שליחה אוטומטית לרו״ח';
  static const accountantAutoOff = 'לא לשלוח';
  static const accountantAutoMonth = 'כל חודש';
  static const accountantAutoBimonth = 'כל חודשיים';
  static const accountantAutoDay = 'ביום בחודש';
  static const accountantForward = 'להעביר לרו״ח כל מסמך שהופק';
  static const advanceRate = 'מקדמות מס הכנסה (%)';
  static const advanceRateInvalid = 'אחוז בין 0 ל-100';
  static const accountantEmailNeeded = 'לשליחה אוטומטית צריך את מייל הרו״ח';
  static const typeChange = 'עוברים לעוסק מורשה';
  static const typeChangeTitle = 'מעבר לעוסק מורשה';
  static const typeChangeBody =
      'מהתאריך שתבחר המסמכים יופקו כעוסק מורשה. מסמכים שכבר הופקו לא משתנים.';
  static const typeChangeFrom = 'מתי?';
  static const typeChangeToday = 'מהיום';
  static const typeChangeNextMonth = 'מתחילת החודש הבא';
  static const typeChangeNextYear = 'מתחילת השנה הבאה';
  static const typeChangeSave = 'שמור מעבר';
  static const typeChangeSaved = 'המעבר נשמר ✓';

  // S13 instances.
  static const edit = 'ערוך';
  static const saved = 'נשמר ✓';
  static const identityLocked =
      'אחרי הפקה ראשונה לא משנים סוג עסק כאן – המשך במחשב';
  static const brandingLogo = 'לוגו';
  static const brandingPickLogo = 'בחר לוגו מהתמונות';
  static const brandingRemoveLogo = 'הסר לוגו';
  static const brandingColor = 'צבע';
  static const approvalsSwitch = 'מסמכים גדולים צריכים אישור';
  static const approvalsThreshold = 'מסמכים מ-₪ (כולל מע״מ)';
  static String approvalsSelf(String name) =>
      'גם מסמכים שאני יוצר צריכים אישור של $name';
  static const approvalsOtherMember = 'חבר צוות נוסף';
  static const desktopIntro = 'נשלח לך מייל עם קישור לדף הנכון במחשב.';
  static const desktopSend = 'שלח לי קישור במייל';
  static const desktopSent = 'שלחנו לך קישור למייל';

  // רשות המסים וחתימה (§13.7–13.8).
  static const shaamTitle = 'רשות המסים';
  static const shaamConnect = 'התחבר / חדש';
  static const shaamConnected = 'מחובר לרשות המסים';
  static const shaamNotConnected = 'לא מחובר לרשות המסים';
  static const shaamExpired = 'החיבור לרשות המסים פג';
  static const shaamOff =
      'החיבור לרשות המסים עדיין לא הופעל. חשבוניות שדורשות מספר הקצאה ימתינו עד ההפעלה';

  /// עוסק פטור / עמותה: no allocation numbers, so nothing waits (persona 01).
  static const shaamNotNeeded = 'לעוסק פטור לא נדרש מספר הקצאה מרשות המסים';
  static String shaamValidUntil(String date) => 'בתוקף עד $date';
  static String shaamVerified(String date) => 'נבדק לאחרונה $date';
  static const shaamManual = 'הזנה ידנית של מספר הקצאה פעילה';
  static const signingTitle = 'חתימה דיגיטלית';
  static const signingActive = 'החתימה פעילה';
  static const signingWillUnlock = 'תשוחרר ב-Face ID בהפקה הבאה';
  static const signingNotConfigured = 'לא הוגדרה חתימה – המשך במחשב';
  static const signingForget = 'שכח את סיסמת החתימה מהמכשיר';
  static const signingForgotten = 'הסיסמה נמחקה מהמכשיר';

  // B·חשבון (§13.11–13.15).
  static const signedInAs = 'מחובר כ';
  static const faceId = 'נעילה ב-Face ID';
  static const hideAmounts = 'הסתר סכומים';
  static const twoFactor = 'אימות דו-שלבי';
  static const twoFactorEmail = 'קוד במייל';
  static const twoFactorApp = 'אפליקציית אימות וקודי שחזור';

  /// The enrolled second factors, as the server reports them.
  static String twoFactorState(MfaMethods m) => m.totp && m.email
      ? 'אפליקציה + קוד במייל'
      : m.totp
      ? 'אפליקציית אימות'
      : m.email
      ? 'קוד במייל'
      : 'לא מוגדר';
  static String twoFactorAppOn(int codes) =>
      codes == 1 ? 'מחוברת · קוד שחזור אחד' : 'מחוברת · $codes קודי שחזור';
  static const signOut = 'צא מהמכשיר';
  static const signOutAll = 'צא מכל המכשירים';
  static const signOutConfirm = 'לצאת מהמכשיר?';
  static const signOutBody =
      'כדי לחזור תצטרך להיכנס שוב עם האימייל והסיסמה. המסמכים נשמרים בחשבון.';
  static const signOutPendingBody =
      'יש במכשיר פעולה שעוד לא נשלחה, והיא תימחק. כדי לחזור תצטרך להיכנס שוב.';
  static const sendErrorLog = 'שלח יומן תקלות';
  static const errorLogEmpty = 'אין תקלות ביומן';
  static String errorLogCount(int n) => n == 1 ? 'תקלה אחת' : '$n תקלות';
  static const signOutAllConfirm = 'לצאת מכל המכשירים?';
  static const signOutAllBody =
      'כל הטלפונים והדפדפנים יתנתקו, כולל הטלפון הזה.';
  static const privacy = 'מדיניות הפרטיות';
  static const terms = 'תנאי השימוש';
  static const support = 'תמיכה';
  static const version = 'גרסה';
  static const deleteAccount = 'מחק חשבון';

  // Sole owner warning (§13.15).
  static const soleOwnerTitle = 'לפני שמוחקים';
  static String soleOwnerBody(String business, int n, String names) => n == 0
      ? 'המחיקה תסגור את $business. המסמכים נשמרים ונעולים 7 שנים לפי החוק ולא יימחקו.'
      : 'המחיקה תסגור את $business. $n חברי צוות ($names) יאבדו גישה. '
            'המסמכים נשמרים ונעולים 7 שנים לפי החוק ולא יימחקו.';
  static const deleteAnyway = 'מחק בכל זאת';
  static const transferInstead =
      'אפשר להעביר את הבעלות לחבר צוות, והעסק ימשיך לעבוד בלעדיך.';
  static String soleOwnerOther(String business) =>
      'גם $business ייסגר אם אין בו בעלים נוסף. המסמכים שלו נשמרים.';

  // Setup waiting (§6.A, member of a business that is not set up yet).
  static String setupPending(String owner) =>
      '$owner עדיין מסיים להגדיר את העסק';
  static const setupPendingOwner = 'בעל העסק';
  static const setupPendingBody = 'אפשר להתחיל לעבוד כשההגדרה תסתיים.';

  // No business at all.
  static const noBusinessTitle = 'החשבון שלך עוד בהקמה — נחזור אליך';
  static String noBusinessBody(String email) =>
      'צוות תבל עוד מקים את העסק בחשבון $email. כשהוא מוכן נעדכן אותך, '
      'ואז "בדוק שוב" יכניס אותך. אם הוזמנת לעסק של מישהו אחר — בקש/י ממנו '
      'לשלוח הזמנה חדשה.';
  static const checkAgain = 'בדוק שוב';

  /// Walkthrough 2026-11-17 #14: "בדוק שוב" found the business, but this
  /// device signed in before it needed two-step verification (an owner /
  /// accountant membership). The server refuses such a device token, so the
  /// user signs in once more — told why, email filled in, never "פג תוקף".
  static const signInAgainForMfa =
      'נמצא עסק בחשבון. כדי להיכנס אליו צריך אימות דו-שלבי, ולכן צריך להתחבר שוב פעם אחת.';
}

/// "המשך במחשב" topics (§13.9) → BE-35 topic keys. Labels from the server list.
const Map<String, String> desktopTopics = {
  'MORE_DOCUMENT_TYPES': 'סוגי מסמכים נוספים',
  'INVENTORY': 'מלאי ומחסנים',
  'CUSTOM_PERMISSIONS': 'הרשאות מותאמות',
  'ADVANCED_BRANDING': 'מיתוג מתקדם',
  'MESSAGE_TEMPLATES': 'נוסחי הודעות',
  'RECEIPT_CANCEL': 'ביטול קבלה',
  'TAX_AUTHORITY': 'רשות המסים',
  'BUSINESS_TYPE_CHANGE': 'שינוי סוג עסק',
  'CSV_IMPORT': 'ייבוא CSV',
  'CUSTOMER_MERGE': 'מיזוג לקוחות',
  'UNIFORM_FORMAT': 'שידור מבנה אחיד',
  'SIGNING_CERTIFICATE': 'תעודת חתימה',
  'BOOKKEEPING_CERTIFICATES': 'אישורי ניהול ספרים',
  'LOGIN_EMAIL_CHANGE': 'שינוי אימייל כניסה',
  'API_INTEGRATIONS': 'API ותוספים',
};

/// B·צוות + S13 "חבר צוות" (§12).
abstract final class TeamHe {
  static const invite = '+ הזמן';
  static const inviteAccountant = 'הזמן רואה חשבון';
  static const sendInvite = 'שלח הזמנה';
  static const inviteTitle = 'הזמנה לצוות';
  static const email = 'אימייל';
  static const emailInvalid = 'נא להזין כתובת מייל תקינה';
  static const invited = 'ההזמנה נשלחה';
  static const resend = 'שלח שוב';
  static const resent = 'ההזמנה נשלחה שוב';
  static const sendWhatsApp = 'שלח קישור בווטסאפ';
  static const sendWhatsAppShort = 'שלח בווטסאפ';
  static const revokeInvite = 'בטל הזמנה';
  static const revokeInviteConfirm = 'לבטל את ההזמנה?';
  static const remove = 'הסר מהעסק';
  static String removeConfirm(String name) => 'להסיר את $name מהעסק?';
  static const removeBody = 'הגישה לעסק תיסגר מיד. המסמכים שיצר נשמרים.';
  static const memberTitle = 'חבר צוות';
  static const issuer = 'מפיק בעצמו';
  static const issuerHint =
      'יוכל להפיק מסמכים ולרשום תשלומים בשמך. לא יוכל לבטל או לאשר '
      'מסמכים של אחרים. יתבקש אימות דו-שלבי.';
  static const more = 'עוד ▾';
  static const custom = 'מותאם אישית';
  static const transfer = 'העבר בעלות';
  static String transferConfirm(String name) => 'להעביר את הבעלות ל-$name?';
  static const transferBody =
      'הוא יהיה בעל העסק ואת/ה תהיה/י שותף/ה. נשלח אליך קוד במייל לאישור.';
  static const transferCodeTitle = 'קוד לאישור העברת הבעלות';
  static const transferCodeWrong = 'הקוד שגוי. נסה שוב.';
  static String transferred(String name) => 'הבעלות הועברה ל-$name';
  static const customHint =
      'לחבר הזה יש הרשאות מותאמות. שינוי שלהן – המשך במחשב.';
  static const completing = 'משלים הגדרה…';
  static String upgradeConfirm(String name) =>
      'לעדכן את רו״ח $name להרשאות רו״ח מייצג? יידרש אימות דו-שלבי';
  static const upgrade = 'עדכן';
  static const upgraded = 'ההרשאות עודכנו';
  static const upgradeUnsupported =
      'עדיין אי אפשר לעדכן להרשאות רו״ח מייצג. נסו שוב בהמשך';
  static const you = '(את/ה)';
  static String pending(int days) => days <= 0
      ? 'ממתין · פג היום'
      : (days == 1 ? 'ממתין · פג מחר' : 'ממתין · פג בעוד $days ימים');
  static const expired = 'פג תוקף';
  static const empty = 'רק את/ה בעסק כרגע';
  static const emptyHint = 'הזמן עובד, שותף או רואה חשבון.';
  static String waText(String business, String url) =>
      'הוזמנת להצטרף ל-$business בתבל – חשבוניות. להצטרפות: $url';
}

/// Preset names and "what they can do" (§4.3, §12.1 — only what the server enforces).
abstract final class PresetHe {
  static const owner = 'בעלים';
  static const partner = 'שותף';
  static const employee = 'עובד';
  static const employeeIssuer = 'עובד · מפיק בעצמו';
  static const accountant = 'רואה חשבון';
  static const accountantFull = 'רו״ח – מלא';
  static const viewer = 'צפייה בלבד';
  static const cashier = 'קופאי/ת';
  static const officeManager = 'מנהל/ת משרד';

  static const employeeHint =
      'יוצר מסמכים ושולח אותם לאישורך. לא מפיק לבד, לא מבטל, לא משנה הגדרות.';
  static const partnerHint = 'יכול הכל, חוץ ממחיקת העסק. יתבקש אימות דו-שלבי.';
  static const accountantHint =
      'רואה מסמכים ודוחות, מאשר הוצאות. לא מפיק ולא שולח ללקוחות. יתבקש אימות דו-שלבי.';
  static const viewerHint = 'רואה מסמכים בלבד.';
  static const cashierHint =
      'מפיק/ה קבלה על תשלום שהתקבל עכשיו, עד ₪2,000 בלי אישור. לא רואה הכנסות ולא מבטל/ת.';
  static const officeManagerHint =
      'רואה יתרות, רושם/ת תשלומים על מסמכים קיימים ומצלם/ת הוצאות. לא מפיק/ה חשבוניות. יתבקש אימות דו-שלבי.';
  static const accountantFullHint =
      'הרשאות רו״ח מלאות (קיים). אפשר לשנות לתפקיד אחר.';

  static String label(Preset p) => switch (p) {
    Preset.owner => owner,
    Preset.partner => partner,
    Preset.employee => employee,
    Preset.employeeIssuer => employeeIssuer,
    Preset.cashier => cashier,
    Preset.officeManager => officeManager,
    Preset.accountantRep => accountant,
    Preset.accountantFull => accountantFull,
    Preset.viewer => viewer,
  };

  static String hint(Preset p) => switch (p) {
    Preset.partner => partnerHint,
    Preset.employee || Preset.employeeIssuer => employeeHint,
    Preset.cashier => cashierHint,
    Preset.officeManager => officeManagerHint,
    Preset.accountantRep => accountantHint,
    Preset.accountantFull => accountantFullHint,
    Preset.viewer => viewerHint,
    Preset.owner => '',
  };
}

/// R · דוחות (§6.R, §11).
abstract final class ReportsHe {
  static const title = 'דוחות';

  /// Accountant home (R as the home tab): the reports of the open business.
  static const myClients = 'דוחות';
  static const periodCurrent = 'התקופה הנוכחית';
  static const periodPrevious = 'התקופה הקודמת';
  static const periodYear = 'השנה';
  static const monthIncome = 'הכנסות החודש';
  static String monthOnlyIncome(String month) => 'הכנסות החודש בלבד ($month)';
  static const owed = 'מגיע לך';
  static const periodIncome = 'הכנסות בתקופה';
  static String owedLine(String amount) => 'יתרה לגבייה (כל התקופות): $amount';
  static const overdue = 'באיחור';
  static const sendToAccountant = 'שלח לרו״ח';
  static const share = 'שתף';
  static const preparing = 'מכין קובץ…';
  static const exportAccountant = 'ייצוא לרו״ח';
  static const exportExcel = 'Excel';
  static const showAll = 'הצג הכל';
  static const pdf = 'PDF';
  static const csv = 'CSV';
  static const notAvailable = 'הדוח הזה עוד לא זמין באפליקציה';
  static String exemptCeiling(String turnover, String ceiling) =>
      'מחזור השנה $turnover מתוך תקרת פטור $ceiling';
  static String accountantSubject(String business, String period) =>
      'דוח $period – $business';
  static const noAccountantEmail = 'כדאי להוסיף את מייל הרו״ח בפרטי העסק';
  static const emptyRows = 'אין נתונים בתקופה הזו';

  static const kinds = {
    'income': 'הכנסות',
    'expenses': 'הוצאות',
    'vat': 'מע״מ',
    'pnl': 'רווח והפסד',
    'advances': 'מקדמות',
    'receivables': 'חובות וגיול',
    'items': 'פריטים שנמכרו',
    'customers': 'הכנסה לפי לקוח',
    'continuity': 'רציפות מסמכים',
    'payments': 'תקבולים',
  };
  static const todo = 'לטיפול';
  static const uniformFormat = 'מבנה אחיד';
  static String sentToAccountant(String to) => 'הדוח נשלח ל-$to';
}

/// A · sign-in additions (MFA step, invitation, setup) (§6.A).
abstract final class AuthHe {
  static const mfaTitle = 'קוד אימות';

  // Sign-in screen, password reset, app lock, account deletion (AT-92).
  static const signIn = 'כניסה';

  // Owner 2026-11-18: accounts are opened by the Tevel team only.
  static const noAccount = 'אין לך חשבון? דברו איתנו';
  static const contactTitle = 'פתיחת חשבון בתבל';
  static const contactBody =
      'את החשבונות אנחנו פותחים אחרי שיחה קצרה: מכירים את העסק, '
      'מקימים אותו עבורך ושולחים לך שם משתמש וסיסמה.';
  static const contactWhatsApp = 'וואטסאפ';
  static const contactEmail = 'שליחת מייל';
  static const suggestPasswordTitle = 'רוצה לבחור סיסמה משלך?';
  static const suggestPasswordBody =
      'את הסיסמה הזו קבענו עבורך בפתיחת החשבון. כדאי להחליף אותה לסיסמה '
      'שרק את/ה מכיר/ה — נשלח קוד למייל ותבחר/י סיסמה חדשה.';
  static const changePassword = 'החלף סיסמה';
  static const showPassword = 'הצגת הסיסמה';
  static const hidePassword = 'הסתרת הסיסמה';
  static const termsLink = 'לתנאי השימוש';
  static const privacyLink = 'ולמדיניות הפרטיות';
  static const gotIt = 'הבנתי';
  static const sendResetLink = 'שליחת קישור';
  static const back = 'חזרה';
  // Owner 2026-11-16: business certificate at setup (moved from the screen).
  static const certificateOpening = 'פותח קובץ…';
  static const certificateUpload = 'העלאת תעודת עסק';
  static String unlockWith(String method) => 'פתיחה עם $method';
  static const lockSignOut = 'התנתקות';
  static const verifyWithApple = 'אימות עם Apple';
  static const deleteForever = 'מחיקת החשבון לצמיתות';
  static const notNow = 'לא עכשיו';
  static const mfaEnrollTitle = 'עוד שכבת הגנה';
  static String mfaSentTo(String to) => 'שלחנו קוד ל-$to';
  static const mfaResend = 'שלח קוד חדש';
  static const mfaUseApp = 'קוד מאפליקציית אימות';
  static const mfaUseEmail = 'שלח לי קוד במייל';
  static const mfaUseRecovery = 'יש לי קוד שחזור';
  static const confirm = 'אשר';
  static const recoveryTitle = 'קודי שחזור';
  static const recoveryBody =
      'אם לא תהיה לך גישה למייל, אפשר להיכנס עם אחד הקודים. '
      'הם מוצגים פעם אחת בלבד — שמור אותם במקום בטוח.';
  static const copy = 'העתק';
  static const copied = 'הועתקו ✓';
  static const savedContinue = 'שמרתי, המשך';

  // Setup (§6.A, 3 steps).
  static const setupTitle = 'הקמת עסק';
  static String setupStep(int step) => 'הקמת עסק · שלב $step מתוך 3';
  static const whichBusiness = 'איזה עסק יש לך?';
  static const whichBusinessHint = 'לפי זה נבחר אוטומטית את סוג המסמך הנכון';
  static const otherTypes = 'עוד ▾';
  static const businessName = 'שם העסק';
  static const defaultDescription = 'על מה אתה בדרך כלל גובה? (לא חובה)';
  static const numberingQuestion = 'כבר הפקת חשבוניות במקום אחר?';
  static const numberingNo = 'לא';
  static const numberingYes = 'כן';
  static const numberingFrom = 'מאיזה מספר להמשיך?';
  static const numberingHint = 'המספר יחול על כל סוגי המסמכים שהעסק מפיק.';
  static const finish = 'סיימתי';
  static const next = 'המשך';
  static const nameRequired = 'נא להזין את שם העסק';
  static const idRequired = 'נא להזין מספר מזהה';
  static const idInvalid = 'המספר לא תקין — בדוק את הספרות';
  static const numberInvalid = 'נא להזין מספר בין 1 ל-999,999,999';
  static const identityHint = 'סוג העסק והמספר המזהה ננעלים אחרי המסמך הראשון.';

  // Invitation (§6.A table).
  static String invitedTo(String business, String preset) =>
      'הוזמנת ל-$business כ$preset';
  static String invitedBy(String name) => 'מאת $name';
  static const joinWithPassword = 'יש לי סיסמה';
  static const createPassword = 'צור סיסמה';
  static const password = 'סיסמה';
  static const displayName = 'שם מלא';
  static const join = 'הצטרף';
  static const passwordPolicy = 'לפחות 12 תווים';
  static String alreadyMember(String business) => 'אתה כבר חבר ב-$business';
  static String expiredAskAgain(String inviter) =>
      'ההזמנה כבר לא בתוקף. בקשו מ$inviter לשלוח הזמנה חדשה';

  /// The server does not name the inviter of a dead invitation.
  static const expiredAskAgainUnknown =
      'ההזמנה כבר לא בתוקף. בקשו ממי ששלח לכם אותה לשלוח הזמנה חדשה';
  static const toSignIn = 'למסך הכניסה';
  static const forgotPassword = 'שכחתי סיסמה';
  static const signInHelp = 'עזרה בכניסה';
  static const signInHelpBody = 'לאיפוס הסיסמה בחשבון זה פנו לתמיכה.';
  static const contactSupport = 'פנה לתמיכה';

  // Invitation in the app (AUTH-INVITE-RESET 2026-11-15).
  static const createAccountJoin = 'יצירת חשבון והצטרפות';
  static const passwordRequired = 'נא להזין סיסמה';
  static const signInJoin = 'כניסה והצטרפות';
  static const inviteNewAccountHint =
      'בוחרים סיסמה לאפליקציה. אותה סיסמה תשמש גם לכניסה לתבל במחשב.';
  static const inviteExistingHint =
      'לכתובת הזו כבר יש חשבון תבל. הזינו את הסיסמה שלכם, או המשיכו עם Apple.';
  static String emailMismatch(String invited, String signedIn) =>
      'ההזמנה נשלחה ל-$invited, התחברת כ-$signedIn. התחברו עם הכתובת שאליה נשלחה ההזמנה.';
  static const appleHiddenEmail = 'חשבון Apple שמסתיר את כתובת האימייל';
  static const confirmEmailTitle = 'אישור כתובת האימייל';

  /// The address itself is its own LTR line under this text (bidi: an
  /// e-mail wrapped inside a Hebrew sentence splits, QA signed-out/16).
  static const confirmEmailSent =
      'שלחנו קוד אימות לכתובת הזו. הזינו אותו כדי לסיים ליצור את החשבון:';
  static const confirmEmailHint =
      'לא הגיע? בדקו בתיקיית הספאם, או שלחו קוד חדש.';
  static const codeSentAgain = 'נשלח קוד חדש';

  // "שכחתי סיסמה" with a code (AUTH-INVITE-RESET 2026-11-15).
  static const passwordResetTitle = 'איפוס סיסמה';
  static const recoveryEmailHint = 'נשלח קוד בן 6 ספרות לכתובת האימייל שלכם';
  static const email = 'אימייל';
  static const emailInvalid = 'נא להזין כתובת מייל תקינה';
  static const sendCode = 'שליחת קוד';
  static const recoveryCodeTitle = 'הזנת הקוד';
  static String recoveryCodeSent(String email) =>
      'אם הכתובת $email רשומה, נשלח אליה קוד. הקוד תקף לזמן קצר.';
  static const recoveryCodeLabel = 'קוד מהמייל';
  static const recoveryCodeFormat = 'הקוד הוא 6 ספרות (לפעמים יותר) מהמייל';
  static const recoveryCodeResent = 'אם הכתובת רשומה, נשלח קוד חדש';
  static const verifyCode = 'אימות הקוד';
  static const newPasswordTitle = 'סיסמה חדשה';
  static const passwordPolicyLong =
      'לפחות 12 תווים ולפחות 4 תווים שונים. לא סיסמה נפוצה.';
  static const savePassword = 'שמירת הסיסמה';
  static const recoveryDoneTitle = 'הסיסמה עודכנה';
  static const recoveryDoneInvite =
      'עכשיו הזינו את הסיסמה החדשה כדי להצטרף לעסק.';
  static const recoveryDoneSignIn = 'אפשר להיכנס עם הסיסמה החדשה.';
}

/// L · מסמכים (activity list) filters (QA 2026-11-12 · 2.5).
abstract final class ActivityHe {
  static const filterType = 'סוג מסמך';
  static const filterDate = 'תאריך';
  static const allTypes = 'כל הסוגים';
  static const clearFilters = 'נקה סינון';
  static String range(DateTime from, DateTime to) =>
      '${from.day}.${from.month}.${from.year % 100}–${to.day}.${to.month}.${to.year % 100}';
}
