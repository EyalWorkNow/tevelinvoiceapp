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

      expect(find.byKey(const Key('calendar-settings')), findsOneWidget);
      expect(find.text(CalendarHe.hoursButton), findsOneWidget);
      expect(find.byKey(const Key('calendar-pending')), findsOneWidget);
      expect(find.byKey(const Key('booking-pending-p1')), findsOneWidget);
      expect(find.byKey(const Key('booking-cancel-p1')), findsNothing);

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
      await pumpAs(t, b, Preset.owner, CalendarScreen(sync: _sync(device)));
      await reveal(t, find.byKey(const Key('booking-block-b1')));
      await t.tap(find.byKey(const Key('booking-block-b1')));
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
      freeSlots(b);
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
      await t.tap(find.byKey(const Key('customer-book-primary')));
      await settle(t);
      expect(b.last('POST', '/calendar/invites')!.body, {
        'customerId': 'c1',
        'slots': [_slot(0)['start'], _slot(2)['start']],
      });
      final wa = launcher.last!;
      expect(wa.host, 'wa.me');
      expect(wa.path, '/972521234567');
      expect(wa.queryParameters['text'], contains('/book/i/tok'));
    });

    testWidgets('at most 3 suggested; "שליחת קישור ליומן" sends no slots and '
        'shares when there is no phone', (t) async {
      final shared = <String>[];
      final before = textSharer;
      textSharer = (x) async => shared.add(x);
      addTearDown(() => textSharer = before);
      freeSlots(b);
      b.json('POST', '/calendar/invites', {
        'link': 'https://invoice.tevel.space/book/i/tok',
        'whatsappText': 'קישור: https://invoice.tevel.space/book/i/tok',
        'expiresAt': null,
      }, status: 201);
      await pumpAs(t, b, Preset.owner, _opener(phone: null));
      await t.tap(find.byKey(const Key('open')));
      await settle(t);
      for (var i = 0; i < 4; i++) {
        await t.tap(find.byKey(Key('customer-slot-$i')));
        await t.pump();
      }
      final chips = t.widgetList<FilterChip>(find.byType(FilterChip));
      expect(chips.where((c) => c.selected), hasLength(3));
      await t.tap(find.text(CalendarHe.modeLink));
      await t.pump();
      await t.tap(find.byKey(const Key('customer-book-primary')));
      await settle(t);
      expect(b.last('POST', '/calendar/invites')!.body, {'customerId': 'c1'});
      expect(shared.single, contains('/book/i/tok'));
    });

    testWidgets('book for them: confirm → POST /calendar/bookings; SLOT_TAKEN '
        'reloads the free times with a message', (t) async {
      freeSlots(b);
      b.error('POST', '/calendar/bookings', 409, 'SLOT_TAKEN');
      await pumpAs(t, b, Preset.owner, _opener());
      await t.tap(find.byKey(const Key('open')));
      await settle(t);
      await t.tap(find.text(CalendarHe.modeBook));
      await t.pump();
      await t.tap(find.byKey(const Key('customer-slot-1')));
      await t.pump();
      await t.tap(find.byKey(const Key('customer-book-primary')));
      await settle(t);
      await t.tap(find.byKey(const Key('customer-book-confirm')));
      await settle(t);
      expect(b.last('POST', '/calendar/bookings')!.body, {
        'customerId': 'c1',
        'start': _slot(1)['start'],
      });
      expect(b.calls('GET', '/calendar/free-slots'), hasLength(2));
      expect(find.byKey(const Key('customer-book-notice')), findsOneWidget);
    });

    testWidgets('free-slots enabled=false: explains and turns booking on', (
      t,
    ) async {
      freeSlots(b, enabled: false);
      b.json('PUT', '/calendar/settings', {'settings': settingsJson()});
      await pumpAs(t, b, Preset.owner, _opener());
      await t.tap(find.byKey(const Key('open')));
      await settle(t);
      expect(find.byKey(const Key('customer-book-disabled')), findsOneWidget);
      expect(find.text(CalendarHe.sendInvite), findsNothing);
      freeSlots(b);
      await t.tap(find.byKey(const Key('customer-book-primary')));
      await settle(t);
      expect(b.last('PUT', '/calendar/settings')!.body, {'enabled': true});
      expect(find.byKey(const Key('customer-book-disabled')), findsNothing);
      expect(find.byKey(const Key('customer-slot-0')), findsOneWidget);
    });

    testWidgets('"קביעת פגישה" on the customer card: owner yes, employee no', (
      t,
    ) async {
      installPeopleFakes(
        b,
        customers: [customerJson('c1', 'דנה', phone: '050-1234567')],
      );
      await pumpAs(t, b, Preset.owner, const PersonScreen(id: 'c1'));
      await reveal(t, find.byKey(const Key('person-book')));
      expect(find.byKey(const Key('person-book')), findsOneWidget);
      await pumpAs(t, b, Preset.employee, const PersonScreen(id: 'c1'));
      expect(find.byKey(const Key('person-book')), findsNothing);
    });
  });
}
