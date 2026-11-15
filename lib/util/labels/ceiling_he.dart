// Stage A · A6 — the עוסק פטור ceiling gauge (Home) and the opening-balance
// field (פרטי העסק). Official 2026 ceiling: ₪122,833 (רשות המסים,
// gov.il/he/pages/vat-rate-amount-new); the value itself comes from /me.

import 'inbox_he.dart';

abstract final class CeilingHe {
  static const title = 'תקרת עוסק פטור';

  /// "₪95,400 מתוך ₪122,833 · 79%"
  static String progress(String turnover, String ceiling, int percent) =>
      '$turnover מתוך $ceiling · $percent%';

  /// "14 באוגוסט" from YYYY-MM-DD; null when malformed.
  static String? dayMonth(String isoDate) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(isoDate);
    if (m == null) return null;
    final month = int.parse(m.group(2)!);
    final day = int.parse(m.group(3)!);
    if (month < 1 || month > 12) return null;
    return '$day ב${InboxHe.months[month - 1]}';
  }

  static String forecast(String dayMonth) => 'בקצב הזה תגיעי לתקרה ב-$dayMonth';
  static const forecastNotThisYear = 'בקצב הזה לא תגיעי לתקרה השנה';
  static const unknown = 'המחזור השנה עוד לא ידוע';
  static String unknownWithCeiling(String ceiling) =>
      'התקרה: $ceiling · המחזור השנה עוד לא ידוע';

  static const warn = 'עברת 80% מהתקרה';
  static const critical = 'עברת 95% מהתקרה';
  static const over = 'המחזור עבר את התקרה';
  static const nextStep = 'מה עושים כשעוברים? פנו לרו״ח / עברו לעוסק מורשה';
  static const switchAction = 'מעבר לעוסק מורשה';
  static const openingMissing =
      'הכנסות שקיבלת השנה לפני תבל לא נספרות. אפשר להוסיף אותן בפרטי העסק.';

  // Explanation sheet.
  static String explainTitle(int year) => 'תקרת עוסק פטור $year';
  static String explainCeiling(String ceiling) =>
      'עוסק פטור הוא עוסק שמחזור העסקאות שלו בשנה אינו עולה על $ceiling (סעיף 1 לחוק מע״מ).';
  static const explainCount =
      'אנחנו סופרים את הקבלות שהפקת בתבל מתחילת השנה, ועוד המחזור שהיה לך השנה לפני תבל (אם הזנת אותו בפרטי העסק).';
  static String explainOpening(String amount) => 'מחזור לפני תבל: $amount';
  static String explainReceipts(String amount) => 'קבלות בתבל השנה: $amount';
  static const explainForecast =
      'הצפי מחושב לפי הקצב הממוצע של 90 הימים האחרונים. זו הערכה, לא ייעוץ מס.';
  static const explainSource = 'מקור: רשות המסים, "סכומים ושיעורים במע״מ"';
  static String explainSourceYear(int year) =>
      'הסכום של $year עוד לא פורסם אצלנו, ולכן מוצגת התקרה האחרונה הידועה.';
  static const close = 'הבנתי';

  // פרטי העסק.
  static String openingField(int year) => 'מחזור מתחילת השנה לפני תבל ($year)';
  static const openingHint =
      'סך ההכנסות שקיבלת מ-1 בינואר ועד שהתחלת להפיק בתבל. נספר בתקרת הפטור.';
  static const openingInvalid = 'סכום לא תקין';
}
