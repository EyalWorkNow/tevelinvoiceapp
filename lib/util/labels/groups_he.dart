// V4 §8 · קבוצות לקוחות — every visible string of the groups row, the group
// page, its actions, the WhatsApp queue and the customer page's groups row.
library;

abstract final class GroupsHe {
  // Customers screen
  static const groups = 'קבוצות';
  static const newGroup = 'קבוצה חדשה';
  static String membersCount(int n) => n == 1 ? 'לקוח אחד' : '$n לקוחות';

  // Smart groups
  static const smartOwes = 'חייבים לי';
  static const smartNoPurchase = 'לא קנו 90 יום';
  static const smartInactive = 'לא פעילים';
  static const smartBadge = 'מתעדכנת לבד';

  // Multi-select
  static String selected(int n) => n == 1 ? 'לקוח אחד נבחר' : '$n נבחרו';
  static const cancelSelection = 'ביטול בחירה';
  static const addToGroup = 'הוסף לקבוצה';
  static const quickAction = 'פעולה מהירה';
  static const quickActionTitle = 'פעולה על הנבחרים';
  static const quickActionHint =
      'הנבחרים נכנסים לקבוצה, ומשם יוצאת הפעולה לכל אחד מהם.';
  static const pickGroupTitle = 'לאיזו קבוצה?';
  static String addedToGroup(int n, String group) =>
      n == 1 ? 'לקוח אחד נוסף ל$group' : '$n לקוחות נוספו ל$group';
  static const longPressHint = 'לחיצה ארוכה על לקוח לבחירה מרובה';

  // Editor
  static const editorNew = 'קבוצה חדשה';
  static const editorEdit = 'עריכת קבוצה';
  static const name = 'שם הקבוצה';
  static const nameHint = 'למשל: ועד בית הרצל 5';
  static const color = 'צבע';
  static const save = 'שמירה';
  static const create = 'יצירת קבוצה';
  static const nameRequired = 'צריך שם לקבוצה';
  static String colorName(String key) => switch (key) {
    'blue' => 'כחול',
    'green' => 'ירוק',
    'orange' => 'כתום',
    'pink' => 'ורוד',
    'purple' => 'סגול',
    'yellow' => 'צהוב',
    'teal' => 'טורקיז',
    'red' => 'אדום',
    _ => 'אפור',
  };

  // Group page
  static const edit = 'עריכת שם וצבע';
  static const delete = 'מחיקת קבוצה';
  static const deleteTitle = 'למחוק את הקבוצה?';
  static String deleteBody(String name) =>
      'הקבוצה "$name" תימחק. הלקוחות עצמם לא נמחקים.';
  static const deleteConfirm = 'מחיקה';
  static const deleted = 'הקבוצה נמחקה';
  static const members = 'חברים';
  static String membersLine(int n) =>
      n == 1 ? 'לקוח אחד בקבוצה' : '$n לקוחות בקבוצה';
  static String owingLine(int n) => n == 1 ? 'אחד חייב' : '$n חייבים';
  static const owingTotal = 'סך החוב';
  static const nobodyOwes = 'אף אחד בקבוצה לא חייב כרגע';
  static String noPhone(int n) => n == 1 ? 'אחד בלי טלפון' : '$n בלי טלפון';
  static String noEmail(int n) => n == 1 ? 'אחד בלי מייל' : '$n בלי מייל';
  static String inactive(int n) =>
      n == 1 ? 'אחד לא פעיל (מדולג בפעולות)' : '$n לא פעילים (מדולגים בפעולות)';
  static String booked(int booked, int sent) => '$booked מתוך $sent קבעו';
  static const quickActions = 'פעולות מהירות';
  static const membersTitle = 'חברי הקבוצה';
  static const emptyMembers = 'עוד אין לקוחות בקבוצה';
  static const emptySmart = 'אין כרגע לקוחות שמתאימים לקבוצה';
  static const addMembers = 'הוסף חברים';
  static const removeMember = 'הוצאה מהקבוצה';
  static String removed(String name) => '$name הוצא/ה מהקבוצה';
  static const inactiveBadge = 'לא פעיל';
  static const inactiveNoActions =
      'לקוחות לא פעילים מדולגים בכל פעולה, לכן אין כאן פעולות שליחה.';
  static const employeeNoActions =
      'שליחת תפוצה ובקשות תשלום לקבוצה — לבעלי העסק בלבד.';

  // Actions
  static const actPayment = 'בקשת תשלום לכולם';
  static const actBroadcast = 'הודעת תפוצה';
  static const actDocument = 'מסמך לכולם';
  static const actInvite = 'קישור לקביעת פגישה';
  static const actStatement = 'שליחת כרטסת';

  // Confirm (preview)
  static const confirmSend = 'שליחה';
  static const confirmIssue = 'הפקה';
  static const previewing = 'בודקים למי זה יוצא…';
  static String willSend(int n) =>
      n == 1 ? 'יישלח ללקוח אחד' : 'יישלח ל-$n לקוחות';
  static String byEmail(int n) => '$n במייל (אוטומטית)';
  static String byWhatsapp(int n) => '$n בוואטסאפ (נגיעה לכל אחד)';
  static String wontGet(int n) => n == 1 ? 'אחד לא יקבל' : '$n לא יקבלו';
  static String notOwing(int n) =>
      n == 1 ? 'אחד לא חייב — מדולג' : '$n לא חייבים — מדולגים';
  static String skippedInactive(int n) =>
      n == 1 ? 'אחד לא פעיל — מדולג' : '$n לא פעילים — מדולגים';
  static String noContact(int n) => '$n בלי טלפון ומייל';
  static String noConsent(int n) => '$n לא אישרו דיוור';
  static String noEmailSkip(int n) => '$n בלי מייל';
  static String documentsLine(int n, String total) =>
      'יוצאו $n מסמכים, סך $total';
  static String perDocument(String amount) => '$amount לכל לקוח';
  static const nobody = 'אין בקבוצה לקוח שיקבל את זה.';
  static const paymentTitle = 'בקשת תשלום לכל מי שחייב';
  static const paymentBody =
      'כל מי שחייב מקבל בקשה אישית על הסכום שלו, עם קישור למסמכים ולתשלום.';
  static const statementTitle = 'כרטסת לכל אחד';
  static const statementBody = 'כל לקוח עם מייל מקבל את הכרטסת שלו כקובץ PDF.';
  static const inviteTitle = 'קישור אישי לקביעת פגישה';
  static const inviteBody =
      'כל חבר מקבל קישור אישי לקביעת פגישה (בתוקף 7 ימים). עם מייל — נשלח לבד; עם טלפון בלבד — בוואטסאפ.';
  static const inviteSend = 'שליחת קישורים';
  static const inviteNone = 'עוד לא נשלחו קישורים לקבוצה הזו';

  // Broadcast sheet
  static const broadcastTitle = 'הודעת תפוצה';
  static const broadcastText = 'נוסח ההודעה';
  static const broadcastHint = 'שלום {שם}, …';
  static const nameHintChip = 'הוספת {שם}';
  static const nameHelp = '{שם} יוחלף בשם הפרטי של כל לקוח';
  static const purpose = 'סוג ההודעה';
  static const purposeService = 'עדכון שירות';
  static const purposeMarketing = 'מבצע / פרסום';
  static const marketingNote =
      'הודעת פרסום נשלחת רק ללקוחות שאישרו דיוור (חוק התקשורת, סעיף 30א). בכל מייל יש קישור להסרה.';
  static const channel = 'ערוץ';
  static const channelWhatsapp = 'וואטסאפ';
  static const channelEmail = 'מייל';
  static const subject = 'נושא המייל';
  static const textRequired = 'צריך לכתוב הודעה';
  static const previewFor = 'כך זה ייראה:';
  static const next = 'המשך';

  // Document sheet
  static const documentTitle = 'מסמך לכולם';
  static const documentBody =
      'אותו פריט וסכום — מסמך נפרד לכל לקוח (למשל דמי ועד חודשיים).';
  static const documentType = 'סוג המסמך';
  static const description = 'תיאור';
  static const descriptionHint = 'למשל: דמי ועד — דצמבר';
  static const amount = 'סכום לכל לקוח (כולל מע״מ)';
  static const amountNoVat = 'סכום לכל לקוח';
  static const dueDate = 'תאריך לתשלום';
  static const noDueDate = 'ללא';
  static const sendToCustomers = 'לשלוח לכל לקוח את המסמך שלו';
  static const descriptionRequired = 'צריך תיאור';
  static const amountRequired = 'צריך סכום';

  // Result
  static const resultTitle = 'בוצע';
  static String sentEmail(int n) => n == 1 ? 'מייל אחד יצא' : '$n מיילים יצאו';
  static String issued(int n) => n == 1 ? 'מסמך אחד הופק' : '$n מסמכים הופקו';
  static String waiting(int n) =>
      n == 1 ? 'אחד מחכה לשליחה בוואטסאפ' : '$n מחכים לשליחה בוואטסאפ';
  static String failed(int n) => n == 1 ? 'אחד נכשל' : '$n נכשלו';
  static String skipped(int n) => n == 1 ? 'אחד דולג' : '$n דולגו';
  static const openQueue = 'לשליחה בוואטסאפ';
  static const done = 'סגירה';
  static const genericError = 'משהו השתבש — נסו שוב';

  // WhatsApp queue
  static const queueTitle = 'שליחה בוואטסאפ';
  static const queueHint =
      'נגיעה פותחת וואטסאפ עם ההודעה מוכנה — שולחים וחוזרים לבא בתור.';
  static const queueSend = 'שליחה';
  static const queueSkip = 'דלג';
  static const queueEmpty = 'הכל נשלח';
  static const queueEmptyBody = 'אין עוד הודעות שמחכות לשליחה.';
  static String queueA11y(String name) => 'שליחה בוואטסאפ ל$name';

  // Customer page
  static const customerGroups = 'קבוצות';
  static const noGroups = 'אין';
  static const customerGroupsTitle = 'הקבוצות של הלקוח';
  static const noGroupsYet = 'עוד אין קבוצות. אפשר ליצור במסך הלקוחות.';
  static const marketingConsent = 'מאשר דיוור';
  static const marketingConsentHint = 'יקבל הודעות פרסום ומבצעים';
}
