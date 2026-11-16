// Payment labels — the ONE source for payment-method wording (squad C, §9.1).
//
// Stage C2 (CD-WALLET-01, server compliance/decision-register.md): bit and
// PayBox get their own chips, but on the wire they are BANK_TRANSFER with the
// wallet in `reference` ("ביט" / "פייבוקס"). The Uniform Format (1.31 §4.5,
// field 1306) has no wallet code, so the separate BIT / PAYBOX methods stay
// behind PAYMENT_METHODS_EXTENDED until an accountant signs the mapping
// (§19 q25). The tax file keeps code 4; reports, the daily summary and the
// receipt line show the wallet.

/// BE-14 (P1, 🛂): BIT / PAYBOX / WITHHOLDING_TAX / APPLE_PAY / GOOGLE_PAY as
/// their own server methods. Accepted only with PAYMENT_METHODS_EXTENDED=1,
/// after the compliance sign-off on the Uniform Format / printout mapping.
const bool extendedPaymentMethodsEnabled = false;

/// The wallet chips and the reference that marks them on a BANK_TRANSFER.
const Map<String, String> walletReferences = {
  'BIT': 'ביט',
  'PAYBOX': 'פייבוקס',
};

/// A chip that is sent as BANK_TRANSFER + wallet reference.
bool isWalletChip(String method) =>
    !extendedPaymentMethodsEnabled && walletReferences.containsKey(method);

/// The `method` POST /payments receives for a chip.
String wireMethod(String method) =>
    isWalletChip(method) ? 'BANK_TRANSFER' : method;

/// The `reference` a wallet chip writes (null for every other chip).
String? walletReference(String method) =>
    isWalletChip(method) ? walletReferences[method] : null;

/// The wallet of a stored payment: BIT / PAYBOX, or a BANK_TRANSFER whose
/// reference is "ביט" / "פייבוקס" (optionally + " " + the wallet's tx id).
String? walletOf(String method, String? reference) {
  if (walletReferences.containsKey(method)) return method;
  if (method != 'BANK_TRANSFER' || reference == null) return null;
  final ref = reference.trim();
  for (final e in walletReferences.entries) {
    if (ref == e.value || ref.startsWith('${e.value} ')) return e.key;
  }
  return null;
}

/// The chip a stored payment belongs to (wallet chip for a wallet transfer).
String chipOf(String method, String? reference) =>
    walletOf(method, reference) ?? method;

/// Label of a stored payment: "ביט" for a wallet transfer, else the method.
String paymentLabelOf(String method, String? reference) =>
    paymentMethodLabel(chipOf(method, reference));

/// Payment methods accepted by POST /payments, in chip order (§9.1).
const Map<String, String> paymentMethodLabels = {
  'CASH': 'מזומן',
  'BANK_TRANSFER': 'העברה',
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

/// Chips shown first (bit / PayBox next to cash: persona 04); the rest sit
/// behind "עוד".
const List<String> primaryPaymentMethods = [
  'CASH',
  'CREDIT_CARD',
  'BIT',
  'PAYBOX',
  'BANK_TRANSFER',
  'CHECK',
];
const List<String> morePaymentMethods = [
  if (extendedPaymentMethodsEnabled) ...[
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

  /// C2: the method is chosen, never assumed (bit after cash was saved as cash).
  static const pickMethod = 'איך שילמו? בחרו אמצעי תשלום';
  static String paidWith(String label) => 'אמצעי התשלום: $label';
}
