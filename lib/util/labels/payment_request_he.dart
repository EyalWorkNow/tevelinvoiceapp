// בקשת תשלום — the short payment-request screen (owner 2026-11-18, tester
// feedback "בקשת תשלום מובילה ליצירת חשבונית"). It issues a 300 (חשבון
// עסקה) but never looks like the Composer.

import '../money.dart' show formatMoney;

abstract final class PaymentRequestHe {
  static const title = 'בקשת תשלום';
  static const subtitle = 'הלקוח יקבל קישור לתשלום';

  static const customer = 'ממי לבקש';
  static const chooseCustomer = 'בחר לקוח';
  static const changeCustomer = 'החלף';

  static const amount = 'סכום לתשלום';
  static const amountHint = '0';
  static const amountExactVat = 'הסכום כולל מע״מ — זה בדיוק מה שהלקוח ישלם';
  static const amountExact = 'זה בדיוק מה שהלקוח ישלם';

  static const description = 'על מה';
  static const descriptionHint = 'לדוגמה: שיעור פרטי, תיקון מזגן';

  static const dueDate = 'לשלם עד';
  static const note = 'הערה ללקוח (לא חובה)';

  static const send = 'שלח בקשת תשלום';
  static const advanced = 'עריכה מתקדמת';

  static const needCustomer = 'בחר למי לשלוח';
  static const needAmount = 'הקלד סכום גדול מאפס';
  static const needDescription = 'כתוב על מה התשלום';

  static const notAvailable = 'אין לך הרשאה לשלוח בקשת תשלום';

  /// Under the amount once it is typed: "יופק חשבון עסקה על ₪590".
  static String issuesAs(BigInt totalMinor) =>
      'יופק חשבון עסקה על ${formatMoney(totalMinor, trimZeroAgorot: true)}';
}
