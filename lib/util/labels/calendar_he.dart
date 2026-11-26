// "יומן" — the owner's calendar + client self-booking (server migration 0106).
// Clients book from a public link that shows only free times; the phone's
// calendars (EventKit) block busy times and receive the confirmed bookings.

import '../../ui/money_text.dart' show ltrIsolate;

abstract final class CalendarHe {
  // ---- entry ----
  static const title = 'יומן';
  static const entry = 'יומן פגישות';

  // ---- agenda ----
  static const today = 'היום';
  static const tomorrow = 'מחר';
  static const viewDay = 'יום';
  static const viewWeek = 'שבוע';
  static const empty = 'אין פגישות בטווח הזה';
  static const emptyBody =
      'שלחו ללקוחות את הקישור לקביעת פגישה — הם יראו רק שעות פנויות ויקבעו לבד.';
  static const busyBlock = 'תפוס ביומן שלך';
  static const busyOther = 'תפוס (יומן של חבר צוות)';
  static const cancelled = 'בוטלה';
  static String cancelledBy(String? by) =>
      by == 'CLIENT' ? 'בוטלה ע״י הלקוח' : 'בוטלה';
  static const call = 'חיוג';
  static const whatsapp = 'וואטסאפ';
  static const email = 'אימייל';
  static const cancelBooking = 'ביטול הפגישה';
  static const cancelTitle = 'לבטל את הפגישה?';
  static const cancelBody =
      'הלקוח יקבל אימייל על הביטול, והפגישה תוסר מהיומן שלו.';
  static const cancelConfirm = 'כן, לבטל';
  static const keep = 'לא';
  static const cancelledToast = 'הפגישה בוטלה והלקוח עודכן';
  static const offNotice = 'קביעת פגישות כבויה — לקוחות לא יכולים לקבוע כרגע.';
  static const turnOn = 'הפעלה';
  static String minutes(int n) => '${ltrIsolate('$n')} דק׳';

  // ---- share ----
  static const inviteGroup = 'הזמן קבוצה';
  static const share = 'שתף קישור לקביעת פגישה';
  static const shareWhatsapp = 'שליחה בוואטסאפ';
  static const shareOther = 'שיתוף…';
  static const copy = 'העתקת הקישור';
  static const copied = 'הקישור הועתק';
  static String shareText(String business, String url) =>
      'לקביעת פגישה עם $business — בחרו מועד פנוי ביומן:\n$url';

  // ---- 2611 §3א: "חבר יומן גוגל" (through the iPhone's accounts) ----
  static const googleConnect = 'חבר יומן גוגל';
  static const googleConnectHint =
      'השעות התפוסות ביומן גוגל ייחסמו בקישור, והפגישות ייכנסו אליו';
  static const googleTitle = 'חיבור יומן גוגל';
  static const googleIntro =
      'יומן גוגל מתחבר דרך האייפון: מוסיפים את חשבון הגוגל להגדרות של האייפון, ותבל רואה אותו כמו כל יומן אחר בטלפון.';
  static const googleStep1Title = 'פותחים את ההגדרות של האייפון';
  static const googleStep1Body =
      'הגדרות ← יומן ← חשבונות ← הוספת חשבון ← Google.';
  static const googleStep2Title = 'מתחברים לחשבון הגוגל';
  static const googleStep2Body =
      'מזינים את כתובת הג׳ימייל והסיסמה, ומדליקים את "יומנים".';
  static const googleStep3Title = 'חוזרים לתבל ומסמנים את היומן';
  static const googleStep3Body =
      'היומן מופיע כאן מיד. מסמנים אותו, ותבל תחסום את השעות התפוסות בו.';
  static const googleOpenSettings = 'פתח את ההגדרות';
  static const googleAllowAccess = 'אישור גישה ליומנים';
  static const googleDenied =
      'אין לתבל גישה ליומנים. בהגדרות ← תבל ← יומנים בוחרים "גישה מלאה".';
  static const googleFound = 'יומן גוגל נמצא באייפון';
  static const googleFoundHint =
      'מסמנים את היומנים שתבל תבדוק בהם שעות תפוסות:';
  static const googleNotFound =
      'עוד לא מצאנו יומן גוגל באייפון. אחרי שמוסיפים את החשבון, חוזרים לכאן.';
  static const googleUnsupported = 'חיבור יומן גוגל זמין באפליקציה לאייפון.';
  static const googleDone = 'סיום';
  static const googleTeam =
      'בעסק עם כמה אנשים: כל אחד מוסיף את חשבון הגוגל שלו מהטלפון שלו.';

  // ---- sync ----
  static const connect = 'חיבור היומן של האייפון';
  static const connectBody =
      'היומן של העסק יחסום שעות שבהן את/ה כבר תפוס/ה ביומנים של האייפון (iCloud, Google, Outlook), ויוסיף אליהם את הפגישות שלקוחות קובעים. לשרת נשלחות רק שעות התחלה וסיום — בלי שמות, משתתפים או פרטים.';
  static const connectButton = 'אישור גישה ליומן';
  static const denied =
      'אין גישה ליומן. אפשר לאשר ב: הגדרות ← תבל ← יומנים ← גישה מלאה.';
  static const openSettings = 'פתיחת הגדרות';
  static const writeOnly =
      'יש גישה רק להוספת אירועים. כדי לחסום שעות תפוסות צריך "גישה מלאה" בהגדרות.';
  static const synced = 'מסונכרן';
  static String syncedAgo(String ago) => 'סונכרן $ago';
  static const notSynced = 'היומן של האייפון לא מחובר';
  static const syncNow = 'סנכרון עכשיו';
  static const syncFailed = 'הסנכרון נכשל. ננסה שוב בפתיחה הבאה.';
  static const freshness =
      'השעות התפוסות מתעדכנות בכל פתיחה של האפליקציה. שינוי ביומן כשהאפליקציה סגורה ייכנס בפתיחה הבאה.';

  // ---- settings ----
  static const settings = 'הגדרות יומן';
  static const enabled = 'לקוחות יכולים לקבוע פגישות';
  static const enabledHint = 'כשכבוי, הקישור מראה "אינו זמין".';
  static const link = 'הקישור לקביעת פגישה';
  static const regenerate = 'יצירת קישור חדש';
  static const regenerateTitle = 'ליצור קישור חדש?';
  static const regenerateBody =
      'הקישור הישן יפסיק לעבוד מיד. פגישות שכבר נקבעו לא נפגעות.';
  static const regenerated = 'נוצר קישור חדש';
  static const hours = 'שעות פעילות';
  static const closed = 'סגור';
  static const days = [
    'ראשון',
    'שני',
    'שלישי',
    'רביעי',
    'חמישי',
    'שישי',
    'שבת',
  ];
  static const meetingTitle = 'שם הפגישה (מה הלקוח רואה)';
  static String meetingTitleHint(String business) => 'פגישה עם $business';
  static const slot = 'אורך פגישה';
  static const buffer = 'הפסקה בין פגישות';
  static const noBuffer = 'בלי';
  static const notice = 'אפשר לקבוע לפחות';
  static String noticeLabel(int minutes) => minutes == 0
      ? 'מיד'
      : minutes < 60
      ? '${ltrIsolate('$minutes')} דק׳ מראש'
      : minutes % 1440 == 0
      ? (minutes == 1440
            ? 'יום מראש'
            : '${ltrIsolate('${minutes ~/ 1440}')} ימים מראש')
      : '${ltrIsolate('${minutes ~/ 60}')} שע׳ מראש';
  static const ahead = 'כמה זמן קדימה';
  static String aheadLabel(int days) => days == 7
      ? 'שבוע'
      : days == 14
      ? 'שבועיים'
      : '${ltrIsolate('$days')} ימים';
  static const notifications = 'התראות';
  static const notifyNew = 'פגישה חדשה נקבעה';
  static const notifyNewHint = 'הודעה באפליקציה ובאימייל כשלקוח קובע או מבטל.';
  static const reminder = 'תזכורת לפני פגישה';
  static const reminderOff = 'בלי';
  static const reminderHint =
      'כשהאפליקציה פתוחה — הודעה מונפשת בראש המסך. כשהיא סגורה — התראה בטלפון, אם התראות תבל מופעלות.';
  static const calendars = 'יומנים באייפון';
  static const readFrom = 'לחסום שעות תפוסות מתוך';
  static const writeTo = 'להוסיף פגישות שנקבעו אל';
  static const noWrite = 'לא להוסיף';
  static const disconnect = 'ניתוק היומן של האייפון';
  static const disconnected = 'היומן נותק. השעות התפוסות מהאייפון נמחקו מהשרת.';
  static const save = 'שמירה';
  static const saved = 'ההגדרות נשמרו';
  static const from = 'מ־';
  static const to = 'עד';

  // ---- notices (notch + local notifications) ----
  static const newBooking = 'נקבעה פגישה חדשה';
  static String newBookingNamed(String name, String when) => '$name · $when';
  static const soon = 'הפגישה הבאה מתקרבת';
  static String soonBody(String name, String time) =>
      '$name · בשעה ${ltrIsolate(time)}';
  static const open = 'פתיחה';

  // ---- device calendar event ----
  static String eventTitle(String name) => 'פגישה: $name';
  static String eventNotes({
    required String phone,
    required String email,
    String? notes,
  }) => [
    'טלפון: $phone',
    'אימייל: $email',
    if (notes != null && notes.isNotEmpty) 'תוכן: $notes',
    'נקבע דרך תבל',
  ].join('\n');

  // ---- v2: breaks, vacation, approval, blocked clients ----
  static const hoursButton = 'שעות וימים';
  static const addBreak = 'הוספת הפסקה';
  static const removeBreak = 'הסרת ההפסקה';
  static const blockedDates = 'חסימת תאריכים';
  static const blockedDatesHint =
      'חופשה או ימים בלי פגישות — לקוחות לא יראו בהם שעות פנויות.';
  static const addBlockedDates = 'הוספת תאריכים';
  static const removeBlockedDates = 'הסרה';
  static const noBlockedDates = 'אין תאריכים חסומים';
  static const tooManyBlockedDates = 'אפשר לחסום עד 30 טווחי תאריכים.';
  static const requireApproval = 'אישור ידני לכל פגישה';
  static const requireApprovalHint =
      'פגישה שלקוח קובע תמתין לאישור שלך; השעה שמורה לו עד שתחליט/י.';
  static const blockedClients = 'לקוחות חסומים';
  static const blockedClientsHint = 'לקוחות שלא יכולים לקבוע פגישות';
  static const noBlockedClients = 'אין לקוחות חסומים';
  static const unblock = 'ביטול חסימה';
  static const unblocked = 'החסימה בוטלה';

  // ---- v2: pending bookings ----
  static const pendingGroup = 'ממתינות לאישור';
  static const pending = 'ממתינה לאישור';
  static String pendingUntil(String when) => 'שמורה עד $when';
  static const approve = 'אישור';
  static const decline = 'דחייה';
  static const approved = 'הפגישה אושרה והלקוח עודכן';
  static const declined = 'הבקשה נדחתה והלקוח עודכן';
  static const declinedLabel = 'נדחתה';
  static String closedLabel(String status, String? by) =>
      status == 'DECLINED' ? declinedLabel : cancelledBy(by);

  // ---- v2: block a client ----
  static const blockClient = 'חסימת הלקוח';
  static const blockTitle = 'לחסום את הלקוח?';
  static const blockBody =
      'הלקוח לא יוכל לקבוע פגישות חדשות, וכל הפגישות הקרובות שלו יבוטלו (הוא יקבל אימייל ביטול רגיל). הלקוח לא יידע שנחסם.';
  static const blockConfirm = 'כן, לחסום';
  static const blocked = 'הלקוח נחסם והפגישות הקרובות שלו בוטלו';

  // ---- v2: from the customer page ----
  static const bookFor = 'קביעת פגישה';
  static const modeSuggest = 'הצעת מועדים';
  static const modeLink = 'שליחת קישור ליומן';
  static const modeBook = 'קביעה בשמו';
  static const suggestHint =
      'בחרו עד 3 מועדים — הלקוח יקבל קישור לבחירה ביניהם.';
  static const linkHint =
      'הלקוח יקבל קישור אישי ליומן (תקף ל־7 ימים) ויבחר בעצמו שעה פנויה.';
  static const bookHint = 'בחרו מועד — הפגישה תיקבע מיד בשם הלקוח.';
  static const pickSlot = 'בחרו מועד מהרשימה';
  static const maxThree = 'אפשר לבחור עד 3 מועדים';
  static const noFreeSlots = 'אין כרגע שעות פנויות ביומן.';
  static const sendInvite = 'שליחה ללקוח';
  static const bookConfirm = 'קביעת הפגישה';
  static String bookConfirmTitle(String name) => 'לקבוע פגישה ל$name?';
  static const bookConfirmEmail =
      'הלקוח יקבל אימייל אישור עם אפשרות לשנות או לבטל.';
  static const booked = 'הפגישה נקבעה';
  static const slotTaken = 'המועד הזה נתפס בינתיים. הנה השעות הפנויות עכשיו.';
  static const disabledTitle = 'קביעת פגישות כבויה';
  static const disabledBody =
      'כדי להציע מועדים או לשלוח קישור ליומן, צריך להפעיל קביעת פגישות.';
  static const enable = 'הפעלת קביעת פגישות';

  // ---- v2.1: day strip (free-slots?date=) ----
  static const modeLinkShort = 'קישור ליומן';
  static const linkShortHint =
      'קישור אישי, תקף 7 ימים — הלקוח בוחר בעצמו שעה פנויה.';
  static const suggestHintDays =
      'בחרו עד 3 מועדים, גם בימים שונים — הלקוח יקבל קישור לבחירה ביניהם.';
  static const bookHintDay = 'בחרו יום ושעה — הפגישה תיקבע מיד בשם הלקוח.';
  static const noTimesThisDay = 'אין שעות פנויות ביום הזה.';
  static const noSlotsHorizon = 'אין שעות פנויות בימים הקרובים.';
  static const changeHours = 'שינוי שעות';
  static const enableShort = 'הפעלה';
  static String defaultHours(String summary) => 'שעות ברירת מחדל: $summary';
  static const notesLabel = 'הערה לפגישה (לא חובה)';
  static String confirmByEmail(String name) =>
      '$name יקבל/תקבל אישור באימייל עם אפשרות לשנות או לבטל.';
  static const confirmByPhone =
      'ללקוח אין אימייל — אחרי הקביעה אפשר לשלוח לו את הפרטים בוואטסאפ.';
  static const confirmNoContact = 'ללקוח אין אימייל או טלפון לשליחת אישור.';
  static const offerWhatsappTitle = 'לשלוח את הפרטים בוואטסאפ?';
  static String offerWhatsappBody(String name, String when) =>
      'הפגישה עם $name נקבעה ל$when.';
  static String whatsappDetails(String name, String when, String business) =>
      'שלום $name, קבענו פגישה ל$when. $business';
  static const sendWhatsapp = 'שליחה בוואטסאפ';
  static const notNow = 'לא עכשיו';
  static String removePick(String label) => 'הסרת $label';

  // ---- 2611 §9: iOS-style calendar (month / day / list) ----
  static const months = [
    'ינואר',
    'פברואר',
    'מרץ',
    'אפריל',
    'מאי',
    'יוני',
    'יולי',
    'אוגוסט',
    'ספטמבר',
    'אוקטובר',
    'נובמבר',
    'דצמבר',
  ];
  static const weekdayLetters = ['א׳', 'ב׳', 'ג׳', 'ד׳', 'ה׳', 'ו׳', 'ש׳'];
  static String monthYear(DateTime m) => '${months[m.month - 1]} ${m.year}';

  /// "יום שלישי, 25 בנובמבר 2026".
  static String longDay(DateTime d) =>
      'יום ${days[d.weekday % 7]}, ${d.day} ב${months[d.month - 1]} ${d.year}';
  static const listView = 'רשימה';
  static const monthView = 'חודש';
  static const newMeeting = 'פגישה חדשה';
  static const add = 'הוספה';
  static const cancelSheet = 'ביטול';
  static const customer = 'לקוח';
  static const pickCustomer = 'בחירת לקוח';
  static const date = 'תאריך';
  static const time = 'שעה';
  static const pickDate = 'בחרו תאריך';
  static const pickTime = 'בחרו שעה';
  static const notes = 'הערה';
  static const notesHint = 'לא חובה';
  static const noCustomer = 'קודם בוחרים לקוח';
  static String pendingCount(int n) => '$pendingGroup · ${ltrIsolate('$n')}';
  static const busyTitle = 'תפוס';
  static const noMeetingsDay = 'אין פגישות ביום הזה';
  static const upcoming = 'הפגישות הקרובות';
  static const openCustomer = 'דף הלקוח';
  static const fromLink = 'נקבעה מהקישור — לא מקושרת ללקוח ברשימה';
  static const statusConfirmed = 'מאושרת';
  static const moveTitle = 'לעדכן את הלקוח?';
  static String moveBody(String name, String when) =>
      'הפגישה עם $name תועבר ל$when.';
  static const moveNotify = 'כן, לעדכן באימייל';
  static const moveQuiet = 'להעביר בלי לעדכן';
  static const moveBack = 'ביטול';
  static const moved = 'הפגישה הועברה';
  static const movedNotified = 'הפגישה הועברה והלקוח עודכן';
  static const slotBusy = 'השעה הזאת תפוסה. נסו שעה אחרת.';
  static const now = 'עכשיו';
  static const dragHint = 'לחיצה ארוכה וגרירה מזיזה את הפגישה';

  static String error(String? code) => switch (code) {
    'VALIDATION' => 'אחד הערכים לא תקין. נא לבדוק את ההגדרות.',
    'BOOKING_NOT_FOUND' => 'הפגישה לא נמצאה.',
    'BOOKING_NOT_PENDING' => 'הבקשה כבר טופלה.',
    'SLOT_TAKEN' => slotTaken,
    'CALENDAR_DISABLED' => disabledTitle,
    'CUSTOMER_NOT_FOUND' => 'הלקוח לא נמצא.',
    'CUSTOMER_NO_CONTACT' =>
      'ללקוח אין טלפון או אימייל — הוסיפו אחד בדף הלקוח.',
    'BOOKING_NOT_CHANGEABLE' => 'את הפגישה הזאת כבר אי אפשר להזיז.',
    _ => 'משהו השתבש. נסו שוב.',
  };
}
