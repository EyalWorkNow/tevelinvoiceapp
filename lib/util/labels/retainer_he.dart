// "חבילת ריטיינר": recurring monthly invoices (SPEC-v2 BE-29, QA 2026-11-16
// C4). The server only creates DRAFTS on the chosen day; a person reviews and
// issues them on "חשבוניות החודש".

import '../../ui/money_text.dart' show ltrIsolate;

abstract final class RetainerHe {
  // ---- entry points ----
  static const monthTitle = 'חשבוניות החודש';
  static const templatesTitle = 'חשבוניות חודשיות';
  static const makeMonthly = 'הפוך לחשבונית חודשית';

  // ---- "הפוך לחודשי" sheet ----
  static const makeMonthlyTitle = 'חשבונית חודשית';
  static const makeMonthlySubtitle =
      'בכל חודש, ביום שתבחר, תוכן טיוטה זהה ללקוח הזה. שום דבר לא מופק או נשלח בלי אישור שלך.';
  static const dayOfMonth = 'יום בחודש';
  static String dayLabel(int day) =>
      day >= 29 ? '$day (או היום האחרון בחודש)' : '$day';
  static const create = 'צור חשבונית חודשית';
  static const created = 'החשבונית החודשית נשמרה';
  static const alreadyExists = 'כבר יש חשבונית חודשית למסמך הזה';

  // ---- month review ----
  static String readyCount(int n) => n == 1
      ? 'טיוטה חודשית אחת מוכנה לאישור'
      : '${ltrIsolate('$n')} טיוטות חודשיות מוכנות לאישור';
  static const nothingYet = 'אין טיוטות לחודש הזה';
  static const nothingYetBody =
      'הטיוטות נוצרות לבד ביום שנבחר לכל לקוח. אפשר להפוך חשבונית קיימת לחודשית מתפריט ⋯ שלה.';
  static const issueAll = 'הפק הכל';
  static const issuing = 'מפיק…';
  static const andSend = 'ושלח ללקוחות (מייל או ווטסאפ, לפי הלקוח)';
  static const editAmount = 'ערוך סכום';
  static const skip = 'דלג החודש';
  static const remove = 'הסר מהחבילה';
  static const removeConfirmTitle = 'להסיר את הלקוח מהחבילה?';
  static const removeConfirmBody =
      'הטיוטה של החודש תימחק, ולא ייווצרו טיוטות בחודשים הבאים.';
  static const removeConfirm = 'הסר';
  static const cancel = 'ביטול';
  static const save = 'שמור';
  static const unitPrice = 'מחיר לפני מע״מ';
  static String linePrice(int i) => 'שורה ${ltrIsolate('${i + 1}')}';

  // hints on a waiting draft
  static const hintApproval = 'יעבור לאישור לפני הפקה';
  static const hintAllocation = 'דורש מספר הקצאה';
  static const hintCustomerVat = 'חסר סטטוס עוסק ללקוח';

  // row states
  static String status(String s) => switch (s) {
    'DRAFTED' => 'ממתין',
    'SUBMITTED' => 'נשלח לאישור',
    'WAITING_ALLOCATION' => 'ממתין למספר הקצאה',
    'ISSUED' => 'הופק',
    'SKIPPED' => 'דולג',
    'REMOVED' => 'הוסר',
    'FAILED' => 'לא נוצר',
    _ => s,
  };

  // issue summary
  static String issueSummary({
    required int issued,
    required int submitted,
    required int waiting,
    required int failed,
  }) {
    final parts = <String>[
      if (issued > 0) 'הופקו ${ltrIsolate('$issued')}',
      if (submitted > 0) 'לאישור ${ltrIsolate('$submitted')}',
      if (waiting > 0) 'ממתינות למספר הקצאה ${ltrIsolate('$waiting')}',
      if (failed > 0) 'לא הופקו ${ltrIsolate('$failed')}',
    ];
    return parts.isEmpty ? 'אין מה להפיק' : parts.join(' · ');
  }

  static const signingLocked =
      'החתימה נעולה. פתח אותה כדי להשלים את ההפקה (שום דבר לא יופק פעמיים).';

  // ---- templates ----
  static const templatesEmpty = 'עוד אין חשבוניות חודשיות';
  static String every(int day) => day >= 29
      ? 'כל חודש ב-${ltrIsolate('$day')} (או ביום האחרון)'
      : 'כל חודש ב-${ltrIsolate('$day')}';

  /// Walkthrough 2026-11-17 #13: a template's amount is its lines BEFORE VAT
  /// (the server keeps net unit prices) — said so, never shown bare next to
  /// the gross amounts everywhere else (₪381.36 for a ₪450 invoice).
  static String netPlusVat(String amount) => '$amount + מע״מ';
  static String templateStatus(String s) => switch (s) {
    'ACTIVE' => 'פעילה',
    'PAUSED' => 'מושהית',
    'ENDED' => 'הסתיימה',
    _ => s,
  };
  static const pause = 'השהה';
  static const resume = 'חדש';
  static const end = 'סיים';
  static const endConfirmTitle = 'לסיים את החשבונית החודשית?';
  static const endConfirmBody =
      'לא ייווצרו טיוטות חדשות. מסמכים שכבר הופקו לא משתנים.';
  static const changePrice = 'שנה מחיר מהחודש הבא';
  static String priceFrom(String period) => 'מחיר חדש מ-${ltrIsolate(period)}';
  static const priceSaved = 'המחיר החדש יחול מהחודש הבא';

  static String error(String? code) => switch (code) {
    'RECURRING_TYPE_NOT_ALLOWED' =>
      'רק חשבונית מס או חשבון עסקה יכולים לחזור כל חודש.',
    'RECURRING_CUSTOMER_REQUIRED' => 'לחשבונית חודשית צריך לקוח.',
    'RECURRING_ALREADY_ISSUED' => 'החשבונית כבר הופקה או נשלחה לאישור.',
    'RECURRING_NOT_EDITABLE' => 'אפשר לערוך רק טיוטה שממתינה.',
    'RECURRING_ENDED' => 'החשבונית החודשית הסתיימה.',
    'APPROVAL_REQUIRED' => 'דרוש אישור לפני הפקה.',
    'ALLOCATION_REQUIRES_USER_INPUT' =>
      'צריך לעדכן אם הלקוח עוסק מורשה לפני ההפקה.',
    _ => 'לא הצלחנו להפיק. נסה שוב.',
  };
}
