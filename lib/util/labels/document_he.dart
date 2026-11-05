// Document labels (squad C). Types + statuses ported from
// invoiceproject apps/web/src/pages/labels.ts.

const Map<String, String> docTypeLabels = {
  'SALES_ORDER': 'הזמנה',
  'DELIVERY_NOTE': 'תעודת משלוח',
  'AGENT_DELIVERY_NOTE': 'תעודת משלוח סוכן',
  'RETURN_NOTE': 'תעודת החזרה',
  'TRANSACTION_INVOICE': 'חשבון עסקה',
  'TAX_INVOICE': 'חשבונית מס',
  'CONCENTRATED_INVOICE': 'חשבונית ריכוז',
  'TAX_INVOICE_RECEIPT': 'חשבונית מס/קבלה',
  'CREDIT_DOCUMENT': 'חשבונית זיכוי',
  'RESERVATION_INVOICE': 'חשבונית שריון',
  'AGENT_INVOICE': 'חשבונית סוכן',
  'RECEIPT': 'קבלה',
  'DONATION_RECEIPT': 'קבלה על תרומות (סעיף 46)',
  'PETTY_CASH_OUT': 'יציאה מקופה',
  'BANK_DEPOSIT': 'הפקדת בנק',
  'PURCHASE_ORDER': 'הזמנת רכש',
  'GOODS_RECEIVED_NOTE': 'תעודת משלוח רכש',
  'VENDOR_RETURN_NOTE': 'החזרת רכש',
  'VENDOR_TAX_INVOICE': 'חשבונית מס רכש',
  'VENDOR_CREDIT_NOTE': 'זיכוי רכש',
  'INVENTORY_OPENING': 'יתרת פתיחה למלאי',
  'STOCK_ENTRY': 'כניסה כללית למלאי',
  'STOCK_EXIT': 'יציאה כללית מהמלאי',
  'WAREHOUSE_TRANSFER': 'העברה בין מחסנים',
  'STOCKTAKE_ADJUSTMENT': 'עדכון בעקבות ספירת מלאי',
  'PRODUCTION_ENTRY': 'דוח ייצור - כניסה',
  'PRODUCTION_EXIT': 'דוח ייצור - יציאה',
};

String docTypeLabel(String type) => docTypeLabels[type] ?? type;

/// Document types where VAT is forbidden (web VAT_FORBIDDEN_TYPES).
const Set<String> vatForbiddenTypes = {
  'DELIVERY_NOTE', 'AGENT_DELIVERY_NOTE', 'RETURN_NOTE', 'RECEIPT', 'DONATION_RECEIPT',
  'PETTY_CASH_OUT', 'BANK_DEPOSIT', 'GOODS_RECEIVED_NOTE', 'VENDOR_RETURN_NOTE',
  'INVENTORY_OPENING', 'STOCK_ENTRY', 'STOCK_EXIT', 'WAREHOUSE_TRANSFER',
  'STOCKTAKE_ADJUSTMENT', 'PRODUCTION_ENTRY', 'PRODUCTION_EXIT',
};

/// Short type names for the D header ("חשבונית מס 1042").
String docTitle(String documentType, String? number) =>
    number == null || number.isEmpty ? docTypeLabel(documentType) : '${docTypeLabel(documentType)} $number';

/// D · S6 · S8 wording (squad C). F11: buttons are imperative verbs.
abstract final class DocumentHe {
  // §6.D primary buttons (nextAction rows 1–16).
  static const approveAndIssue = 'אשר והפק';
  static const reject = 'דחה';
  static const continueDraft = 'המשך';
  static const fixAndResend = 'תקן ושלח שוב';
  static const retry = 'נסה שוב';
  static const signAndIssue = 'חתום והפק PDF';
  static const sendWhatsApp = 'שלח בווטסאפ';
  static const send = 'שלח';
  static const recordPayment = 'קיבלתי תשלום';
  static const sendAgain = 'שלח שוב';
  static const sendReminder = 'שלח תזכורת';
  static const sendQuote = 'שלח הצעה';
  static const convertToInvoice = 'הפוך לחשבונית';
  static const customerRejected = 'הלקוח דחה';
  static const openInvoice = 'פתח חשבונית';
  static const share = 'שתף';

  // Row 4 menu (allocation).
  static const manualAllocation = 'הזן מספר ידנית';
  static const continueWithoutNumber = 'המשך בלי מספר';
  static const cancelAllocation = 'בטל בקשה';
  static const connectTaxAuthority = 'התחבר לרשות המסים';

  // 100 / 300 → 305 (BE-08 linked clone).
  static const issueTaxInvoice = 'הפק חשבונית מס';

  // Fixed ⋯ items.
  static const duplicate = 'שכפל';
  static const pdfClose = 'סגירה';
  static const cancelOrCredit = 'בטל / זכה';

  // "—" rows: the line shown instead of a button.
  static const waitingApproval = 'ממתין לאישור';
  static String waitingApprovalOf(String name) => 'ממתין לאישור של $name';
  static const waitingAllocation = 'ממתין למספר הקצאה';
  static const waitingSignature = 'ממתין לחתימה של בעל העסק';
  static const notRelevant = 'לא רלוונטית';

  // Status line + timeline.
  static const taxAuthorityOk = '✓ אושר ברשות המסים';
  static const sentWhatsApp = 'נשלח';
  static const timelineCreated = 'נוצר';
  static const timelineIssued = 'הופק';
  static const timelinePaid = 'שולם';
  static const timelineCredited = 'זוכה';
  static const timelineVoided = 'בוטל';
  static const timelineSent = 'נשלח ללקוח';
  static const timelineSubmitted = 'נשלח לאישור';
  static const showTimeline = 'הצג היסטוריה';
  static const quoteValidUntil = 'בתוקף עד';
  static const quoteTitle = 'הצעת מחיר';
  static const quoteNoPdf = 'אין פירוט שורות להצעה זו';
  static const quoteLinesTitle = 'פירוט';
  static const quoteNet = 'לפני מע״מ';
  static const quoteVatOnConvert = 'המע״מ ייקבע בהפיכה לחשבונית';
  static const draftNoPdf = 'טיוטה – ה-PDF ייווצר בהפקה';
  static const pdfOpen = 'נגיעה לפתיחה במסך מלא';
  static const pdfUnavailable = 'ה-PDF עוד לא מוכן';
  static const pdfNotCreated = 'ה-PDF של המסמך עוד לא נוצר';
  static const pdfLoadFailed = 'לא הצלחנו לטעון את ה-PDF';
  static const rejectedBecause = 'נדחה:';
  static const commitToast = 'מסמך שהופק לא נערך. לתיקון מפיקים זיכוי מ-⋯';

  // Dialogs (≤1 field each — not sheets, F4).
  static const rejectTitle = 'למה לדחות?';
  static const rejectHint = 'הסיבה תוצג למי שהגיש';
  static const reasonRequired = 'צריך לכתוב סיבה';
  static const manualTitle = 'מספר הקצאה';
  static const manualHint = '9 ספרות לפחות';
  static const passphraseTitle = 'סיסמת החתימה';
  static const passphraseHint = 'הסיסמה שקיבלת בהפעלת החתימה';
  static const rememberWithFaceId = 'שמור עם Face ID';
  static const saveWithFaceId = 'שמור עם Face ID';
  static const consentTitle = 'הלקוח הסכים לקבל מסמכים במייל?';
  static const consentBody = 'לפי הוראות ניהול ספרים, מסמך ממוחשב נשלח במייל רק בהסכמת הלקוח.';
  static const consentYes = 'כן, הסכים';
  static const consentNoWhatsApp = 'שלח בווטסאפ במקום';
  static const continueOnComputerTitle = 'המשך במחשב';
  static const continueOnComputerBody = 'נשלח אליך קישור במייל כדי להמשיך במחשב.';
  static const sendMeLink = 'שלח לי קישור';

  // S6.
  static const shareTitle = 'שתף';
  static const email = 'מייל';
  static const sendEmail = 'שלח במייל';
  static const emailHint = 'כתובת מייל';
  static const emailInvalid = 'כתובת המייל לא תקינה';
  static const copyLink = 'העתק קישור';
  static const linkCopied = 'הקישור הועתק – בתוקף ל-30 יום';
  static const pdf = 'PDF';
  static const pdfCopy = 'PDF העתק נאמן למקור';
  static const showQr = 'הצג QR לתשלום';
  static const qrGeneral = 'קישור תשלום כללי – הלקוח יקליד את הסכום';
  static const setupPaymentLink = 'הגדר קישור תשלום';
  static const qrCaption = 'הלקוח סורק ורואה את המסמך ואת הסכום';
  static const revokeLink = 'בטל קישור';
  static const linkRevoked = 'הקישור בוטל';
  static const emailSent = 'המייל נשלח ✓';
  static const emailQueued = 'המייל בדרך – ננסה שוב אוטומטית';
  static const emailFailed = 'שליחת המייל נכשלה – נסה שוב';

  // S8.
  static const cancelTitle = 'בטל / זכה';
  static const issueCredit = 'הפק זיכוי';
  static const voidDocument = 'בטל מסמך';
  static String fullCredit(String amount) => 'זיכוי מלא $amount';
  static const partialCredit = 'זיכוי חלקי';
  static const creditAmount = 'סכום הזיכוי (כולל מע״מ)';
  static String creditMax(String amount) => 'אפשר לזכות עד $amount';
  static const creditEffect = 'יופק מסמך זיכוי ללקוח. המסמך המקורי לא נמחק.';
  static const creditPaidNote =
      'הזיכוי לא מחזיר כסף. אם החזרת כסף ללקוח – זה נעשה מחוץ לאפליקציה';
  static const credit320Note = 'התשלום שבמסמך נשאר רשום; הזיכוי יוצר יתרת זכות ללקוח.';
  static const voidEffect = 'המסמך יסומן "בוטל". לא נוצר מסמך חדש.';
  static const voidHasPayments = 'יש תשלום. בטל קודם את הקבלה במחשב';
  static const voidReason = 'סיבת הביטול';
  static const creditIssued = 'הזיכוי הופק ✓';
  static const documentVoided = 'המסמך בוטל ✓';
  static String partialCreditLine(String? number) =>
      number == null ? 'זיכוי חלקי' : 'זיכוי חלקי לחשבונית $number';

  // Banners / toasts after actions.
  static const approved = 'אושר והופק ✓';
  static const rejected = 'נדחה – המגיש יראה את הסיבה';
  static const markedRejected = 'סומן "לא רלוונטית"';
  static const allocationRetried = 'נשלח שוב לרשות המסים';
  static const duplicated = 'נוצרה טיוטה חדשה';
  static const quoteDuplicated = 'נוצרה הצעה חדשה';

  // Timeline (BE-12) — raw audit types → words. Unknown types are not shown.
  static const Map<String, String> timelineEvents = {
    'document.draft_created': 'נוצר',
    'document.cloned': 'נוצר משכפול',
    'document.approval_submitted': 'נשלח לאישור',
    'document.approval_approved': 'אושר',
    'document.approval_rejected': 'נדחה',
    'document.finalized': 'הופק',
    'document.allocation_requested': 'נשלח לרשות המסים',
    'document.allocation_cancelled': 'בקשת המספר בוטלה',
    'document.signed': 'נחתם',
    'document.shared': 'נוצר קישור ללקוח',
    'document.share_downloaded': 'הלקוח צפה',
    'document.share_revoked': 'הקישור בוטל',
    'document.sent': 'נשלח במייל',
    'document.send_failed': 'שליחת המייל נכשלה',
    'document.send_blocked_no_consent': 'המייל לא נשלח – אין הסכמה',
    'document.credited': 'זוכה',
    'document.voided': 'בוטל',
    'payment.allocated': 'נרשם תשלום',
    'receipt.issued': 'הופקה קבלה',
  };
  static const timelineTitle = 'היסטוריה';
  static const paymentsTitle = 'תשלומים';
  static const linkedTitle = 'מסמכים קשורים';
  static const voidedPayment = 'בוטל';

  /// `linkedDocuments[].relation` → how the other document relates.
  static const Map<String, String> linkRelations = {
    'RECEIPT': 'קבלה',
    'CREDIT': 'זיכוי',
    'CONVERTED_TO': 'הופק ממנו',
    'RECEIPT_FOR': 'קבלה עבור',
    'CREDIT_FOR': 'זיכוי של',
    'CONVERTED_FROM': 'נוצר מ',
  };
  static String dueBy(String date) => 'לתשלום עד $date';

  // Payments ledger (BE-11, R → "תקבולים").
  static const ledgerTitle = 'תקבולים';
  static const ledgerEmpty = 'אין תשלומים בתקופה';
  static const ledgerMore = 'הצג עוד';
  static const voidPayment = 'בטל תשלום';
  static const voidPaymentTitle = 'למה לבטל את התשלום?';
  static const paymentVoided = 'התשלום בוטל ✓';
  static String receiptNo(String n) => 'קבלה $n';

  /// Server codes of the P1 money endpoints (SRV-2) that the shared Hebrew
  /// table (errors_he, INT) does not carry yet; texts as apps/web/src/api.ts.
  static const Map<String, String> serverErrors = {
    'PAYMENT_LOCKED_IN_DOCUMENT':
        'התשלום כלול במסמך שהופק. לביטול – הפק זיכוי, או בטל את הקבלה במחשב.',
    'PAYMENT_VOIDED': 'התשלום בוטל ולא ניתן להשתמש בו.',
    'PAYMENT_NOT_FOUND': 'התשלום לא נמצא.',
    'PAYMENT_METHOD_NOT_ENABLED': 'אמצעי התשלום עדיין לא זמין. רשום אותו כהעברה בנקאית.',
    'DOCUMENT_VOID_NOT_ALLOWED': 'אפשר לבטל כך רק חשבון עסקה, הזמנה או הזמנת רכש שהופקו.',
    'DOCUMENT_ALREADY_VOIDED': 'המסמך כבר בוטל.',
    'DOCUMENT_HAS_PAYMENTS': 'יש תשלום. בטל קודם את הקבלה במחשב',
    'CLONE_TYPE_NOT_ALLOWED': 'אי אפשר לשכפל לסוג המסמך הזה.',
    'ALLOCATION_NUMBER_RESERVED':
        'המספר כבר שמור ברשות המסים – אי אפשר לבטל את הבקשה. בחר "המשך בלי מספר" או נסה שוב.',
  };
}
