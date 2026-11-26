// 2611 §9: the pure geometry of the iOS-style calendar — the month grid
// (Sunday first), overlapping events side by side, drag snapping, working
// hours, blocked dates, month marks and the long-press slot choice.

import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/screens/calendar/calendar_api.dart';
import 'package:invoice/screens/calendar/calendar_layout.dart';
import 'package:invoice/screens/calendar/calendar_screen.dart';

BusyBlock _busy(int h1, int m1, int h2, int m2, {int day = 25}) =>
    BusyBlock(DateTime(2026, 11, day, h1, m1), DateTime(2026, 11, day, h2, m2));

AgendaItem _item(int h1, int m1, int h2, int m2, {int day = 25}) =>
    AgendaItem.busyBlock(_busy(h1, m1, h2, m2, day: day));

Booking _booking(String id, DateTime start, {String status = 'CONFIRMED'}) =>
    Booking(
      id: id,
      startsAt: start,
      endsAt: start.add(const Duration(minutes: 30)),
      status: status,
      clientName: 'x',
      clientPhone: '',
      clientEmail: '',
      sequence: 0,
      createdAt: start,
    );

void main() {
  final day = DateTime(2026, 11, 25);

  group('month grid', () {
    test('November 2026 starts on Sunday: no blanks, 5 rows', () {
      final nov = DateTime(2026, 11);
      expect(leadingBlanks(nov), 0);
      expect(daysInMonth(nov), 30);
      expect(weekRows(nov), 5);
    });

    test('a month starting Saturday needs 6 rows', () {
      final aug = DateTime(2026, 8); // Sat 1.8.2026
      expect(leadingBlanks(aug), 6);
      expect(weekRows(aug), 6);
    });

    test('February 2026 fits exactly 4 rows', () {
      final feb = DateTime(2026, 2); // Sun 1.2.2026, 28 days
      expect(weekRows(feb), 4);
    });

    test('month arithmetic and week start', () {
      expect(addMonths(DateTime(2026, 11), 2), DateTime(2027, 1));
      expect(addMonths(DateTime(2026, 1), -1), DateTime(2025, 12));
      expect(monthsBetween(DateTime(2025, 11), DateTime(2026, 2)), 3);
      expect(weekStart(DateTime(2026, 11, 25)), DateTime(2026, 11, 22));
      expect(weekStart(DateTime(2026, 11, 22)), DateTime(2026, 11, 22));
    });
  });

  group('layoutDay (overlapping events)', () {
    test('separate events take the full width', () {
      final out = layoutDay([_item(9, 0, 10, 0), _item(10, 0, 11, 0)], day);
      expect(out.map((e) => e.columns), [1, 1]);
      expect(out.map((e) => e.column), [0, 0]);
      expect(out.first.startMinute, 540);
      expect(out.first.endMinute, 600);
    });

    test('two overlapping events split the width', () {
      final out = layoutDay([_item(9, 0, 10, 0), _item(9, 30, 10, 30)], day);
      expect(out.map((e) => (e.column, e.columns)), [(0, 2), (1, 2)]);
    });

    test('a chain of overlaps shares one cluster; a freed column is reused', () {
      // A 9–11, B 9:30–10, C 10:15–10:45 → B ends before C: C reuses column 1.
      final out = layoutDay([
        _item(9, 0, 11, 0),
        _item(9, 30, 10, 0),
        _item(10, 15, 10, 45),
      ], day);
      expect(out.map((e) => (e.startMinute, e.column, e.columns)), [
        (540, 0, 2),
        (570, 1, 2),
        (615, 1, 2),
      ]);
    });

    test(
      'three at once → three columns; a later event starts a new cluster',
      () {
        final out = layoutDay([
          _item(9, 0, 10, 0),
          _item(9, 0, 10, 0),
          _item(9, 15, 9, 45),
          _item(12, 0, 13, 0),
        ], day);
        expect(out.take(3).map((e) => e.columns).toSet(), {3});
        expect(out.take(3).map((e) => e.column).toSet(), {0, 1, 2});
        expect((out.last.column, out.last.columns), (0, 1));
      },
    );

    test('longer events go first when two start together', () {
      final out = layoutDay([_item(9, 0, 9, 30), _item(9, 0, 11, 0)], day);
      expect(out.first.endMinute, 660);
      expect(out.first.column, 0);
    });

    test(
      'events crossing midnight are clipped to the day; other days skipped',
      () {
        final out = layoutDay([
          AgendaItem.busyBlock(
            BusyBlock(DateTime(2026, 11, 24, 23), DateTime(2026, 11, 25, 1)),
          ),
          AgendaItem.busyBlock(
            BusyBlock(DateTime(2026, 11, 25, 23), DateTime(2026, 11, 26, 2)),
          ),
          _item(9, 0, 10, 0, day: 26),
        ], day);
        expect(out.map((e) => (e.startMinute, e.endMinute)), [
          (0, 60),
          (1380, 1440),
        ]);
      },
    );
  });

  test('drag snapping: 15-minute steps, both directions', () {
    expect(snappedMinutes(0), 0);
    expect(snappedMinutes(7), 0);
    expect(snappedMinutes(8), 15);
    expect(snappedMinutes(44), 45);
    expect(snappedMinutes(-23), -30);
    expect(snappedMinutes(120, pixelsPerMinute: 2), 60);
  });

  test('working minutes of the weekday; a closed day has none', () {
    const week = [
      DayHours(3, [
        TimeRangeHm('09:00', '13:00'),
        TimeRangeHm('14:00', '17:30'),
      ]),
      DayHours(6, []),
    ];
    expect(workingMinutes(week, day), [(540, 780), (840, 1050)]); // Wed
    expect(workingMinutes(week, DateTime(2026, 11, 28)), isEmpty); // Sat
    expect(workingMinutes(week, DateTime(2026, 11, 22)), isEmpty); // missing
  });

  test('blocked dates are inclusive ranges', () {
    const blocked = [BlockedRange('2026-11-24', '2026-11-26')];
    expect(isBlockedDay(blocked, DateTime(2026, 11, 24)), isTrue);
    expect(isBlockedDay(blocked, DateTime(2026, 11, 26, 18)), isTrue);
    expect(isBlockedDay(blocked, DateTime(2026, 11, 27)), isFalse);
  });

  test('month marks count confirmed and pending, never cancelled', () {
    final marks = marksByDay([
      _booking('a', DateTime(2026, 11, 25, 9)),
      _booking('b', DateTime(2026, 11, 25, 11)),
      _booking('c', DateTime(2026, 11, 25, 12), status: 'PENDING'),
      _booking('d', DateTime(2026, 11, 26, 9), status: 'CANCELLED'),
    ]);
    expect(marks[day]!.meetings, 2);
    expect(marks[day]!.pending, 1);
    expect(marks[DateTime(2026, 11, 26)], isNull);
  });

  test('long-press slot: the first free time at or after the hour, else the '
      'last one before it', () {
    FreeSlot s(int h, int m) {
      final at = DateTime(2026, 11, 25, h, m);
      return FreeSlot(
        start: at.toUtc().toIso8601String(),
        end: at.add(const Duration(minutes: 30)).toUtc().toIso8601String(),
        date: '2026-11-25',
        time: '$h:$m',
      );
    }

    final slots = [s(9, 0), s(9, 30), s(11, 0)];
    expect(slotNear(slots, DateTime(2026, 11, 25, 9, 30))!.time, '9:30');
    expect(slotNear(slots, DateTime(2026, 11, 25, 10))!.time, '11:0');
    expect(slotNear(slots, DateTime(2026, 11, 25, 15))!.time, '11:0');
    expect(slotNear(const [], DateTime(2026, 11, 25)), isNull);
  });

  test(
    'mergeAgendas: the sync window wins; extra months add their meetings',
    () {
      final base = CalendarAgenda(
        bookings: [_booking('a', DateTime(2026, 11, 25, 9))],
        busy: const [],
        enabled: true,
      );
      final extra = CalendarAgenda(
        bookings: [
          _booking('a', DateTime(2026, 11, 25, 15)),
          _booking('z', DateTime(2027, 3, 1, 9)),
        ],
        busy: [_busy(9, 0, 10, 0)],
        enabled: true,
      );
      final m = mergeAgendas(base, [extra]);
      expect(m.bookings.map((b) => b.id).toSet(), {'a', 'z'});
      expect(
        m.bookings.firstWhere((b) => b.id == 'a').startsAt,
        DateTime(2026, 11, 25, 9),
      );
      expect(m.busy, hasLength(1));
    },
  );
}
