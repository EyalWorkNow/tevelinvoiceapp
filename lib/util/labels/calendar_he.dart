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
  static const share = 'שתף קישור לקביעת פגישה';
  static const shareWhatsapp = 'שליחה בוואטסאפ';
  static const shareOther = 'שיתוף…';
  static const copy = 'העתקת הקישור';
  static const copied = 'הקישור הועתק';
  static String shareText(String business, String url) =>
      'לקביעת פגישה עם $business — בחרו מועד פנוי ביומן:\n$url';

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

  static String error(String? code) => switch (code) {
    'VALIDATION' => 'אחד הערכים לא תקין. נא לבדוק את ההגדרות.',
    'BOOKING_NOT_FOUND' => 'הפגישה לא נמצאה.',
    _ => 'משהו השתבש. נסו שוב.',
  };
}
