// Calendar v2 (app side): a break per day + vacation dates + manual approval
// in the settings, pending requests on top of the agenda (approve / decline),
// block a client, the customer-page "קביעת פגישה" sheet (suggest times →
// invite, book for them, slot taken) and a switched-off calendar there.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/screens/calendar/calendar_api.dart';
import 'package:invoice/screens/calendar/calendar_screen.dart';
import 'package:invoice/screens/calendar/calendar_settings_screen.dart';
import 'package:invoice/screens/calendar/calendar_sync.dart';
import 'package:invoice/screens/calendar/customer_booking_sheet.dart';
import 'package:invoice/screens/document/sheets/s6_share.dart' show textSharer;
import 'package:invoice/screens/people/person_screen.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/system_notices.dart';
import 'package:invoice/ui/widgets/notch_notice.dart';
import 'package:invoice/util/labels/calendar_he.dart';

import '../business/e_harness.dart';
import '../fakes/fake_api.dart';
import 'calendar_test.dart'
    show FakeDevice, MemoryPrefs, agenda, booking, reveal, settingsJson;

CalendarSync _sync(FakeDevice device) =>
    CalendarSync(device: device, store: MemoryPrefs(), notice: (_) {});

/// Days 1..4 of December 2026, one free 10:00 slot each (old servers: no
/// days[]); [_daySlots] serves the v2 shape.
Map<String, dynamic> _slot(int i) {
  final start = DateTime.utc(2026, 12, 1 + i, 8);
  return {
    'start': start.toIso8601String(),
    'end': start.add(const Duration(minutes: 30)).toIso8601String(),
    'date': '2026-12-${(1 + i).toString().padLeft(2, '0')}',
    'time': '10:00',
  };
}

void freeSlots(FakeBackend b, {bool enabled = true, int count = 4}) =>
    b.json('GET', '/calendar/free-slots', {
      'enabled': enabled,
      'slots': enabled ? [for (var i = 0; i < count; i++) _slot(i)] : [],
    });

/// A slot on [date] at [hour]:[minute] (Israel = UTC+2 in December).
Map<String, dynamic> _at(String date, int hour, [int minute = 0]) {
  final d = DateTime.parse(date);
  final start = DateTime.utc(d.year, d.month, d.day, hour - 2, minute);
  return {
    'start': start.toIso8601String(),
    'end': start.add(const Duration(minutes: 30)).toIso8601String(),
    'date': date,
    'time':
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
  };
}

/// v2 server: days[] (12-01: 5 times, 12-02 closed → not listed, 12-03: 2),
/// ?date= → that whole day.
const _v2Days = {'2026-12-01': 5, '2026-12-03': 2};

void daySlots(FakeBackend b) => b.on('GET', '/calendar/free-slots', (r) {
  final date = r.query['date'];
  List<Map<String, dynamic>> day(String d) => [
    for (var i = 0; i < _v2Days[d]!; i++) _at(d, 9 + i),
  ];
  return FakeResponse(200, {
    'enabled': true,
    'slots': date == null
        ? day('2026-12-01')
        : _v2Days.containsKey(date)
        ? day(date)
        : <Object>[],
    'days': [
      for (final e in _v2Days.entries) {'date': e.key, 'count': e.value},
    ],
  });
});

/// A page with one button that opens the customer booking sheet.
Widget _opener({String? phone = '0521234567'}) => Scaffold(
  body: Builder(
    builder: (c) => Center(
      child: TextButton(
        key: const Key('open'),
        onPressed: () => showCustomerBookingSheet(
          c,
          customerId: 'c1',
          name: 'דנה כהן',
          phone: phone,
        ),
        child: const Text('open'),
      ),
    ),
  ),
);

void main() {
  late FakeBackend b;
  late FakeDevice device;

  setUp(() async {
    b = await eSetUp();
    device = FakeDevice();
    b.json('PUT', '/calendar/busy', {'stored': 0});
  });

  test('push: bookingPending opens the calendar like bookingNew', () {
    expect(systemNoticePresentation('bookingPending'), (
      'בקשה לפגישה ממתינה לאישור',
      NoticeMotion.calendar,
    ));
  });

  group('settings', () {
    testWidgets('a break makes two ranges; blocked dates and manual approval '
        'are sent with the save', (t) async {
      final s = settingsJson()
        ..['blockedDates'] = [
          {'from': '2026-12-20', 'to': '2026-12-24'},
          {'from': '2027-01-05', 'to': '2027-01-05'},
        ]
        ..['requireApproval'] = false;
      // Monday arrives with a break already (kept as is).
      (s['weeklyHours'] as List)[1] = {
        'day': 1,
        'ranges': [
          {'start': '08:00', 'end': '12:00'},
          {'start': '13:00', 'end': '18:00'},
        ],
      };
      b.json('GET', '/calendar/settings', {'settings': s});
      b.json('PUT', '/calendar/settings', {'settings': s});
      await pumpAs(
        t,
        b,
        Preset.owner,
        CalendarSettingsScreen(sync: _sync(device)),
      );
      // Sunday: "הוספת הפסקה" → 09:00–13:00 + 14:00–17:00.
      await t.tap(find.byKey(const Key('calendar-day-0-add-break')));
      await t.pump();
      expect(find.byKey(const Key('calendar-day-0-range-1')), findsOneWidget);
      expect(find.byKey(const Key('calendar-day-0-add-break')), findsNothing);
      // Monday's break removed → one range 08:00–18:00.
      await t.tap(find.byKey(const Key('calendar-day-1-remove-break-1')));
      await t.pump();
      expect(find.byKey(const Key('calendar-day-1-range-1')), findsNothing);

      await reveal(t, find.byKey(const Key('calendar-blocked-1')));
      expect(
        find.text('20.12.2026 – 24.12.2026', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('05.01.2027', skipOffstage: false), findsOneWidget);
      await t.tap(find.byKey(const Key('calendar-blocked-remove-1')));
      await t.pump();
      await reveal(t, find.byKey(const Key('calendar-require-approval')));
      await t.tap(find.byKey(const Key('calendar-require-approval')));
      await t.pump();
      await t.tap(find.byKey(const Key('calendar-save')));
      await settle(t);

      final body = b.last('PUT', '/calendar/settings')!.body;
      final hours = body['weeklyHours'] as List;
      expect(hours[0], {
        'day': 0,
        'ranges': [
          {'start': '09:00', 'end': '13:00'},
          {'start': '14:00', 'end': '17:00'},
        ],
      });
      expect(hours[1], {
        'day': 1,
        'ranges': [
          {'start': '08:00', 'end': '18:00'},
        ],
      });
      expect(hours[6], {'day': 6, 'ranges': <dynamic>[]});
      expect(body['blockedDates'], [
        {'from': '2026-12-20', 'to': '2026-12-24'},
      ]);
      expect(body['requireApproval'], isTrue);
    });

    test('break / range helpers', () {
      expect(
        withBreak(const TimeRangeHm('10:00', '11:00')),
        isNull,
        reason: 'an hour is too short for a break',
      );
      expect(
        validRanges(const [
          TimeRangeHm('09:00', '13:00'),
          TimeRangeHm('12:00', '17:00'),
        ]),
        isFalse,
      );
    });

    testWidgets('"לקוחות חסומים": the list and "ביטול חסימה"', (t) async {
      b.json('GET', '/calendar/settings', {'settings': settingsJson()});
      b.json('GET', '/calendar/blocked', {
        'contacts': [
          {
            'id': 'k1',
            'name': 'רון',
            'phone': '0521112222',
            'email': 'ron@example.test',
            'createdAt': '2026-11-20T10:00:00.000Z',
          },
        ],
      });
      b.json('DELETE', '/calendar/blocked/:id', {'status': 'ok'});
      await pumpAs(
        t,
        b,
        Preset.owner,
        CalendarSettingsScreen(sync: _sync(device)),
      );
      await reveal(t, find.byKey(const Key('calendar-blocked-clients')));
      await t.tap(find.byKey(const Key('calendar-blocked-clients')));
      await settle(t);
      expect(find.text('רון'), findsOneWidget);
      await t.tap(find.byKey(const Key('blocked-unblock-k1')));
      await settle(t);
      expect(b.last('DELETE', '/calendar/blocked/:id')!.params['id'], 'k1');
      expect(find.text('רון'), findsNothing);
      expect(find.text(CalendarHe.noBlockedClients), findsOneWidget);
    });
  });

  group('agenda', () {
    setUp(() {
      b.json('GET', '/calendar/settings', {'settings': settingsJson()});
    });

    testWidgets('pending requests on top: approve and decline call the '
        'server; a declined one shows like a cancelled one', (t) async {
      final at = DateTime.now().toUtc().add(const Duration(days: 2));
      final today = DateTime.now();
      final todayAt = DateTime(today.year, today.month, today.day, 10).toUtc();
      agenda(b, [
        booking('p1', start: at, status: 'PENDING', name: 'נועה'),
        booking(
          'p2',
          start: at.add(const Duration(hours: 1)),
          status: 'PENDING',
          name: 'יוסי',
        ),
        booking('d1', start: todayAt, status: 'DECLINED', name: 'גיל'),
      ], reminderMinutes: 0);
      b.json('POST', '/calendar/bookings/:id/approve', {
        'booking': booking('p1', start: at),
      });
      b.json('POST', '/calendar/bookings/:id/decline', {
        'booking': booking('p2', start: at, status: 'DECLINED'),
      });
      await pumpAs(t, b, Preset.owner, CalendarScreen(sync: _sync(device)));
      // The month view says how many wait; the pill opens the list.
      expect(find.byKey(const Key('calendar-pending-pill')), findsOneWidget);
      await t.tap(find.byKey(const Key('calendar-pending-pill')));
      await settle(t);

      expect(find.byKey(const Key('calendar-pending')), findsOneWidget);
      expect(find.byKey(const Key('booking-pending-p1')), findsOneWidget);

      await reveal(t, find.byKey(const Key('booking-approve-p1')));
      await t.tap(find.byKey(const Key('booking-approve-p1')));
      await settle(t);
      expect(b.calls('POST', '/calendar/bookings/:id/approve'), hasLength(1));
      expect(
        b.last('POST', '/calendar/bookings/:id/approve')!.params['id'],
        'p1',
      );

      await reveal(t, find.byKey(const Key('booking-decline-p2')));
      await t.tap(find.byKey(const Key('booking-decline-p2')));
      await settle(t);
      expect(b.calls('POST', '/calendar/bookings/:id/decline'), hasLength(1));
      expect(
        b.last('POST', '/calendar/bookings/:id/decline')!.params['id'],
        'p2',
      );

      await reveal(t, find.byKey(const Key('booking-cancelled-d1')));
      expect(find.text(CalendarHe.declinedLabel), findsOneWidget);
    });

    testWidgets('block the client: asks first (they are not told), then '
        'POST …/block', (t) async {
      final today = DateTime.now();
      final at = DateTime(today.year, today.month, today.day, 10).toUtc();
      agenda(b, [booking('b1', start: at)], reminderMinutes: 0);
      b.json('POST', '/calendar/bookings/:id/block', {
        'booking': booking('b1', start: at, status: 'CANCELLED'),
        'blocked': {'id': 'k1', 'name': 'דנה כהן'},
      });
      await pumpAs(
        t,
        b,
        Preset.owner,
        CalendarScreen(
          sync: _sync(device),
          initialMode: CalendarMode.day,
          clock: () => DateTime(today.year, today.month, today.day, 9),
        ),
      );
      await t.tap(find.byKey(const Key('calendar-block-b1')));
      await settle(t);
      await t.ensureVisible(find.byKey(const Key('booking-detail-block')));
      await t.tap(find.byKey(const Key('booking-detail-block')));
      await settle(t);
      expect(find.text(CalendarHe.blockTitle), findsOneWidget);
      expect(find.textContaining('לא יידע'), findsOneWidget);
      await t.tap(find.byKey(const Key('calendar-block-confirm')));
      await settle(t);
      expect(b.calls('POST', '/calendar/bookings/:id/block'), hasLength(1));
    });
  });

  group('customer page', () {
    testWidgets('suggest times: pick 2 → POST /calendar/invites with those '
        'starts, then WhatsApp to the customer', (t) async {
      final launcher = FakeLauncher()..install();
      addTearDown(FakeLauncher.uninstall);
      daySlots(b);
      b.json('POST', '/calendar/invites', {
        'link': 'https://invoice.tevel.space/book/i/tok',
        'whatsappText':
            'היי דנה, אפשר לבחור מועד: https://invoice.tevel.space/book/i/tok',
        'expiresAt': '2026-11-30T10:00:00.000Z',
      }, status: 201);
      await pumpAs(t, b, Preset.owner, _opener());
      await t.tap(find.byKey(const Key('open')));
      await settle(t);
      await t.tap(find.byKey(const Key('customer-slot-0')));
      await t.tap(find.byKey(const Key('customer-slot-2')));
      await t.pump();
      expect(find.byKey(const Key('customer-pick-1')), findsOneWidget);
      await t.tap(find.byKey(const Key('customer-book-primary')));
      await settle(t);
      expect(b.last('POST', '/calendar/invites')!.body, {
        'customerId': 'c1',
        'slots': [
          _at('2026-12-01', 9)['start'],
          _at('2026-12-01', 11)['start'],
        ],
      });
      final wa = launcher.last!;
      expect(wa.host, 'wa.me');
      expect(wa.path, '/972521234567');
      expect(wa.queryParameters['text'], contains('/book/i/tok'));
    });

    testWidgets('month calendar: the first bookable day is chosen and asked with '
        '?date=; a closed day is shown but cannot be chosen; another day '
        'loads its own times', (t) async {
      daySlots(b);
      await pumpAs(t, b, Preset.owner, _opener());
      await t.tap(find.byKey(const Key('open')));
      await settle(t);
      final dates = [
        for (final r in b.calls('GET', '/calendar/free-slots')) r.query['date'],
      ];
      expect(dates, [null, '2026-12-01']);
      expect(find.byKey(const Key('new-booking-day-2026-12-01')), findsOneWidget);
      // 12-02 (no free times) is in the month but cannot be chosen.
      final closed = find.byKey(const Key('new-booking-day-2026-12-02'));
      await t.ensureVisible(closed);
      expect(t.widget<GestureDetector>(closed).onTap, isNull);
      expect(find.byKey(const Key('customer-slot-4')), findsOneWidget);
      final later = find.byKey(const Key('new-booking-day-2026-12-03'));
      await t.ensureVisible(later);
      await t.tap(later);
      await settle(t);
      expect(
        b.last('GET', '/calendar/free-slots')!.query['date'],
        '2026-12-03',
      );
      expect(find.byKey(const Key('customer-slot-1')), findsOneWidget);
      expect(find.byKey(const Key('customer-slot-2')), findsNothing);
    });

    testWidgets('at most 3 suggested, also across days; "קישור ליומן" sends '
        'no slots and shares when there is no phone', (t) async {
      final shared = <String>[];
      final before = textSharer;
      textSharer = (x) async => shared.add(x);
      addTearDown(() => textSharer = before);
      daySlots(b);
      b.json('POST', '/calendar/invites', {
        'link': 'https://invoice.tevel.space/book/i/tok',
        'whatsappText': 'קישור: https://invoice.tevel.space/book/i/tok',
        'expiresAt': null,
      }, status: 201);
      await pumpAs(t, b, Preset.owner, _opener(phone: null));
      await t.tap(find.byKey(const Key('open')));
      await settle(t);
      await t.tap(find.byKey(const Key('customer-slot-0')));
      await t.tap(find.byKey(const Key('customer-slot-1')));
      await t.pump();
      final later = find.byKey(const Key('new-booking-day-2026-12-03'));
      await t.ensureVisible(later);
      await t.tap(later);
      await settle(t);
      await t.tap(find.byKey(const Key('customer-slot-0')));
      await t.pump();
      await t.tap(find.byKey(const Key('customer-slot-1')));
      await settle(t);
      expect(find.byKey(const Key('customer-pick-2')), findsOneWidget);
      expect(find.byKey(const Key('customer-pick-3')), findsNothing);
      expect(find.text(CalendarHe.maxThree), findsOneWidget);
      await t.tap(find.text(CalendarHe.modeLinkShort));
      await t.pump();
      expect(find.byKey(const Key('customer-book-days')), findsNothing);
      expect(find.text(CalendarHe.linkShortHint), findsOneWidget);
      await t.tap(find.byKey(const Key('customer-book-primary')));
      await settle(t);
      expect(b.last('POST', '/calendar/invites')!.body, {'customerId': 'c1'});
      expect(shared.single, contains('/book/i/tok'));
    });

    testWidgets('an older server (no days[]): days come from the slots', (
      t,
    ) async {
      freeSlots(b);
      await pumpAs(t, b, Preset.owner, _opener());
      await t.tap(find.byKey(const Key('open')));
      await settle(t);
      expect(b.calls('GET', '/calendar/free-slots'), hasLength(1));
      expect(find.byKey(const Key('new-booking-day-2026-12-01')), findsOneWidget);
      expect(find.byKey(const Key('customer-slot-0')), findsOneWidget);
    });

    testWidgets('book for them: note sent; SLOT_TAKEN reloads that day with a '
        'message', (t) async {
      daySlots(b);
      b.error('POST', '/calendar/bookings', 409, 'SLOT_TAKEN');
      await pumpAs(t, b, Preset.owner, _opener());
      await t.tap(find.byKey(const Key('open')));
      await settle(t);
      await t.tap(find.text(CalendarHe.modeBook));
      await t.pump();
      await t.tap(find.byKey(const Key('customer-slot-1')));
      await t.pump();
      await t.enterText(
        find.byKey(const Key('customer-book-notes')),
        'להביא את התוכניות',
      );
      await t.ensureVisible(find.byKey(const Key('customer-book-primary')));
      await t.tap(find.byKey(const Key('customer-book-primary')));
      await settle(t);
      await t.tap(find.byKey(const Key('customer-book-confirm')));
      await settle(t);
      expect(b.last('POST', '/calendar/bookings')!.body, {
        'customerId': 'c1',
        'start': _at('2026-12-01', 10)['start'],
        'notes': 'להביא את התוכניות',
      });
      expect(b.calls('GET', '/calendar/free-slots'), hasLength(3));
      expect(
        b.last('GET', '/calendar/free-slots')!.query['date'],
        '2026-12-01',
      );
      expect(find.byKey(const Key('customer-book-notice')), findsOneWidget);
    });

    testWidgets('book for them without an e-mail: after booking, offers the '
        'details on WhatsApp', (t) async {
      final launcher = FakeLauncher()..install();
      addTearDown(FakeLauncher.uninstall);
      daySlots(b);
      b.json('POST', '/calendar/bookings', {
        'booking': {
          'id': 'bk1',
          'startsAt': _at('2026-12-01', 9)['start'],
          'endsAt': _at('2026-12-01', 9)['end'],
          'status': 'CONFIRMED',
          'createdAt': '2026-11-23T10:00:00Z',
        },
      }, status: 201);
      await pumpAs(t, b, Preset.owner, _opener());
      await t.tap(find.byKey(const Key('open')));
      await settle(t);
      await t.tap(find.text(CalendarHe.modeBook));
      await t.pump();
      expect(find.text(CalendarHe.confirmByPhone), findsOneWidget);
      await t.tap(find.byKey(const Key('customer-slot-0')));
      await t.ensureVisible(find.byKey(const Key('customer-book-primary')));
      await t.tap(find.byKey(const Key('customer-book-primary')));
      await settle(t);
      await t.tap(find.byKey(const Key('customer-book-confirm')));
      // The button spins while the WhatsApp offer is open: no settle.
      for (var i = 0; i < 10; i++) {
        await t.runAsync(() => Future<void>.delayed(Duration.zero));
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text(CalendarHe.offerWhatsappTitle), findsOneWidget);
      await t.tap(find.byKey(const Key('customer-book-whatsapp')));
      await settle(t);
      expect(launcher.last!.host, 'wa.me');
      expect(launcher.last!.path, '/972521234567');
    });

    testWidgets('free-slots enabled=false: default hours, then "הפעלה" '
        'continues in the sheet', (t) async {
      freeSlots(b, enabled: false);
      b
        ..json('GET', '/calendar/settings', {'settings': settingsJson()})
        ..json('PUT', '/calendar/settings', {'settings': settingsJson()});
      await pumpAs(t, b, Preset.owner, _opener());
      await t.tap(find.byKey(const Key('open')));
      await settle(t);
      expect(find.byKey(const Key('customer-book-disabled')), findsOneWidget);
      expect(find.byKey(const Key('customer-book-hours')), findsOneWidget);
      expect(find.text(CalendarHe.sendInvite), findsNothing);
      daySlots(b);
      await t.tap(find.byKey(const Key('customer-book-primary')));
      await settle(t);
      expect(b.last('PUT', '/calendar/settings')!.body, {'enabled': true});
      expect(find.byKey(const Key('customer-book-disabled')), findsNothing);
      expect(find.byKey(const Key('customer-slot-0')), findsOneWidget);
    });

    test('hoursSummary groups days with the same hours', () {
      expect(
        hoursSummary([
          for (var d = 0; d < 5; d++)
            DayHours(d, const [TimeRangeHm('09:00', '17:00')]),
          const DayHours(5, [TimeRangeHm('09:00', '13:00')]),
          const DayHours(6, []),
        ]),
        'א׳–ה׳ \u206609:00–17:00\u2069 · ו׳ \u206609:00–13:00\u2069',
      );
    });

    test('dayStrip fills the closed days between bookable ones', () {
      final strip = dayStrip(const [
        FreeDay('2026-12-03', 2),
        FreeDay('2026-12-01', 5),
      ]);
      expect(
        [for (final d in strip) '${d.date}:${d.count}'],
        ['2026-12-01:5', '2026-12-02:0', '2026-12-03:2'],
      );
    });

    testWidgets('"קביעת פגישה" on the customer card: owner yes, employee no', (
      t,
    ) async {
      installPeopleFakes(
        b,
        customers: [customerJson('c1', 'דנה', phone: '050-1234567')],
      );
      await pumpAs(t, b, Preset.owner, const PersonScreen(id: 'c1'));
      expect(find.byKey(const Key('person-action-book')), findsOneWidget);
      await pumpAs(t, b, Preset.employee, const PersonScreen(id: 'c1'));
      expect(find.byKey(const Key('person-action-book')), findsNothing);
    });
  });
}
