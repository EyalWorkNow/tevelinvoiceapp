// Payment labels — the ONE source for payment-method wording (squad C, §9.1).
//
// P0: "העברה / ביט" is BANK_TRANSFER (no `reference` written; §9.1). Gate
// before the P0 release: compliance sign-off on that mapping (§19 q25); if it
// is refused, set [bitOnTransferChip] to false and the chip reads "העברה".

/// §19 q25: show "ביט" on the bank-transfer chip.
const bool bitOnTransferChip = !extendedPaymentMethodsEnabled;

/// BE-14 (P1, 🛂): BIT / PAYBOX / WITHHOLDING_TAX / APPLE_PAY / GOOGLE_PAY.
/// The server accepts them only with PAYMENT_METHODS_EXTENDED=1, after the
/// compliance sign-off on the Uniform Format / printout mapping. Turn this on
/// together with that flag; until then S5 keeps the P0 chips.
const bool extendedPaymentMethodsEnabled = false;

/// Payment methods accepted by POST /payments, in chip order (§9.1).
const Map<String, String> paymentMethodLabels = {
  'CASH': 'מזומן',
  'BANK_TRANSFER': bitOnTransferChip ? 'העברה / ביט' : 'העברה',
  'CREDIT_CARD': 'כרטיס אשראי',
  'CHECK': "צ'ק",
  'DIRECT_DEBIT': 'הוראת קבע',
  'OTHER': 'אחר',
  'BIT': 'ביט',
  'PAYBOX': 'פייבוקס',
  'WITHHOLDING_TAX': 'ניכוי במקור',
  'APPLE_PAY': 'Apple Pay',
  'GOOGLE_PAY': 'Google Pay',
};

/// Chips shown first; the rest sit behind "עוד".
const List<String> primaryPaymentMethods = [
  'CASH',
  'BANK_TRANSFER',
  'CREDIT_CARD',
  'CHECK',
];
const List<String> morePaymentMethods = [
  if (extendedPaymentMethodsEnabled) ...[
    'BIT',
    'PAYBOX',
    'WITHHOLDING_TAX',
    'APPLE_PAY',
    'GOOGLE_PAY',
  ],
  'DIRECT_DEBIT',
  'OTHER',
];

String paymentMethodLabel(String method) =>
    paymentMethodLabels[method] ?? method;

/// S5 wording (F11: imperative verbs only on buttons).
abstract final class PaymentHe {
  /// Card-clearing preview button (the clearing itself comes later).
  static const comingSoon = 'בקרוב';
  static const title = 'תשלום';
  static const record = 'רשום';
  static const recording = 'רושם…';
  static const issuingReceipt = 'מפיק קבלה…';
  static const amount = 'סכום';
  static const date = 'תאריך';
  static const method = 'אמצעי';
  static const more = 'עוד';
  static const addPayment = '+ תשלום נוסף';
  static const addCheck = "+ צ'ק נוסף";
  static const remove = 'הסר';
  static const bank = 'בנק';
  static const branch = 'סניף';
  static const account = 'חשבון';
  static const checkNumber = "מספר צ'ק";
  static const checkDate = "תאריך הצ'ק";
  static const paymentN = 'תשלום';
  static const balance = 'יתרה לתשלום';
  static const overBalance = 'הסכום גבוה מהיתרה';
  static const amountRequired = 'צריך סכום';
  static const checkDetailsRequired = "לצ'ק צריך בנק, סניף, חשבון ומספר צ'ק";
  static const digitsOnly = 'ספרות בלבד';
  static const receiptIssued = 'הקבלה הופקה ✓';
  static const paymentRecorded = 'התשלום נרשם ✓';
  static const sendReceipt = 'שלח קבלה בווטסאפ';
}
