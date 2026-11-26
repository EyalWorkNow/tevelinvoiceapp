// Automatic collection reminders, "תזכורות גבייה אוטומטיות" (server 0111):
// the ladder settings, the daily WhatsApp batch, opt-out and pause.

abstract final class CollectionHe {
  // ---- settings -------------------------------------------------------------
  // 2611 §2 "תדירות".
  static const cadenceTitle = 'תדירות';
  static String cadenceLabel(String cadence) => switch (cadence) {
    'WEEKLY' => 'כל שבוע',
    'BIWEEKLY' => 'כל שבועיים',
    'MONTHLY' => 'פעם בחודש',
    'LADDER' => 'לפי שלבים',
    'BUSINESS' => 'כמו בעסק',
    'NONE' => 'בלי תזכורות',
    _ => cadence,
  };
  static String cadenceHint(String cadence) => switch (cadence) {
    'WEEKLY' => 'ביום הפירעון, ואז כל 7 ימים',
    'BIWEEKLY' => 'ביום הפירעון, ואז כל 14 יום',
    'MONTHLY' => 'ביום הפירעון, ואז כל 30 יום',
    'LADDER' => 'לפי השלבים שב"מתקדם"',
    'BUSINESS' => 'התדירות שנקבעה בהגדרות ← תזכורות',
    'NONE' => 'לא יישלחו ללקוח הזה תזכורות אוטומטיות',
    _ => '',
  };
  static const cadenceCeiling =
      'עד 6 תזכורות למסמך, ואז הוא עובר ל"לטיפול ידני" במסך החובות.';
  static const advancedTitle = 'מתקדם';
  static const advancedHint = 'שלבי התזכורת, הנוסח ומספר התזכורות';
  static const customerCadenceTitle = 'תזכורות ללקוח הזה';
  static const termsAndReminders = 'תנאי תשלום ותזכורות';
  static String nextReminder(String day) => 'תזכורת הבאה: $day';
  static const manualHandling = 'לטיפול ידני';
  static const manualHandlingHint =
      'נשלחו כל התזכורות האוטומטיות. כדאי לפנות ללקוח בעצמך.';
  static const remindersPaused = 'תזכורות מושהות';

  static const settingsTitle = 'תזכורות גבייה אוטומטיות';
  static const settingsRowHint = 'מתי, באיזה ערוץ ובאיזה נוסח';
  static const master = 'שליחה אוטומטית';
  static const masterHint =
      'מייל יוצא מעצמו. ווטסאפ מחכה לך לאישור בנגיעה אחת.';
  static const whenTitle = 'מתי לשלוח';
  static const maxTitle = 'כמה תזכורות לכל היותר למסמך';
  static const channelsTitle = 'ערוצים';
  static const email = 'מייל';
  static const emailHint = 'נשלח אוטומטית עם המסמך מצורף';
  static const whatsapp = 'ווטסאפ';
  static const whatsappHint =
      'ללקוחות בלי מייל: מוכן לשליחה בנגיעה אחת מהטלפון';
  static const summary = 'התראה יומית אחת';
  static const summaryHint =
      'רק כשיש תזכורות ווטסאפ שמחכות. בלי התראה על כל לקוח.';
  static const quietHours =
      'לא נשלח בלילה (21:00–09:00), ביום שישי אחרי 13:00, בשבת ובחגים. '
      'תשלום, זיכוי או ביטול עוצרים את התזכורות מיד.';
  // ---- old debts (#9b): never a blast on switch-on --------------------------
  /// The switch-on dialog: only what is due from today gets the ladder.
  static String enableBody(int backlog) =>
      'תזכורות יישלחו רק על מסמכים שמועד התשלום שלהם היום או אחריו, לפי לוח הזמנים. '
      '${backlog == 0
          ? ''
          : backlog == 1
          ? 'לחוב ישן אחד לא תישלח תזכורת בלי שתאשר. '
          : 'ל-$backlog חובות ישנים לא תישלח תזכורת בלי שתאשר. '}'
      'אפשר לכבות בכל רגע.';
  static String backlogTitle(int n) => n == 1
      ? 'יש חוב ישן אחד. לשלוח לו תזכורת?'
      : 'יש $n חובות ישנים. לשלוח להם תזכורת?';
  static String backlogBody(int customers) =>
      'מועד התשלום שלהם עבר לפני שהפעלת את התזכורות. '
      '${customers == 1 ? 'הלקוח יקבל' : 'כל אחד מ-$customers הלקוחות יקבל'} תזכורת אחת בלבד, '
      'ולא יותר מאחת ללקוח ביום.';
  static const backlogSend = 'שלח תזכורת אחת';
  static const backlogLater = 'לא עכשיו';
  static const backlogApproved =
      'החובות הישנים יקבלו תזכורת אחת בימים הקרובים, בשעות השליחה.';
  static const saveFailed = 'השינוי לא נשמר. נסו שוב.';
  static const saved = 'נשמר';

  /// "3 ימים לפני מועד התשלום" / "ביום מועד התשלום" / "7 ימים אחרי…".
  static String stepLabel(int offsetDays) {
    if (offsetDays == 0) return 'ביום מועד התשלום';
    final n = offsetDays.abs();
    final days = n == 1 ? 'יום אחד' : '$n ימים';
    return offsetDays < 0 ? '$days לפני מועד התשלום' : '$days אחרי מועד התשלום';
  }

  static const stepCustomText = 'נוסח אישי';
  static const stepDefaultText = 'נוסח רגיל';

  // ---- step editor ----------------------------------------------------------
  static const editStep = 'עריכת תזכורת';
  static const before = 'לפני';
  static const onDay = 'ביום';
  static const after = 'אחרי';
  static const days = 'ימים';
  static const textTitle = 'נוסח ההודעה';
  static const textHint =
      'אפשר להוסיף פרטים קבועים בנגיעה: שם הלקוח, הסכום, מספר המסמך…';
  static const resetText = 'חזרה לנוסח הרגיל';
  static const saveStep = 'שמירה';
  static const stepClash = 'כבר יש תזכורת ביום הזה. בחרו יום אחר.';
  static const placeholderNames = {
    '{לקוח}': 'שם הלקוח',
    '{עסק}': 'שם העסק',
    '{מסמך}': 'סוג המסמך',
    '{מספר}': 'מספר מסמך',
    '{סכום}': 'סכום',
    '{תאריך}': 'מועד תשלום',
    '{קישור}': 'קישור למסמך',
  };

  // ---- the daily batch ------------------------------------------------------
  static const batchTitle = 'תזכורות מוכנות לשליחה';
  static String batchBanner(int n) =>
      n == 1 ? 'תזכורת אחת מוכנה לשליחה' : '$n תזכורות מוכנות לשליחה';
  static const batchBannerAction = 'לשליחה';
  static const batchHint =
      'נגיעה אחת פותחת ווטסאפ עם ההודעה מוכנה. המיילים כבר נשלחו מעצמם.';
  static const batchEmpty = 'אין תזכורות שמחכות לך';
  static const batchEmptyBody = 'כשתגיע תזכורת ללקוח בלי מייל, היא תופיע כאן.';
  static const send = 'שלח בווטסאפ';
  static String sendA11y(String customer) => 'שלח תזכורת בווטסאפ ל$customer';
  static const skip = 'דלג';
  static const sentNotice = 'התזכורת נשלחה ונרשמה';
  static const skippedNotice = 'דילגנו על התזכורת';
  static const more = 'עוד';
  static const pauseDocument = 'השהה תזכורות למסמך הזה';
  static const optOutCustomer = 'אל תשלח תזכורות ללקוח הזה';
  static const debtLine = 'רישום בפנקס החובות';

  // ---- holds (customer / document) -----------------------------------------
  static const holdCustomer = 'אל תשלח תזכורות ללקוח הזה';
  static const holdCustomerHint = 'תזכורות הגבייה האוטומטיות לא יישלחו אליו';
  static const holdDocument = 'השהה תזכורות אוטומטיות';
  static const holdDocumentHint = 'למסמך הזה בלבד';
}
