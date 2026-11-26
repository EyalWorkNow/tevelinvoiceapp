// The customer / supplier page (כרטיס לקוח v2, owner spec 2026-11-23):
// header + status card + quick actions + short lists.

abstract final class PersonPageHe {
  // ---- status card ----
  static const owesYou = 'חייב לך';
  static const noBalance = 'אין יתרה פתוחה';
  static const noDocsYet = 'עוד אין מסמכים';
  static String daysWord(int n) => n == 1 ? 'יום אחד' : '$n ימים';
  static String docOverdue(String doc, int days) =>
      '$doc באיחור ${daysWord(days)}';
  static String docDueBy(String doc, String date) => '$doc · לתשלום עד $date';
  static String docOpen(String doc) => '$doc · פתוח לתשלום';
  static String lastDocAgo(int days) => days <= 0
      ? 'מסמך אחרון היום'
      : days == 1
      ? 'מסמך אחרון אתמול'
      : 'מסמך אחרון לפני $days ימים';
  static String nextMeeting(String when) => 'פגישה · $when';
  static String nextVisit(String title, String when) => '$title · $when';
  static String nextFollowUp(String title) => 'תזכורת: $title · באיחור';
  static const nothingNext = 'אין פגישות או תזכורות קרובות';

  // ---- dates ----
  static String dayLabel(String weekday, String dayMonth) =>
      'יום $weekday $dayMonth';
  static const weekdayShort = ['א׳', 'ב׳', 'ג׳', 'ד׳', 'ה׳', 'ו׳', 'ש׳'];

  // ---- tags ----
  static const tagScheduled = 'נקבע';
  static const tagOverdue = 'באיחור';
  static const tagPending = 'ממתינה לאישור';
  static const tagActive = 'בטיפול';
  static const meeting = 'פגישה';

  // ---- quick actions ----
  static const quickActions = 'פעולות מהירות';
  static const call = 'חיוג';
  static const whatsapp = 'וואטסאפ';
  static const email = 'אימייל';
  static const requestPayment = 'בקשת תשלום';
  static const invoice = 'חשבונית';
  static const book = 'קביעת פגישה';
  static const paid = 'קיבלתי תשלום';
  static const quote = 'הצעת מחיר';
  static const reminder = 'תזכורת לעצמי';
  static const more = 'עוד';
  static const addPhone = 'הוספת טלפון';
  static const newExpense = 'הוצאה חדשה';

  // ---- supplier ----
  static const supplierExpenses = 'הוצאות';
  static const supplierExpensesHint = 'הוצאות שקלטת מהספק נמצאות במסך ההוצאות.';

  /// One-line orb labels (the full names above stay for VoiceOver / "עוד").
  static const orbBook = 'פגישה';
  static const orbReminder = 'תזכורת';
  static const orbAddPhone = 'הוספת טלפון';

  // ---- "עוד" sheet ----
  static const moreTitle = 'עוד פעולות';
  static const repeatLast = 'כמו בפעם הקודמת';
  static const debt = 'רשום חוב';
  static const newJob = 'ביקור או עבודה חדשה';
  static const note = 'פתק';
  static const navigate = 'ניווט לכתובת';
  static const statement = 'שליחת כרטסת';
  static const details = 'פרטים ועריכה';
  static const terms = 'תנאי תשלום';
  static const archive = 'ארכוב';

  // ---- lists ----
  static const all = 'הכל';
  static const less = 'פחות';
  static const documents = 'מסמכים';
  static const firstInvoice = 'חשבונית ראשונה';
  static const visits = 'ביקורים ופגישות';
  static const noVisits = 'אין ביקורים קרובים';
  static const calendarBookings = 'פגישות ביומן';
  static const noBookings = 'אין פגישות ביומן ללקוח הזה';
  static const notes = 'פתקים ותזכורות';
  static const noNotes = 'אין פתקים';
  static const addNote = 'פתק חדש';
  static const money = 'כסף ורווחיות';
  static const customerDetails = 'פרטי הלקוח';
  static const supplierDetails = 'פרטי הספק';
  static const phone = 'טלפון';
  static const address = 'כתובת';
  static const taxId = 'עוסק / ח.פ.';
  static const autoReminders = 'תזכורות תשלום אוטומטיות';
  static const autoRemindersHint = 'תזכורות גבייה שנשלחות ללקוח לפי ההגדרות';
  static const missing = '—';
  static const meetingDetails = 'פרטי הפגישה';

  // ---- "תזכורת לעצמי" sheet ----
  static const reminderTitle = 'תזכורת לעצמי';
  static const tomorrow = 'מחר';
  static const inWeek = 'בעוד שבוע';
  static const pickDate = 'בחירת תאריך';
  static const reminderText = 'על מה להזכיר?';
  static String reminderDefault(String name) => 'לחזור ל$name';
  static const saveReminder = 'שמירת תזכורת';
  static const reminderSaved = 'התזכורת נשמרה';
  static const noteSaved = 'הפתק נשמר';
}

abstract final class PersonCrmHe {
  static const deleteNoteTitle = 'למחוק את הפתק?';
  static String deleteNoteBody(String name) => 'הפתק יוסר מהתיק של $name.';
  static const deleteReminderTitle = 'למחוק את התזכורת?';
  static const deleteReminderBody = 'אפשר ליצור תזכורת חדשה בכל שלב.';
}
