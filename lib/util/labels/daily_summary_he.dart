// C2 · "סיכום יום" (Z-style daily summary by payment method). QA 2026-11-16
// persona 04 pain 1: "כמה עשיתי היום, ובאיזה אמצעי?".

import '../money.dart';

abstract final class DailySummaryHe {
  static const title = 'סיכום יום';
  static const titleWeek = 'סיכום השבוע';
  static const cardHint = 'כמה התקבל היום, לפי אמצעי תשלום';
  static const today = 'היום';
  static const week = 'השבוע';
  static const pickDay = 'בחירת יום';
  static const totalToday = 'התקבל היום';
  static const totalRange = 'התקבל בתקופה';
  static const byMethod = 'לפי אמצעי תשלום';
  static const receipts = 'התקבולים';
  static const empty = 'עוד לא נרשמו תקבולים בטווח הזה';
  static const shareWhatsApp = 'שלח בוואטסאפ';
  static const pdf = 'PDF';
  static const preparing = 'מכין…';
  static const restrictedNote =
      'את הסכומים רואים רק בעלי העסק ומנהלים. כאן מופיע מספר הקבלות שהפקת.';
  static const truncated = 'מוצגים 500 התקבולים הראשונים; הסכומים כוללים הכל.';
  static const timeZoneNote = 'לפי שעון ישראל, לפי מועד רישום התקבול.';

  static String count(int n) => n == 1 ? 'תקבול אחד' : '$n תקבולים';
  static String ownCount(int n) =>
      n == 1 ? 'הפקת קבלה אחת' : 'הפקת $n קבלות';
  static String methodLine(String label, int n, BigInt minor) =>
      '$label · ${count(n)} · ${formatMoney(minor)}';

  /// The WhatsApp text for the owner / accountant (amounts LTR-safe as-is).
  static String shareText({
    required String businessName,
    required String rangeLabel,
    required bool isDay,
    required BigInt totalMinor,
    required int count,
    required List<({String label, int count, BigInt totalMinor})> methods,
  }) {
    final lines = <String>[
      '${isDay ? title : titleWeek} · $businessName · $rangeLabel',
      'סה״כ: ${formatMoney(totalMinor)} (${DailySummaryHe.count(count)})',
      for (final m in methods)
        if (m.count > 0) '• ${m.label}: ${formatMoney(m.totalMinor)} (${m.count})',
    ];
    return lines.join('\n');
  }
}
