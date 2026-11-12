// Labels owned by squad A – home (H, §6.H), "לטיפול" cards (§6.H.1) and
// activity (L, §6.L). F11: imperative verbs only.

import '../../state/caps.dart';
import '../money.dart';

abstract final class InboxHe {
  // Action labels shared by the application screens.
  static const dismissSummary = 'הסרה מהרשימה';
  static const allInvoicesAction = 'לכל המסמכים  ←';

  // H
  static const moneyLabel = 'מגיע לך';
  static const moneyOverdue = 'מתוכם באיחור';
  static const todo = 'לטיפול';
  static const inboxListTitle = 'משימות לטיפול';
  static const recent = 'מסמכים אחרונים';
  static const documentsAction = 'מסמכים';
  static const expensesAction = 'הוצאות';
  static const allActivity = 'כל הפעילות ›';
  static String moreCards(int n) => 'עוד $n ›';
  static const firstDocHint = 'הפק את הראשונה בפחות מדקה';
  static const noRecent = 'עוד אין מסמכים';
  static const switchBusinessHint = 'נגיעה להחלפת עסק';

  // Card actions (§6.H.1).
  static const actOpen = 'פתח';
  static const actFix = 'תקן';
  static const actIssue = 'הפק';
  static const actRetry = 'נסה שוב';
  static const actSign = 'חתום';
  static const actContinue = 'המשך';
  static const actSendReminders = 'שלח תזכורות';
  static const actReview = 'בדוק';
  static const actConvert = 'הפוך לחשבונית';
  static const actRenew = 'המשך במחשב';
  static const actAdd = 'הוסף';
  static const actIssueReceipt = 'הפק קבלה';
  static const actSend = 'שלח';

  // Card titles.
  static String approvalNeeded(int n) =>
      n == 1 ? 'מסמך אחד ממתין לאישורך' : '$n ממתינים לאישורך';
  static String myRejected(String? customer, String reason) {
    final who = (customer == null || customer.isEmpty)
        ? 'המסמך'
        : 'המסמך ל$customer';
    return reason.isEmpty ? '$who נדחה' : '$who נדחה: $reason';
  }

  static String myRejectedMany(int n) => '$n מסמכים שלך נדחו';
  static String taxInvoiceDue(String? customer, String? until) {
    final who = (customer == null || customer.isEmpty) ? 'הלקוח' : customer;
    final by = until == null ? '' : ' עד $until';
    return '$who שילם על חשבון עסקה – הפק חשבונית מס$by';
  }

  static String taxInvoiceDueMany(int n) =>
      '$n חשבונות עסקה שולמו – הפק חשבוניות מס';
  static String allocationProblem(String? number) => number == null
      ? 'חסר מספר הקצאה לחשבונית'
      : 'חסר מספר הקצאה לחשבונית $number';
  static String allocationProblemMany(int n) => 'חסר מספר הקצאה ל-$n חשבוניות';
  static String signingLocked(int n) =>
      n == 1 ? 'מסמך אחד ממתין לחתימה' : '$n מסמכים ממתינים לחתימה';
  static String unfinished(String? customer) =>
      (customer == null || customer.isEmpty)
      ? 'מסמך לא הושלם'
      : 'המסמך ל$customer לא הושלם';
  static String unfinishedMany(int n) => '$n מסמכים לא הושלמו';
  static String overdue(int n) =>
      n == 1 ? 'חשבונית אחת באיחור' : '$n חשבוניות באיחור';
  static String expenseReview(int n) =>
      n == 1 ? 'הוצאה אחת לבדיקה' : '$n הוצאות לבדיקה';
  static String quoteAccepted(String? customer) =>
      (customer == null || customer.isEmpty)
      ? 'הלקוח אישר את ההצעה'
      : '$customer אישר את ההצעה';
  static String shaamRenew(int days) => days <= 0
      ? 'החיבור לרשות המסים פג'
      : days == 1
      ? 'החיבור לרשות המסים יפוג מחר'
      : 'החיבור לרשות המסים יפוג בעוד $days ימים';
  static String paymentReceived(String? customer) =>
      (customer == null || customer.isEmpty)
      ? 'התקבל תשלום בקישור'
      : '$customer שילם בקישור';
  static const reportReady = 'דוח מוכן לשליחה';
  static const continuityGap = 'יש פער ברצף המסמכים';

  static const setupRecoveryCodes = 'שמור קודי שחזור';
  static const setupLogo = 'הוסף לוגו למסמכים';
  static const setupPaymentLink = 'הוסף קישור תשלום למסמכים';
  static const setupTeam = 'הזמן חבר צוות';

  // Reminders (§9.3).
  static const remindersSending = 'שולח תזכורות…';
  static String remindersDone(int sent, int whatsapp) {
    final parts = <String>[
      if (sent > 0)
        sent == 1 ? 'נשלחה תזכורת אחת במייל' : 'נשלחו $sent תזכורות במייל',
      if (whatsapp > 0) '$whatsapp בלי מייל – שלח בווטסאפ',
    ];
    return parts.isEmpty ? 'אין חשבוניות באיחור' : parts.join(' · ');
  }

  static const remindersWhatsApp = 'שלח בווטסאפ';
  static const remindersWhatsAppTitle = 'תזכורת בווטסאפ';
  static String reminderText({
    String? customer,
    String? number,
    required BigInt amountMinor,
    required String business,
    required String link,
    String? paymentUrl,
  }) => [
    'שלום${customer == null || customer.isEmpty ? '' : ' $customer'},',
    'תזכורת: חשבונית${number == null ? '' : ' $number'} על סך ${formatMoney(amountMinor, trimZeroAgorot: true)} מ-$business ממתינה לתשלום.',
    link,
    if (paymentUrl != null && paymentUrl.isNotEmpty) 'לתשלום: $paymentUrl',
  ].join('\n');
  static const allocationRetried = 'נשלחה בקשה חוזרת למספר הקצאה';
  static String signedDone(int n) => n == 1 ? 'המסמך נחתם' : '$n מסמכים נחתמו';
  static const handoffShaam = 'רשות המסים';
  static const handoffSent = 'שלחנו לך קישור במייל – פתח אותו במחשב';

  // "באיחור" preview (0.8): nothing is sent before the explicit confirm.
  static const remindersPreviewTitle = 'תזכורות לחשבוניות באיחור';
  static const remindersPreviewBody =
      'מי שיש לו מייל יקבל תזכורת במייל. לשאר נציע שליחה בווטסאפ.';
  static const remindersNone = 'אין חשבוניות באיחור';
  static String remindersConfirm(int n) =>
      n == 1 ? 'שלח תזכורת אחת' : 'שלח $n תזכורות';
  static const remindersCancel = 'ביטול';

  // Draft rows (AT-92).
  static const draftActions = 'פעולות לטיוטה';
  static const deleteDraft = 'מחק טיוטה';
  static const deleteDraftTitle = 'למחוק את הטיוטה?';
  static const deleteDraftBody = 'הטיוטה תימחק מרשימת המסמכים.';
  static const cancel = 'ביטול';

  // Navigation guards (1.11 / 1.12).
  static const routeForbidden = 'אין לך הרשאה למסך הזה';
  static const routeUnavailable = 'הקישור לא זמין';
  static const switchBusinessTitle = 'לעבור לעסק אחר?';
  static String switchBusinessBody(String name) =>
      'הקישור שייך לעסק "$name". הפעולות הבאות יתבצעו בעסק הזה.';
  static const switchBusinessConfirm = 'עבור לעסק';

  // L
  static const activityTitle = 'מסמכים';
  static const searchHint = 'שם, ח.פ., סכום או מספר מסמך';
  static const searchLabel = 'חיפוש';
  static const chipAll = 'הכל';
  static const chipUnpaid = 'לא שולם';
  static const chipDrafts = 'טיוטות';
  static const chipQuotes = 'הצעות';
  static const chipPaid = 'שולם';
  static const chipInbox = 'לטיפול';
  static const capped = 'מוצגים 500 המסמכים האחרונים';
  static const loadMore = 'טען עוד';
  static const noResults = 'לא נמצא';
  static const noResultsHint = 'נסה שם אחר, סכום או מספר מסמך';
  static const emptyAll = 'עוד אין מסמכים';
  static const emptyUnpaid = 'אין חשבוניות פתוחות';
  static const emptyDrafts = 'אין טיוטות';
  static const emptyQuotes = 'אין הצעות מחיר';
  static const quoteNoCustomer = 'הצעת מחיר';
  static String quoteValidUntil(String date) => 'בתוקף עד $date';
  static String quoteCreated(String date) => 'נוצרה $date';
  static const noCustomer = 'ללא לקוח';

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

  /// '2026-10' → 'אוקטובר 2026'.
  static String monthTitle(int year, int month) => '${months[month - 1]} $year';
}

/// Header tag for a non-owner (§6.H 1). Null for the owner.
const Map<Preset, String> presetTagLabels = {
  Preset.partner: 'שותף',
  Preset.employee: 'עובד',
  Preset.employeeIssuer: 'עובד',
  Preset.accountantRep: 'רואה חשבון',
  Preset.accountantFull: 'רו״ח – מלא',
  Preset.viewer: 'צפייה בלבד',
};

/// Document-type words for row subtitles (type · number). F1: the name of the
/// type is fine once issued (rows, D).
const Map<String, String> rowTypeLabels = {
  'SALES_ORDER': 'הזמנה',
  'TRANSACTION_INVOICE': 'חשבון עסקה',
  'TAX_INVOICE': 'חשבונית מס',
  'TAX_INVOICE_RECEIPT': 'חשבונית מס-קבלה',
  'CREDIT_DOCUMENT': 'חשבונית זיכוי',
  'RECEIPT': 'קבלה',
  'DONATION_RECEIPT': 'קבלה על תרומה',
  'PURCHASE_ORDER': 'הזמנת רכש',
};
