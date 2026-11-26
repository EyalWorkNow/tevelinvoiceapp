// 2611 V3 (spec §9) — the calendar screenshot scenario with MOCKED data
// (FakeBackend). Shared by integration_test/calendar_v3_shots_test.dart (the
// simulator, SHOT: markers) and test/calendar/calendar_render_shots_test.dart
// (rendered off-screen with the real SF Hebrew fonts, when no simulator
// can boot).
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart' show Customer;
import 'package:invoice/screens/calendar/calendar_screen.dart';
import 'package:invoice/screens/calendar/calendar_sync.dart';
import 'package:invoice/screens/calendar/new_booking_sheet.dart';
import 'package:invoice/state/caps.dart';

import '../business/e_harness.dart';
import '../fakes/fake_api.dart';
import 'calendar_test.dart' show FakeDevice, MemoryPrefs, booking, settingsJson;

late WidgetTester t;
late Future<void> Function(int ms) wait;

final today = () {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}();

DateTime at(int dayOffset, int hour, [int minute = 0]) => DateTime(
  today.year,
  today.month,
  today.day + dayOffset,
  hour,
  minute,
).toUtc();

String ymdOf(int offset) {
  final d = DateTime(today.year, today.month, today.day + offset);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// "now" for the shots: today 11:20 (the now line in the morning's middle).
DateTime clock() => DateTime(today.year, today.month, today.day, 11, 20);

FakeBackend backend() {
  final b = FakeBackend()..install();
  installBusinessFakes(b);
  b.json('GET', '/calendar/settings', {
    'settings': {
      ...settingsJson(),
      'requireApproval': true,
      'blockedDates': [
        {'from': ymdOf(8), 'to': ymdOf(10)},
      ],
    },
  });
  b.json('PUT', '/calendar/busy', {'stored': 0});
  Map<String, dynamic> linked(Map<String, dynamic> j, String id) => {
    ...j,
    'customerId': id,
  };
  b.json('GET', '/calendar/agenda', {
    'bookings': [
      linked(
        booking('b1', start: at(0, 9), minutes: 60, name: 'דניאל רוזן'),
        'c1',
      ),
      linked(
        booking(
          'b2',
          start: at(0, 10, 30),
          minutes: 45,
          name: 'מיכל לוי',
          notes: 'מדידה למטבח',
        ),
        'c2',
      ),
      booking(
        'p1',
        start: at(0, 10, 45),
        status: 'PENDING',
        name: 'יוסי אברהם',
        notes: 'ייעוץ ראשוני',
      ),
      linked(
        booking('b3', start: at(0, 14), minutes: 60, name: 'נועה כהן'),
        'c3',
      ),
      linked(booking('b4', start: at(1, 9, 30), name: 'אורי שמש'), 'c4'),
      booking('p2', start: at(2, 16), status: 'PENDING', name: 'רונית בר'),
      linked(booking('b5', start: at(3, 12), name: 'שירה גולן'), 'c5'),
      linked(booking('b6', start: at(6, 10), name: 'עמית דהן'), 'c6'),
      linked(booking('b7', start: at(13, 11), name: 'דניאל רוזן'), 'c1'),
      booking('x1', start: at(1, 15), status: 'CANCELLED', name: 'בוטלה'),
    ],
    'busy': [
      {
        'start': at(0, 12).toIso8601String(),
        'end': at(0, 13).toIso8601String(),
        'mine': true,
      },
      {
        'start': at(1, 11).toIso8601String(),
        'end': at(1, 12, 30).toIso8601String(),
        'mine': true,
      },
    ],
    'enabled': true,
    'busySyncedAt': null,
    'notifyNewBooking': true,
    'reminderMinutes': 0,
  });
  b.on('GET', '/calendar/free-slots', (r) {
    final date = r.query['date'] ?? ymdOf(1);
    final d = DateTime.parse(date);
    return FakeResponse(200, {
      'enabled': true,
      'slots': [
        for (final h in [9, 10, 13, 14, 15, 16])
          for (final m in [0, 30])
            if (!(h == 9 && m == 30))
              {
                'start': DateTime(
                  d.year,
                  d.month,
                  d.day,
                  h,
                  m,
                ).toUtc().toIso8601String(),
                'end': DateTime(
                  d.year,
                  d.month,
                  d.day,
                  h,
                  m + 30,
                ).toUtc().toIso8601String(),
                'date': date,
                'time':
                    '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}',
              },
      ],
      'days': [
        for (var i = 1; i < 21; i++)
          if (i % 7 != 5 && (i < 8 || i > 10)) {'date': ymdOf(i), 'count': 11},
      ],
    });
  });
  return b;
}

Future<void> open(
  CalendarMode mode, {
  Brightness brightness = Brightness.light,
}) async {
  final b = backend();
  await t.runAsync(() => signInAs(b, Preset.owner));
  await t.pumpWidget(const SizedBox());
  await wait(200);
  await t.pumpWidget(
    eApp(
      CalendarScreen(
        sync: CalendarSync(
          device: FakeDevice(),
          store: MemoryPrefs(),
          notice: (_) {},
        )..addListener(() {}),
        initialMode: mode,
        clock: clock,
      ),
      brightness: brightness,
    ),
  );
  await wait(2500);
}

Future<void> tap(Finder f, {int ms = 1200}) async {
  for (var i = 0; i < 20 && f.evaluate().isEmpty; i++) {
    await wait(150);
  }
  if (f.evaluate().isEmpty) {
    print('AUDIT: not found $f');
    return;
  }
  await t.tap(f.first, warnIfMissed: false);
  await wait(ms);
}

/// Runs every view and calls [shot] at each screen worth a picture.
Future<void> runCalendarShots(
  WidgetTester tester, {
  required Future<void> Function(String name) shot,
  required Future<void> Function(int ms) waitMs,
}) async {
  t = tester;
  wait = waitMs;
  pickCalendarCustomer = (_) async => const Customer(
    id: 'c1',
    name: 'דניאל רוזן',
    phone: '0521234567',
    email: 'daniel@example.test',
  );

  await open(CalendarMode.month);
  await shot('01-month');

  // Month → day (zoom), today.
  await tap(find.byKey(Key('calendar-day-${ymdOf(0)}')), ms: 1500);
  await shot('02-day-today');

  // Tomorrow: a busy block from the phone.
  await tap(find.byKey(Key('calendar-strip-${ymdOf(1)}')), ms: 1500);
  await shot('03-day-tomorrow');
  await tap(find.byKey(Key('calendar-strip-${ymdOf(0)}')), ms: 1500);

  // Details of a confirmed meeting and of a request.
  await tap(find.byKey(const Key('calendar-block-b2')), ms: 1500);
  await shot('04-detail-confirmed');
  await t.tapAt(const Offset(200, 80));
  await wait(900);
  await tap(find.byKey(const Key('calendar-block-p1')), ms: 1500);
  await shot('05-detail-pending');
  await t.tapAt(const Offset(200, 80));
  await wait(900);

  // Drag 14:00 → 15:00: "לעדכן את הלקוח?".
  final block = find.byKey(const Key('calendar-block-b3'));
  final g = await t.startGesture(t.getCenter(block));
  await wait(700);
  for (var i = 0; i < 10; i++) {
    await g.moveBy(const Offset(0, 6));
    await wait(40);
  }
  await wait(300);
  await shot('06-drag-lifted');
  await g.up();
  await wait(1200);
  await shot('07-move-confirm');
  await tap(find.byKey(const Key('calendar-move-back')));

  // New meeting from "+": customer, date picker open, then times.
  await tap(find.byKey(const Key('calendar-add')), ms: 1800);
  await tap(find.byKey(const Key('new-booking-customer')));
  await shot('08-new');
  await tap(find.byKey(const Key('new-booking-date')));
  await shot('09-new-date-picker');
  await tap(find.byKey(Key('new-booking-day-${ymdOf(3)}')), ms: 1500);
  await shot('10-new-time-picker');
  await t.tapAt(const Offset(200, 80));
  await wait(900);

  // List: requests first.
  await open(CalendarMode.list);
  await shot('11-list');

  // Dark.
  await open(CalendarMode.month, brightness: Brightness.dark);
  await shot('12-month-dark');
  await tap(find.byKey(Key('calendar-day-${ymdOf(0)}')), ms: 1500);
  await shot('13-day-dark');
}
