// The Israel civil date (Asia/Jerusalem) on the device, whatever its time
// zone: the server judges "today", issue dates and due dates by it. Israel
// time is UTC+2, and UTC+3 from the Friday before the last Sunday of March
// (02:00) to the last Sunday of October (02:00) — the rule since 2013.

/// Today in Israel as a date-only [DateTime] (local, midnight).
DateTime israelTodayDate([DateTime? now]) {
  final utc = (now ?? DateTime.now()).toUtc();
  final local = utc.add(Duration(hours: israelSummerTime(utc) ? 3 : 2));
  return DateTime(local.year, local.month, local.day);
}

/// Today in Israel, 'YYYY-MM-DD'.
String israelToday([DateTime? now]) => isoDate(israelTodayDate(now));

/// 'YYYY-MM-DD' of the calendar date of [d].
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// True when Israel summer time (UTC+3) is in force at [utc].
bool israelSummerTime(DateTime utc) {
  DateTime lastSunday(int month) {
    var d = DateTime.utc(utc.year, month + 1, 0);
    while (d.weekday != DateTime.sunday) {
      d = d.subtract(const Duration(days: 1));
    }
    return d;
  }

  // Starts Friday 02:00 IST (= 00:00 UTC); ends Sunday 02:00 IDT (= Saturday 23:00 UTC).
  final start = lastSunday(3).subtract(const Duration(days: 2));
  final end = lastSunday(10).subtract(const Duration(hours: 1));
  return !utc.isBefore(start) && utc.isBefore(end);
}
