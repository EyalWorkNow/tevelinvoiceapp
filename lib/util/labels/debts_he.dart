// C1 · "מי חייב לי" and the debt book (ספר חובות). A debt-book line is an
// internal note — never a document, never revenue or VAT — and every label
// that shows one says so.

import 'document_he.dart' show docTypeLabel;

abstract final class DebtsHe {
  static const title = 'מי חייב לי';
  static const homeRow = 'מי חייב לי';
  static String homeRowA11y(int customers) =>
      customers == 1 ? 'מי חייב לי, לקוח אחד' : 'מי חייב לי, $customers לקוחות';

  /// Same figure as Home (open 300/305 balances) — named for what it is
  /// (tester 2026-11-18: "מגיע לך" did not say what the number is).
  static const headerLabel = 'יתרה לגבייה';

  /// An open document in the list. A 300 is what the owner sent as
  /// "בקשת תשלום" (tester 2026-11-18: payment requests belong here too).
  static String documentLine(String documentType, String? number) {
    final type = documentType == 'TRANSACTION_INVOICE'
        ? 'בקשת תשלום'
        : docTypeLabel(documentType);
    return number == null || number.isEmpty ? type : '$type מס׳ $number';
  }
  static const headerOverdue = 'באיחור';

  /// Under the header: the debt book is added on top of Home's figure, never into it.
  static const bookExtra = 'ועוד בפנקס החובות';
  static const bookExtraNote = 'רישום פנימי, לא מסמך ולא הכנסה';

  static const empty = 'אף אחד לא חייב לך 🎉';
  static const emptyBody = 'כשמישהו יחייב לך כסף, הוא יופיע כאן.';

  static const remind = 'שלח תזכורת בווטסאפ';
  static String remindA11y(String name) => 'שלח תזכורת בווטסאפ ל$name';
  static const paid = 'קיבלתי תשלום';
  static const documents = 'מסמכים';
  static const issueReceipt = 'הפק קבלה';
  static const delete = 'מחק מהפנקס';
  static const deleteConfirmTitle = 'למחוק מהפנקס?';
  static const deleteConfirmBody = 'הרישום יוסר מהרשימה. זה לא מבטל שום מסמך.';
  static const deleteConfirm = 'מחק';
  static const cancel = 'ביטול';

  static const noCustomer = 'ללא לקוח';
  static String overdueDays(int days) =>
      days == 1 ? 'באיחור של יום' : 'באיחור של $days ימים';
  static const notOverdue = 'עדיין לא באיחור';
  static String bookSince(int days) => switch (days) {
    <= 0 => 'בפנקס מהיום',
    1 => 'בפנקס מאתמול',
    _ => 'בפנקס כבר $days ימים',
  };
  static const neverReminded = 'עוד לא נשלחה תזכורת';

  /// Which tone the next reminder will have (shown before sending).
  static String nextTone(int previous) => switch (previous) {
    <= 0 => 'תזכורת ראשונה, בנוסח ידידותי',
    1 => 'תזכורת שנייה, בנוסח נחרץ יותר',
    _ => 'תזכורת ${previous + 1}, "נא להסדיר"',
  };

  /// The badge on every debt-book line.
  static const bookBadge = 'פנקס · לא מסמך';

  // ---- the "רשום חוב" sheet ----
  static const add = 'רשום חוב';
  static const addTitle = 'רשום חוב בפנקס';
  static const editTitle = 'עריכת חוב';
  static const addSubtitle =
      'רישום פנימי בלבד: לא חשבונית, לא נספר כהכנסה ולא במע״מ. '
      'כשישולם, מפיקים ממנו קבלה בנגיעה.';
  static const customer = 'מי חייב';
  static const pickCustomer = 'בחר לקוח';
  static const amount = 'סכום';
  static const note = 'על מה';
  static const noteHint = 'למשל: 3 שיעורים שלא שולמו';
  static const date = 'מתאריך';
  static const save = 'שמור בפנקס';
  static const saved = 'נרשם בפנקס';
  static const missingCustomer = 'צריך לבחור מי חייב';
  static const missingAmount = 'צריך סכום';
  static const missingNote = 'צריך לכתוב על מה';

  static const closed = 'הקבלה הופקה והחוב נסגר';
  static const closeFailed =
      'הקבלה הופקה, אבל החוב לא נסגר. אפשר לסגור אותו שוב מהרשימה.';
  static const reminderSent = 'התזכורת נפתחה בווטסאפ';
}
