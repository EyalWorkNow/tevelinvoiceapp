// וואטסאפ עסקי (Meta Cloud API, 0136): every visible string of the business
// settings page, the template sheet, the group's send choice, the campaign
// sheet and the campaign screens.
library;

abstract final class WaHe {
  // Settings row / page
  static const row = 'וואטסאפ עסקי';
  static const title = 'וואטסאפ עסקי';
  static const unavailable = 'שליחה אוטומטית בוואטסאפ אינה זמינה כרגע.';

  // Not connected
  static const introTitle = 'הודעות וואטסאפ אוטומטיות מהמספר שלך';
  static const introPoints = <String>[
    'ההודעות יוצאות מהמספר של העסק, בשם העסק.',
    'לכל עסק מכסה חודשית של הודעות.',
    'נשלח רק ללקוחות שאישרו קבלת דיוור.',
    'כל הודעה נשלחת לפי תבנית ש-Meta מאשרת מראש.',
  ];
  static const connect = 'חיבור מספר וואטסאפ';
  static const connectHint =
      'ייפתח דף של Meta. אחרי החיבור חוזרים לאפליקציה והמצב מתעדכן לבד.';
  static const waitingForConnect = 'ממתינים לסיום החיבור בדף של Meta…';

  // Connected
  static const connected = 'מחובר';
  static const number = 'מספר';
  static const verifiedName = 'שם מאומת';
  static const quality = 'איכות המספר';
  static String qualityLabel(String? q) => switch ((q ?? '').toUpperCase()) {
    'GREEN' || 'HIGH' => 'גבוהה',
    'YELLOW' || 'MEDIUM' => 'בינונית',
    'RED' || 'LOW' => 'נמוכה',
    _ => 'עוד לא נקבעה',
  };
  static const coexistence =
      'המספר ממשיך לעבוד גם באפליקציית WhatsApp Business. תשובות הלקוחות מגיעות לשם.';
  static const quotaTitle = 'מכסה חודשית';
  static String quotaLine(int used, int quota) => '$used מתוך $quota הודעות';
  static String quotaLeft(int n) =>
      n == 1 ? 'נשארה הודעה אחת החודש' : 'נשארו $n הודעות החודש';
  static const disconnect = 'ניתוק';
  static const disconnectTitle = 'לנתק את מספר הוואטסאפ?';
  static const disconnectBody =
      'שליחה אוטומטית תיפסק. התבניות נשארות אצל Meta, ואפשר לחבר שוב בכל עת. '
      'בינתיים אפשר להמשיך לשלוח בנגיעה לכל לקוח.';
  static const disconnectConfirm = 'ניתוק';
  static const disconnected = 'המספר נותק';

  // Error
  static const errorTitle = 'החיבור לוואטסאפ נכשל';
  static const errorFallback = 'Meta לא אישרה את החיבור. נסו לחבר שוב.';
  static const reconnect = 'חיבור מחדש';

  // Templates
  static const templates = 'תבניות הודעה';
  static const newTemplate = 'תבנית חדשה';
  static const noTemplates =
      'עוד אין תבניות. כל הודעה אוטומטית יוצאת לפי תבנית ש-Meta אישרה.';
  static String templateStatus(String s) => switch (s) {
    'APPROVED' => 'מאושר',
    'PENDING' => 'ממתין לאישור',
    'REJECTED' => 'נדחה',
    'PAUSED' => 'מושהה',
    'DISABLED' => 'מושבת',
    _ => s,
  };
  static String rejected(String reason) => 'סיבה: $reason';
  static const deleteTemplate = 'מחיקת התבנית';
  static const deleteTemplateTitle = 'למחוק את התבנית?';
  static const deleteTemplateBody =
      'התבנית תימחק גם אצל Meta. קמפיינים שכבר נשלחו לא משתנים.';
  static const deleteConfirm = 'מחיקה';
  static const templateDeleted = 'התבנית נמחקה';

  // New template sheet
  static const templateText = 'נוסח ההודעה';
  static const templateHint = 'שלום {שם}, …';
  static const insertName = 'הוסף שם לקוח';
  static const nameHelp = '{שם} יוחלף בשם הפרטי של כל לקוח';
  static const previewTitle = 'כך זה ייראה אצל הלקוח:';
  static const sampleName = 'דנה כהן';
  static const footer = 'להסרה לחצו על הכפתור';
  static const optOutButton = 'הסרה מרשימת התפוצה';
  static const approvalNote =
      'Meta בודקת כל תבנית לפני שאפשר לשלוח אותה. בדרך כלל זה לוקח כמה דקות ועד כמה שעות. '
      'הכפתור להסרה מתווסף לבד (חוק התקשורת, סעיף 30א).';
  static const submit = 'שליחה לאישור';
  static const textRequired = 'צריך לכתוב את נוסח ההודעה';
  static const textTooLong = 'עד 900 תווים';
  static const templateSent = 'התבנית נשלחה לאישור Meta';

  // Group: send choice
  static const choiceTitle = 'שליחה בוואטסאפ';
  static const choiceAuto = 'שליחה אוטומטית מהמספר שלך';
  static const choiceAutoHint =
      'תבנית מאושרת יוצאת לכל מי שאישר דיוור, בלי לגעת בטלפון.';
  static const choiceQueue = 'תור הקשה לכל לקוח';
  static const choiceQueueHint =
      'הודעה חופשית; כל הודעה נפתחת בוואטסאפ ואת/ה שולח/ת בנגיעה.';

  // Campaign sheet
  static const campaignTitle = 'שליחה אוטומטית';
  static const pickTemplate = 'בחירת תבנית';
  static const noApproved = 'עוד אין תבנית מאושרת.';
  static const createTemplate = 'ליצירת תבנית';
  static const pendingNote = 'תבניות שממתינות לאישור יופיעו כאן כשיאושרו.';
  static const checking = 'בודקים למי זה יוצא…';
  static String recipients(int n) =>
      n == 1 ? 'יישלח ללקוח אחד' : 'יישלח ל-$n לקוחות';
  static String skippedNoConsent(int n) =>
      n == 1 ? 'אחד לא אישר דיוור — מדולג' : '$n לא אישרו דיוור — מדולגים';
  static String skippedNoPhone(int n) =>
      n == 1 ? 'אחד בלי טלפון תקין — מדולג' : '$n בלי טלפון תקין — מדולגים';
  static String skippedArchived(int n) =>
      n == 1 ? 'אחד לא פעיל — מדולג' : '$n לא פעילים — מדולגים';
  static String quotaAfter(int left) => 'נשארו במכסה החודשית: $left';
  static const nobody = 'אין בקבוצה לקוח שיקבל את ההודעה.';
  static const send = 'שליחה';
  static String confirmTitle(int n) =>
      n == 1 ? 'לשלוח ללקוח אחד?' : 'לשלוח ל-$n לקוחות?';
  static const confirmBody =
      'ההודעה תצא עכשיו מהמספר של העסק לכל הנמענים. אי אפשר לבטל אחרי השליחה.';

  // Campaign screen
  static const campaign = 'קמפיין וואטסאפ';
  static const sending = 'בשליחה';
  static const done = 'הסתיים';
  static const countQueued = 'בתור';
  static const countSent = 'נשלחו';
  static const countDelivered = 'נמסרו';
  static const countRead = 'נקראו';
  static const countFailed = 'נכשלו';
  static const recipientsTitle = 'נמענים';
  static const autoRefresh = 'מתעדכן כל כמה שניות';
  static String recipientStatus(String s) => switch (s) {
    'QUEUED' || 'PENDING' => 'בתור',
    'SENDING' => 'נשלח',
    'SENT' => 'נשלח',
    'DELIVERED' => 'נמסר',
    'READ' => 'נקרא',
    'FAILED' => 'נכשל',
    'SKIPPED' => 'דולג',
    _ => s,
  };

  // Previous campaigns
  static const previous = 'קמפיינים קודמים';
  static const noCampaigns = 'עוד לא נשלחו קמפיינים לקבוצה הזו.';
  static String previousCount(int n) => n == 1 ? 'קמפיין אחד' : '$n קמפיינים';
  static String campaignLine(int sent, int total) => '$sent מתוך $total נשלחו';

  // Errors (409 codes of POST …/whatsapp-campaigns)
  static const errQuota =
      'אין מספיק הודעות במכסה החודשית לכל הנמענים. לא נשלח דבר.';
  static const errNotApproved = 'התבנית עוד לא אושרה על ידי Meta.';
  static const errNotConnected =
      'מספר הוואטסאפ של העסק לא מחובר. אפשר לשלוח בנגיעה לכל לקוח.';
  static const errDemo = 'בעסק לדוגמה לא שולחים הודעות ללקוחות.';
  static const errDuplicate = 'הקמפיין הזה כבר נשלח עכשיו לקבוצה.';
}
