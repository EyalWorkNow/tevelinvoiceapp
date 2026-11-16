// SA2 · a document that waits for its allocation number, and the money that
// waits with it (QA 2026-11-16, persona 02 pain 2). Plain words, no codes.

import '../money.dart';
import 'payment_he.dart';

abstract final class PendingPaymentHe {
  static const waitingTitle = 'המסמך ממתין למספר הקצאה';
  static const waitingWhy =
      'חשבונית בסכום גבוה צריכה מספר הקצאה מרשות המסים. המסמך שמור אצלנו, '
      'ויופק ללקוח ברגע שהמספר יגיע.';
  static const whatNow = 'מה אפשר לעשות:';
  static const optionWait =
      'לחכות. נעדכן כאן כשהמספר יגיע, אין צורך לעשות דבר.';
  static const optionManual =
      'קיבלת מספר הקצאה באתר רשות המסים? אפשר להזין אותו כאן.';
  static const optionCancel =
      'לבטל את הבקשה ולהחזיר את המסמך לטיוטה, כדי לשנות אותו.';
  static const optionCancelWithPayment =
      'לבטל את הבקשה ולהחזיר את המסמך לטיוטה. גם התשלום הממתין יבוטל, '
      'ותצטרך לרשום אותו שוב בהפקה.';

  // Buttons (AT-92: words live here).
  static const enterNumber = 'הזן מספר הקצאה';
  static const cancelRequest = 'בטל את הבקשה';
  static const edit = 'ערוך';
  static const cancelPayment = 'בטל תשלום';

  /// "תשלום ממתין: ₪1,180.00 ביט, יירשם כשיתקבל מספר ההקצאה"
  static String pendingLine(
    BigInt amountMinor,
    String method, [
    String? reference,
  ]) =>
      'תשלום ממתין: ${formatMoney(amountMinor)} '
      '${paymentLabelOf(method, reference)}, יירשם כשיתקבל מספר ההקצאה';

  static const editTitle = 'עריכת התשלום הממתין';
  static const amountHint = 'סכום בשקלים';
  static const amountInvalid = 'צריך סכום גדול מאפס';
  static const cancelTitle = 'לבטל את התשלום הממתין?';
  static const cancelBody =
      'התשלום לא יירשם כשיגיע מספר ההקצאה. אם הלקוח שילם, אפשר לרשום אותו שוב אחר כך.';
  static const keep = 'השאר';
  static const updated = 'התשלום הממתין עודכן';
  static const cancelled = 'התשלום הממתין בוטל';

  /// Composer toast when a paid document stops for its allocation number.
  static const issuedWaitingWithPayment =
      'ממתין למספר הקצאה. התשלום נשמר ויירשם כשהמספר יגיע';
}
