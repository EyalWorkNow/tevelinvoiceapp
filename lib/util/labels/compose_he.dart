// Labels owned by squad B – Composer, S1, S3 (SPEC-v2 §6.C, §8, F11).
// Every button word is imperative; shared verbs come from CommonHe.

import '../composer_config.dart';
import '../intent_resolver.dart';
import '../money.dart';

abstract final class ComposeHe {
  // Primary button (§6.C step 4).
  static const submit = 'שלח לאישור';
  static const sendQuoteWhatsApp = 'שלח הצעה בווטסאפ';
  static const sendQuote = 'שלח הצעה';
  static const issueAndWhatsApp = 'הפק ושלח בווטסאפ';
  static const issue = 'הפק';

  // Step texts while the button loads (§6.C states).
  static const stepIssuing = 'מפיק…';
  static const stepAuthority = 'בודק מול רשות המסים…';
  static const stepSigning = 'חותם…';
  static const stepPdf = 'יוצר PDF…';
  static const stepPayment = 'רושם תשלום…';
  static const stepSending = 'שולח…';

  static const amountQuestion = 'מה הסכום?';
  static const newInvoice = 'חשבונית חדשה';
  static const recordIncome = 'רישום הכנסה';

  // Screen.
  static const titleNew = 'מסמך חדש';
  static const titlePaid = 'קיבלתי תשלום';
  static const titleRequest = 'בקש תשלום';
  static const titleQuote = 'הצעת מחיר';

  /// The AppBar echoes the home intent, never the document type (F1).
  static String titleFor(String intent) => switch (intent) {
        intentPaid => titlePaid,
        intentRequest => titleRequest,
        intentQuote => titleQuote,
        _ => titleNew,
      };
  static const chooseCustomer = 'בחר לקוח';
  static const editCustomer = 'החלף לקוח';
  static const moreDetails = 'פרטים נוספים';
  static const vatIncludedHint = 'נגיעה מחליפה כולל ↔ לפני מע״מ';
  static const defaultDescription = 'שירותים';
  static const descriptionLabel = 'תיאור';
  static const editDescription = 'על מה?';
  static const methodMore = 'עוד';
  static const checkBank = 'בנק';
  static const checkBranch = 'סניף';
  static const checkAccount = 'חשבון';
  static const checkNumber = "מספר צ'ק";
  static const donorId = 'ת.ז. התורם';
  static const loadFailed = 'לא הצלחנו לטעון את המסמך';
  static const notAvailable = 'סוג המסמך הזה לא זמין לעסק';
  static const fixAndResend = 'תקן ושלח שוב';

  // Leaving / coming back (U0, U5).
  static const saveDraftTitle = 'לשמור טיוטה?';
  static const saveDraftBody = 'אפשר להמשיך אותה בפעם הבאה.';
  static const saveDraft = 'שמור טיוטה';
  static const discardDraft = 'מחק';
  static const resumeDraftTitle = 'יש טיוטה שלא הסתיימה';
  static String resumeDraftBody(String? customer, String amount) =>
      customer == null || customer.isEmpty
          ? '\u2066$amount\u2069'
          : '$customer · \u2066$amount\u2069';
  static const resumeDraft = 'המשך טיוטה';
  static const startNew = 'התחל חדש';

  // Dialogs.
  static String bigAmountTitle(BigInt total) =>
      'להפיק מסמך על ${formatMoney(total, trimZeroAgorot: true)}?';
  static const bigAmountBody = 'סכום גבוה במיוחד. בדוק שהסכום נכון לפני ההפקה.';
  static String vatDealerQuestion(String customer) => '$customer הוא עוסק מורשה?';
  static const vatDealerYes = 'כן';
  static const vatDealerNo = 'לא, לקוח פרטי';
  static const vatNumber = 'מספר עוסק מורשה';
  static const signingTitle = 'סיסמת החתימה';
  static const signingBody = 'פעם אחת בלבד: הסיסמה נשמרת במכשיר ונפתחת ב-Face ID.';
  static const signingSaveFaceId = 'שמור עם Face ID';
  static const signingReason = 'חתימה על המסמך';
  static const signingWrong = 'סיסמת החתימה שגויה';

  // After issue (toasts on D).
  static String issuedSentTo(String name) => 'הופק ✓ · נשלח ל$name בווטסאפ';
  static const issued = 'הופק ✓';
  static const submitted = 'נשלח לאישור ✓';
  static const firstIssueNote = 'מסמך שהופק לא נערך. לתיקון מפיקים זיכוי מ-⋯';
  static const waitingAllocation = 'ממתין למספר הקצאה מרשות המסים';
  static const waitingSignature = 'ממתין לחתימה';
  static const quoteSent = 'ההצעה נשלחה ✓';
  static const quoteNotSent = 'ההצעה נשמרה ולא נשלחה. אפשר לשלוח אותה מההצעה.';
  static const issuedShareFailed = 'המסמך הופק. השיתוף נכשל – אפשר לשתף מהמסמך.';
  static const issuedWhatsAppOpened = 'המסמך הופק. WhatsApp נפתח לשיתוף.';
  static String issuedDeliveryFailed(String reason) =>
      'המסמך הופק. המשלוח לא הושלם: $reason';

  // S1.
  static const s1Title = 'מה ליצור?';
  static const tileQuote = 'הצעת מחיר';
  static const tileExpense = 'הוצאה';
  static const tileCustomer = 'לקוח';
  static const tileMore = 'עוד סוגים';
  static const moreOnComputer = 'סוגים נוספים – המשך במחשב';

  // S3.
  static const s3Title = 'פרטים נוספים';
  static const lines = 'שורות';
  static const addLine = '+ שורה';
  static const lineDescription = 'תיאור';
  static const lineQuantity = 'כמות';
  static const linePrice = 'מחיר';
  static const removeLine = 'הסר שורה';
  static const discount = 'הנחה כוללת';
  static const discountTooBig = 'ההנחה גדולה מסכום השורה הראשית';
  static const vat = 'מע״מ';
  static const vatRegular = 'רגיל';
  static const vatNone = 'ללא';
  static const docType = 'סוג מסמך';
  static const customerAskedAllocation = 'הלקוח ביקש מספר הקצאה';
  static const validUntil = 'בתוקף עד';
  static const notes = 'הערה';
  static const notesHint = 'תודפס על המסמך';
  static const dueDate = 'תאריך פירעון';
  static const vatPerLine = 'לפי שורה';
  static const lineVatNone = 'ללא מע״מ';
  static const saveAsItem = 'לשמור כפריט?';
  static const savedAsItem = 'נשמר כפריט ✓';
}

/// "חשבונית מס-קבלה" etc. for the S3 / S1 type lists (shown only there and on
/// D, never before issuing in J1–J3 – F1).
const Map<DocKind, String> kindLabels = {
  DocKind.taxInvoiceReceipt: 'חשבונית מס-קבלה',
  DocKind.taxInvoice: 'חשבונית מס',
  DocKind.transactionInvoice: 'חשבון עסקה / פרופורמה',
  DocKind.receipt: 'קבלה',
  DocKind.donationReceipt: 'קבלה על תרומה',
  DocKind.credit: 'זיכוי',
  DocKind.quote: 'הצעת מחיר',
  DocKind.salesOrder: 'הזמנה',
  DocKind.purchaseOrder: 'הזמנת רכש',
};

String actionLabel(ComposerAction a) => switch (a) {
      ComposerAction.submit => ComposeHe.submit,
      ComposerAction.sendQuoteWhatsApp => ComposeHe.sendQuoteWhatsApp,
      ComposerAction.sendQuote => ComposeHe.sendQuote,
      ComposerAction.issueAndWhatsApp => ComposeHe.issueAndWhatsApp,
      ComposerAction.issue => ComposeHe.issue,
    };

/// "מסמך מ-₪5,000 כולל מע״מ דורש אישור" (§4.5 rule 2).
String approvalNote(BigInt thresholdMinor) =>
    'מסמך מ-${formatMoney(thresholdMinor, trimZeroAgorot: true)} כולל מע״מ דורש אישור';

/// "₪1,000 + ₪180 מע״מ = ₪1,180" (VatBreakdownLine), laid out LTR like a sum.
/// The Hebrew word sits in its own RTL isolate: bare, it pulled the amounts
/// after it into one RTL run ("₪12.71 + ₪15 = ₪2.29 מע״מ"). Wrap the result
/// in an LTR isolate when it is shown.
String vatBreakdown(BigInt net, BigInt vat, BigInt total) =>
    '${formatMoney(net, trimZeroAgorot: true)} + ${formatMoney(vat, trimZeroAgorot: true)}'
    ' \u2067מע״מ\u2069 = ${formatMoney(total, trimZeroAgorot: true)}';

String vatModeLabel(bool inclusive) => inclusive ? 'כולל מע״מ' : 'לפני מע״מ';

/// §13.5 fixed WhatsApp text (not editable in the app).
String issueWhatsAppText({
  required String customerName,
  required String typeLabel,
  required String? number,
  required BigInt totalMinor,
  required String link,
  required String businessName,
}) =>
    'שלום $customerName, מצורפת $typeLabel'
    '${number == null ? '' : ' מס\' $number'} על סך ${formatMoney(totalMinor, trimZeroAgorot: true)}. '
    'לצפייה ולתשלום: $link. תודה, $businessName';

/// P1 quote text (BE-06 link to the quote page + PDF), §13.5 wording.
String quoteLinkWhatsAppText({
  required String customerName,
  required BigInt totalMinor,
  required String validUntil,
  required String link,
  required String businessName,
}) =>
    'שלום $customerName, מצורפת הצעת מחיר על סך ${formatMoney(totalMinor, trimZeroAgorot: true)}, '
    'בתוקף עד $validUntil. לצפייה: $link. תודה, $businessName';

/// P0 quote text: the lines from the Composer's memory (§8.2.4); still used
/// when the server has no BE-06 share link.
String quoteWhatsAppText({
  required String customerName,
  required List<(String, BigInt)> lines,
  required BigInt totalMinor,
  required String validUntil,
  required String businessName,
}) {
  final b = StringBuffer('שלום $customerName, הצעת מחיר מ-$businessName:\n');
  for (final (d, amount) in lines) {
    b.writeln('• $d – ${formatMoney(amount, trimZeroAgorot: true)}');
  }
  b.write('סה״כ ${formatMoney(totalMinor, trimZeroAgorot: true)}, בתוקף עד $validUntil.');
  return b.toString();
}
