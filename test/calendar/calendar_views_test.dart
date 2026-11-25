// 2611 §9 — the iOS-style calendar, one widget test per view: month (today
// circle, dots, blocked days, tap → day), day (blocks by kind, working
// hours, now line, swipe / strip, long-press → new meeting), list (requests
// first), the details sheet (customer row, actions), "פגישה חדשה" (customer
// first, inline date + time, POST), and drag-to-move ("לעדכן את הלקוח?").

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart' show Customer;
import 'package:invoice/screens/calendar/booking_detail_sheet.dart';
import 'package:invoice/screens/calendar/calendar_api.dart';
import 'package:invoice/screens/calendar/calendar_day_view.dart';
import 'package:invoice/screens/calendar/calendar_screen.dart';
import 'package:invoice/screens/calendar/calendar_sync.dart';
import 'package:invoice/screens/calendar/new_booking_sheet.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/util/labels/calendar_he.dart';

import '../business/e_harness.dart';
import '../fakes/fake_api.dart';
import 'calendar_test.dart'
    show FakeDevice, MemoryPrefs, agenda, booking, settingsJson;

/// Wednesday 25.11.2026 09:00 on the phone.
final wed = DateTime(2026, 11, 25, 9);
DateTime clock() => wed;

DateTime at(int day, int hour, [int minute = 0]) =>
    DateTime(2026, 11, day, hour, minute).toUtc();

Map<String, dynamic> _slot(String date, int hour, [int minute = 0]) {
  final d = DateTime.parse(date);
  final start = DateTime(d.year, d.month, d.day, hour, minute);
  return {
    'start': start.toUtc().toIso8601String(),
    'end': start.add(const Duration(minutes: 30)).toUtc().toIso8601String(),
    'date': date,
    'time':
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
  };
}

void freeDays(FakeBackend b) => b.on('GET', '/calendar/free-slots', (r) {
  final date = r.query['date'] ?? '2026-11-26';
  return FakeResponse(200, {
    'enabled': true,
    'slots': [
      for (final h in [10, 11, 14]) _slot(date, h),
    ],
    'days': [
      {'date': '2026-11-26', 'count': 3},
      {'date': '2026-11-30', 'count': 3},
    ],
  });
});

void main() {
  late FakeBackend b;

  setUp(() async {
    b = await eSetUp();
    b.json('GET', '/calendar/settings', {
      'settings': {
        ...settingsJson(),
        'blockedDates': [
          {'from': '2026-11-29', 'to': '2026-11-29'},
        ],
      },
    });
    b.json('PUT', '/calendar/busy', {'stored': 0});
  });

  Future<void> pump(WidgetTester t, {CalendarMode? mode}) => pumpAs(
    t,
    b,
    Preset.owner,
    CalendarScreen(
      sync: CalendarSync(
        device: FakeDevice(),
        store: MemoryPrefs(),
        notice: (_) {},
      ),
      initialMode: mode,
      clock: clock,
    ),
  );

  group('month', () {
    testWidgets('today in the filled circle, a dot under meeting days, a '
        'blocked date shaded; a tap zooms into that day and "נובמבר" goes '
        'back', (t) async {
      agenda(b, [
        booking('b1', start: at(26, 10)),
        booking('p1', start: at(27, 11), status: 'PENDING'),
      ], reminderMinutes: 0);
      await pump(t);
      expect(find.byKey(const Key('calendar-today-circle')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('calendar-today-circle')),
          matching: find.text('25'),
        ),
        findsOneWidget,
      );
      expect(find.text('נובמבר'), findsWidgets);
      expect(find.byKey(const Key('calendar-pending-pill')), findsOneWidget);
      // Blocked 29.11: a grey cell.
      final blocked = t.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byKey(const Key('calendar-day-2026-11-29')),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((blocked.decoration as BoxDecoration).color, isNotNull);
      final plain = t.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byKey(const Key('calendar-day-2026-11-28')),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((plain.decoration as BoxDecoration).color, isNull);

      await t.tap(find.byKey(const Key('calendar-day-2026-11-26')));
      await settle(t);
      expect(
        find.text(CalendarHe.longDay(DateTime(2026, 11, 26))),
        findsOneWidget,
      );
      expect(find.byKey(const Key('calendar-block-b1')), findsOneWidget);
      await t.tap(find.byKey(const Key('calendar-back-month')));
      await settle(t);
      expect(find.byKey(const Key('calendar-month-list')), findsOneWidget);
    });
  });

  group('day', () {
    testWidgets('confirmed, pending (dashed) and busy blocks; working hours '
        'white; the now line on today; strip tap and swipe change the day', (
      t,
    ) async {
      agenda(
        b,
        [
          booking('b1', start: at(25, 10), name: 'נועה'),
          booking('p1', start: at(25, 10, 15), status: 'PENDING', name: 'גיל'),
          booking('x1', start: at(25, 13), status: 'CANCELLED', name: 'בוטל'),
        ],
        busy: [
          {
            'start': at(25, 12).toIso8601String(),
            'end': at(25, 13).toIso8601String(),
            'mine': true,
          },
        ],
        reminderMinutes: 0,
      );
      await pump(t, mode: CalendarMode.day);
      expect(find.byKey(const Key('calendar-block-b1')), findsOneWidget);
      expect(find.byKey(const Key('calendar-block-p1')), findsOneWidget);
      // A cancelled meeting is not on the timeline.
      expect(find.byKey(const Key('calendar-block-x1')), findsNothing);
      expect(find.text(CalendarHe.busyBlock), findsOneWidget);
      // b1 and p1 overlap: half width each.
      final w1 = t.getSize(find.byKey(const Key('calendar-block-b1'))).width;
      final w2 = t.getSize(find.byKey(const Key('calendar-block-p1'))).width;
      expect((w1 - w2).abs(), lessThan(1));
      final busyW = t
          .getSize(find.byKey(const Key('calendar-block-busy-720-0')))
          .width;
      expect(busyW, greaterThan(w1 * 1.8));
      // Pending = a dashed outline.
      expect(
        find.descendant(
          of: find.byKey(const Key('calendar-block-p1')),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.foregroundPainter is DashedOutline,
          ),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('calendar-working-540')), findsOneWidget);
      expect(find.byKey(const Key('calendar-now-line')), findsOneWidget);

      await t.tap(find.byKey(const Key('calendar-strip-2026-11-27')));
      await settle(t);
      expect(
        find.text(CalendarHe.longDay(DateTime(2026, 11, 27))),
        findsOneWidget,
      );
      expect(find.byKey(const Key('calendar-now-line')), findsNothing);
      // In Hebrew the next day comes from the left: drag right → forward.
      await t.drag(
        find.byKey(const Key('calendar-day-pages')),
        const Offset(300, 0),
      );
      await settle(t);
      expect(
        find.text(CalendarHe.longDay(DateTime(2026, 11, 28))),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('calendar-today')));
      await settle(t);
      expect(
        find.text(CalendarHe.longDay(DateTime(2026, 11, 25))),
        findsOneWidget,
      );
    });

    testWidgets('long-press on an empty hour opens "פגישה חדשה" at that '
        'time', (t) async {
      agenda(b, [], reminderMinutes: 0);
      freeDays(b);
      await pump(t, mode: CalendarMode.day);
      await t.tap(find.byKey(const Key('calendar-strip-2026-11-26')));
      await settle(t);
      // The timeline opens at 08:30 (half an hour before the working day):
      // 11:00 is 2.5 hours (150 px) below the top of the visible timeline.
      final area = find.byKey(const Key('calendar-timeline-2026-11-26'));
      final top = t.getTopLeft(area);
      await t.longPressAt(top + const Offset(200, 150 + 5));
      await settle(t);
      expect(find.byKey(const Key('new-booking')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('new-booking-time')),
          matching: find.text('11:00'),
        ),
        findsOneWidget,
      );
    });
  });

  group('list', () {
    testWidgets('requests waiting for approval come first, then the days', (
      t,
    ) async {
      agenda(b, [
        booking('b1', start: at(25, 11), name: 'היום'),
        booking('p1', start: at(28, 10), status: 'PENDING', name: 'ממתין'),
      ], reminderMinutes: 0);
      await pump(t, mode: CalendarMode.list);
      final pendingY = t
          .getTopLeft(find.byKey(const Key('calendar-pending')))
          .dy;
      final dayY = t
          .getTopLeft(find.byKey(const Key('calendar-list-day-2026-11-25')))
          .dy;
      expect(pendingY, lessThan(dayY));
      expect(find.byKey(const Key('booking-approve-p1')), findsOneWidget);
      expect(find.byKey(const Key('calendar-sync-line')), findsOneWidget);
      // The list toggle goes back to the month.
      await t.tap(find.byKey(const Key('calendar-list-toggle')));
      await settle(t);
      expect(find.byKey(const Key('calendar-month-list')), findsOneWidget);
    });
  });

  group('details sheet', () {
    BookingAction? result;

    Future<void> open(WidgetTester t, Booking booking) async {
      result = null;
      await pumpAs(
        t,
        b,
        Preset.owner,
        Scaffold(
          body: Builder(
            builder: (c) => Center(
              child: TextButton(
                key: const Key('open'),
                onPressed: () async => result = await showBookingDetailSheet(
                  c,
                  booking,
                  canOpenCustomer: true,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.byKey(const Key('open')));
      await settle(t);
    }

    Booking linked({String status = 'CONFIRMED', String? customerId = 'c1'}) =>
        Booking.fromJson({
          ...booking('b1', start: at(26, 10), status: status),
          'customerId': customerId,
        });

    testWidgets('customer row → the customer page; cancel in red at the '
        'bottom', (t) async {
      await open(t, linked());
      expect(find.byKey(const Key('booking-detail-status')), findsOneWidget);
      final cancelY = t
          .getTopLeft(find.byKey(const Key('booking-detail-cancel')))
          .dy;
      final blockY = t
          .getTopLeft(find.byKey(const Key('booking-detail-block')))
          .dy;
      expect(cancelY, greaterThan(blockY));
      await t.tap(find.byKey(const Key('booking-detail-customer')));
      await settle(t);
      expect(find.byKey(const Key('booking-detail')), findsNothing);
      expect(result, BookingAction.openCustomer);
    });

    testWidgets('a request: approve / decline, no cancel row; a meeting from '
        'the open link has no customer page', (t) async {
      await open(t, linked(status: 'PENDING', customerId: null));
      expect(find.byKey(const Key('booking-detail-approve')), findsOneWidget);
      expect(find.byKey(const Key('booking-detail-decline')), findsOneWidget);
      expect(find.byKey(const Key('booking-detail-cancel')), findsNothing);
      expect(find.text(CalendarHe.fromLink), findsOneWidget);
      await t.tap(find.byKey(const Key('booking-detail-customer')));
      await settle(t);
      // Not linked: the tap does nothing.
      expect(find.byKey(const Key('booking-detail')), findsOneWidget);
    });

    testWidgets('approve from the sheet calls the server', (t) async {
      agenda(b, [
        booking('p1', start: at(26, 10), status: 'PENDING'),
      ], reminderMinutes: 0);
      b.json('POST', '/calendar/bookings/:id/approve', {
        'booking': booking('p1', start: at(26, 10)),
      });
      await pump(t, mode: CalendarMode.list);
      await t.tap(find.byKey(const Key('calendar-row-p1')));
      await settle(t);
      await t.tap(find.byKey(const Key('booking-detail-approve')));
      await settle(t);
      expect(
        b.last('POST', '/calendar/bookings/:id/approve')!.params['id'],
        'p1',
      );
    });
  });

  group('new meeting', () {
    testWidgets('"+": customer first, the first free day preselected, the '
        'time picked inline, "הוספה" books it', (t) async {
      agenda(b, [], reminderMinutes: 0);
      freeDays(b);
      b.json('POST', '/calendar/bookings', {
        'booking': booking('n1', start: at(26, 11)),
      });
      pickCalendarCustomer = (_) async =>
          const Customer(id: 'c9', name: 'רינה לוי', email: 'r@example.test');
      addTearDown(() => pickCalendarCustomer = (_) async => null);
      await pump(t);
      await t.tap(find.byKey(const Key('calendar-add')));
      await settle(t);
      final add = t.widget<TextButton>(
        find.byKey(const Key('new-booking-add')),
      );
      expect(add.onPressed, isNull);
      expect(
        find.descendant(
          of: find.byKey(const Key('new-booking-date')),
          matching: find.text(CalendarHe.longDay(DateTime(2026, 11, 26))),
        ),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('new-booking-customer')));
      await settle(t);
      expect(find.text('רינה לוי'), findsOneWidget);
      // The date picker opens in place: bookable days only.
      await t.tap(find.byKey(const Key('new-booking-date')));
      await settle(t);
      expect(find.byKey(const Key('new-booking-month')), findsOneWidget);
      await t.tap(find.byKey(const Key('new-booking-day-2026-11-30')));
      await settle(t);
      expect(
        b.last('GET', '/calendar/free-slots')!.query['date'],
        '2026-11-30',
      );
      // Choosing a day opens the times.
      await t.tap(find.byKey(const Key('new-booking-slot-1')));
      await settle(t);
      await t.enterText(find.byKey(const Key('new-booking-notes')), 'מדידה');
      await t.tap(find.byKey(const Key('new-booking-add')));
      await settle(t);
      final post = b.last('POST', '/calendar/bookings')!;
      expect(post.body['customerId'], 'c9');
      expect(post.body['start'], _slot('2026-11-30', 11)['start']);
      expect(post.body['notes'], 'מדידה');
      expect(find.byKey(const Key('new-booking')), findsNothing);
    });

    testWidgets('SLOT_TAKEN keeps the sheet open with the message', (t) async {
      agenda(b, [], reminderMinutes: 0);
      freeDays(b);
      b.on(
        'POST',
        '/calendar/bookings',
        (_) => FakeResponse(409, {'error': 'SLOT_TAKEN', 'message': 'x'}),
      );
      pickCalendarCustomer = (_) async =>
          const Customer(id: 'c9', name: 'רינה לוי', phone: '0521111111');
      addTearDown(() => pickCalendarCustomer = (_) async => null);
      await pump(t);
      await t.tap(find.byKey(const Key('calendar-add')));
      await settle(t);
      await t.tap(find.byKey(const Key('new-booking-customer')));
      await settle(t);
      await t.tap(find.byKey(const Key('new-booking-add')));
      await settle(t);
      expect(find.byKey(const Key('new-booking-error')), findsOneWidget);
      expect(find.text(CalendarHe.slotTaken), findsOneWidget);
    });
  });

  group('drag to move', () {
    Future<void> drag(WidgetTester t, double dy) async {
      final g = await t.startGesture(
        t.getCenter(find.byKey(const Key('calendar-block-b1'))),
      );
      await t.pump(const Duration(milliseconds: 700));
      for (var i = 0; i < 6; i++) {
        await g.moveBy(Offset(0, dy / 6));
        await t.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await settle(t);
    }

    Future<void> open(WidgetTester t) async {
      agenda(b, [
        booking('b1', start: at(26, 10), minutes: 60),
      ], reminderMinutes: 0);
      b.json('POST', '/calendar/bookings/:id/move', {
        'booking': booking('b1', start: at(26, 11), minutes: 60),
      });
      await pump(t, mode: CalendarMode.day);
      await t.tap(find.byKey(const Key('calendar-strip-2026-11-26')));
      await settle(t);
    }

    testWidgets('an hour down → "לעדכן את הלקוח?" → yes: moved with notify', (
      t,
    ) async {
      await open(t);
      await drag(t, 62);
      expect(find.text(CalendarHe.moveTitle), findsOneWidget);
      await t.tap(find.byKey(const Key('calendar-move-notify')));
      await settle(t);
      final call = b.last('POST', '/calendar/bookings/:id/move')!;
      expect(call.params['id'], 'b1');
      expect(call.body['start'], at(26, 11).toIso8601String());
      expect(call.body['notify'], true);
    });

    testWidgets('"להעביר בלי לעדכן" → notify false; "ביטול" → nothing sent', (
      t,
    ) async {
      await open(t);
      await drag(t, -29);
      await t.tap(find.byKey(const Key('calendar-move-quiet')));
      await settle(t);
      final call = b.last('POST', '/calendar/bookings/:id/move')!;
      expect(call.body['start'], at(26, 9, 30).toIso8601String());
      expect(call.body['notify'], false);
      await drag(t, 45);
      await t.tap(find.byKey(const Key('calendar-move-back')));
      await settle(t);
      expect(b.calls('POST', '/calendar/bookings/:id/move'), hasLength(1));
    });

    testWidgets('a small wiggle (under 8 minutes) moves nothing', (t) async {
      await open(t);
      await drag(t, 5);
      expect(find.text(CalendarHe.moveTitle), findsNothing);
    });
  });
}
