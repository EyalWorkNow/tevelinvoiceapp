// "יומן" (spec §9, iOS-style): the pure geometry behind the month grid and
// the day timeline — no widgets, so it is unit-tested on its own.
//
//   · month grid: Sunday first (right to left on screen), 5–6 week rows;
//   · day timeline: events placed in side-by-side columns when they overlap
//     (each cluster of transitively overlapping events shares its columns);
//   · drag: a vertical offset → a new start, snapped to 15 minutes;
//   · working hours (white) and blocked dates (grey) of the settings.

import 'calendar_api.dart';
import 'calendar_screen.dart' show AgendaItem;

DateTime dayOf(DateTime d) {
  final l = d.isUtc ? d.toLocal() : d;
  return DateTime(l.year, l.month, l.day);
}

/// The first of [d]'s month.
DateTime monthOf(DateTime d) => DateTime(d.year, d.month);

/// [month] moved by [by] months (always the 1st).
DateTime addMonths(DateTime month, int by) =>
    DateTime(month.year, month.month + by);

/// Whole months from [from] to [to] (both firsts).
int monthsBetween(DateTime from, DateTime to) =>
    (to.year - from.year) * 12 + to.month - from.month;

/// Empty cells before the 1st (Sunday = 0).
int leadingBlanks(DateTime month) =>
    DateTime(month.year, month.month).weekday % 7;

int daysInMonth(DateTime month) => DateTime(month.year, month.month + 1, 0).day;

/// Week rows the month needs (4–6).
int weekRows(DateTime month) =>
    ((leadingBlanks(month) + daysInMonth(month)) / 7).ceil();

/// The Sunday that starts [d]'s week.
DateTime weekStart(DateTime d) {
  final day = dayOf(d);
  return DateTime(day.year, day.month, day.day - day.weekday % 7);
}

/// One event on a day's timeline. Minutes are from that day's midnight,
/// clipped to the day; [column] of [columns] side by side.
class TimelineEntry {
  const TimelineEntry({
    required this.item,
    required this.startMinute,
    required this.endMinute,
    required this.column,
    required this.columns,
  });

  final AgendaItem item;
  final int startMinute;
  final int endMinute;
  final int column;
  final int columns;

  int get minutes => endMinute - startMinute;
}

/// Places [items] that touch [day] on its timeline. Overlapping events split
/// the width: a cluster (events chained by overlaps) gets as many columns as
/// its widest moment; each event takes the first column free at its start.
List<TimelineEntry> layoutDay(List<AgendaItem> items, DateTime day) {
  final start = dayOf(day);
  final end = DateTime(start.year, start.month, start.day + 1);
  int minuteOf(DateTime t) {
    final l = t.toLocal();
    if (!l.isAfter(start)) return 0;
    if (!l.isBefore(end)) return 24 * 60;
    return l.difference(start).inMinutes;
  }

  final placed = [
    for (final i in items)
      if (i.startsAt.toLocal().isBefore(end) &&
          i.endsAt.toLocal().isAfter(start))
        (item: i, s: minuteOf(i.startsAt), e: minuteOf(i.endsAt)),
  ]..sort((a, b) => a.s != b.s ? a.s.compareTo(b.s) : b.e.compareTo(a.e));

  final out = <TimelineEntry>[];
  var cluster = <({AgendaItem item, int s, int e, int col})>[];
  var clusterEnd = -1;
  final columnEnds = <int>[];

  void flush() {
    final columns = columnEnds.length;
    for (final c in cluster) {
      out.add(
        TimelineEntry(
          item: c.item,
          startMinute: c.s,
          endMinute: c.e,
          column: c.col,
          columns: columns,
        ),
      );
    }
    cluster = [];
    columnEnds.clear();
  }

  for (final p in placed) {
    if (cluster.isNotEmpty && p.s >= clusterEnd) flush();
    var col = columnEnds.indexWhere((e) => e <= p.s);
    if (col < 0) {
      col = columnEnds.length;
      columnEnds.add(p.e);
    } else {
      columnEnds[col] = p.e;
    }
    clusterEnd = cluster.isEmpty || p.e > clusterEnd ? p.e : clusterEnd;
    cluster.add((item: p.item, s: p.s, e: p.e, col: col));
  }
  if (cluster.isNotEmpty) flush();
  return out;
}

/// Minutes a drag of [dy] pixels moves an event, at [pixelsPerMinute],
/// snapped to [step] minutes.
int snappedMinutes(double dy, {double pixelsPerMinute = 1, int step = 15}) =>
    ((dy / pixelsPerMinute) / step).round() * step;

/// The working ranges of [day] in minutes from midnight (settings hours).
List<(int, int)> workingMinutes(List<DayHours> week, DateTime day) {
  final weekday = dayOf(day).weekday % 7;
  int parse(String hm) {
    final parts = hm.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  for (final d in week) {
    if (d.day != weekday) continue;
    return [for (final r in d.ranges) (parse(r.start), parse(r.end))];
  }
  return const [];
}

/// A vacation / blocked date (settings → חסימת תאריכים).
bool isBlockedDay(List<BlockedRange> blocked, DateTime day) {
  final key = ymd(dayOf(day));
  return blocked.any(
    (r) => r.from.compareTo(key) <= 0 && r.to.compareTo(key) >= 0,
  );
}

/// What the month grid marks under a day.
class DayMarks {
  const DayMarks({this.meetings = 0, this.pending = 0});
  final int meetings;
  final int pending;
  bool get any => meetings + pending > 0;
}

/// Confirmed and pending meetings per local day (cancelled ones not shown).
Map<DateTime, DayMarks> marksByDay(Iterable<Booking> bookings) {
  final out = <DateTime, DayMarks>{};
  for (final b in bookings) {
    if (b.closed) continue;
    final d = dayOf(b.startsAt);
    final m = out[d] ?? const DayMarks();
    out[d] = DayMarks(
      meetings: m.meetings + (b.confirmed ? 1 : 0),
      pending: m.pending + (b.pending ? 1 : 0),
    );
  }
  return out;
}

/// The free slot to preselect after a long-press at [at]: the first one that
/// starts at or after it on the same day, else the last one before it.
FreeSlot? slotNear(List<FreeSlot> slots, DateTime at) {
  FreeSlot? before;
  for (final s in slots) {
    final start = DateTime.tryParse(s.start)?.toLocal();
    if (start == null) continue;
    if (!start.isBefore(at)) return s;
    before = s;
  }
  return before;
}
