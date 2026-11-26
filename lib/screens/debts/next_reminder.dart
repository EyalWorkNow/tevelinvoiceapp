// 2611 §2: "תזכורת הבאה: יום ב׳ 1.12" / "לטיפול ידני" on the "חייבים לך"
// screen — what the server's projection (GET /debts nextReminder) says.

import '../../util/labels/collection_he.dart';
import '../../util/labels/person_page_he.dart';

/// "יום ב׳ 1.12" for an Israel civil date (YYYY-MM-DD); null when unreadable.
String? reminderDayLabel(String? isoDate) {
  if (isoDate == null) return null;
  final d = DateTime.tryParse(isoDate);
  if (d == null) return null;
  return PersonPageHe.dayLabel(
    PersonPageHe.weekdayShort[d.weekday % 7],
    '${d.day}.${d.month}',
  );
}

/// The line under a debtor / a document: the next automatic reminder, or
/// "לטיפול ידני" (the ceiling reached), or null (off / paused / nothing).
String? nextReminderLine({required String? state, required String? date}) {
  if (state == 'MANUAL') return CollectionHe.manualHandling;
  if (state == 'PAUSED') return CollectionHe.remindersPaused;
  if (state != 'SCHEDULED') return null;
  final day = reminderDayLabel(date);
  return day == null ? null : CollectionHe.nextReminder(day);
}
