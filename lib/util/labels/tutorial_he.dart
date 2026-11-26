// 2611 §1: the first-run tutorial (4 cards) and the coach marks.

abstract final class TutorialHe {
  static const skip = 'דלג';
  static const next = 'הבא';
  static const start = 'בוא נתחיל';
  static String progress(int page, int of) => 'כרטיס $page מתוך $of';

  static const docTitle = 'מוציאים מסמך בשלוש נגיעות';
  static const docBody = 'נוגעים ב־+, בוחרים לקוח, כותבים סכום — והמסמך נשלח.';
  static const docSteps = ['+', 'לקוח', 'סכום', 'נשלח'];

  static const debtsTitle = 'יודעים מי חייב לך';
  static const debtsBody =
      'כרטיס "חייבים לך" מראה מי באיחור, ותזכורת בוואטסאפ יוצאת בנגיעה.';
  static const debtsCard = 'חייבים לך';
  static const debtsBubble = 'תזכורת ידידותית: החשבונית ממתינה לתשלום 🙏';

  static const customersTitle = 'הלקוחות במקום אחד';
  static const customersBody =
      'בדף הלקוח: המסמכים, החובות והפעולות המהירות — חשבונית, תשלום, פגישה.';
  static const customersSample = 'דף לקוח';

  static const calendarTitle = 'יומן וקביעת פגישות';
  static const calendarBody =
      'הלקוח קובע לבד מהקישור שלך, ואתה מקבל התראה. אפשר לחבר גם את יומן גוגל מהאייפון.';
  static const calendarGoogle = 'איך מחברים את יומן גוגל';
  static const calendarBooked = 'נקבעה פגישה חדשה';

  // Coach marks ("נקודות הסבר"): one bubble per screen, the first time.
  static const coachHome = 'כאן מוציאים מסמך חדש: חשבונית, קבלה או הצעת מחיר.';
  static const coachPeople = 'כאן מוסיפים לקוח — או מייבאים מאנשי הקשר.';
  static const coachPerson =
      'הפעולות המהירות: מסמך, תשלום, פגישה ותזכורת ללקוח הזה.';
  static const coachDismiss = 'נגיעה בכל מקום לסגירה';

  // עזרה
  static const replay = 'הצג שוב את ההדרכה';
}
