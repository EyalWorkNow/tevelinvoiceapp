// 0106 "יומן": the phone ↔ server sync (busy start/end only, bookings written
// into the phone calendar, moved/cancelled kept in step, new-booking notices,
// local reminders only without server push), the agenda screen, the share
// sheet, owner cancel, who sees the entry, and the notch / push wiring.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/calendar/calendar_api.dart';
import 'package:invoice/screens/calendar/calendar_screen.dart';
import 'package:invoice/screens/calendar/calendar_sync.dart';
import 'package:invoice/screens/calendar/device_calendar.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/system_notices.dart';
import 'package:invoice/ui/widgets/notch_notice.dart';
import 'package:invoice/util/labels/calendar_he.dart';

import '../business/e_harness.dart';
import '../fakes/fake_api.dart';

Caps capsOf(Preset p) => Caps.fromMe(Me.fromJson(meJson(p)));

class FakeDevice implements DeviceCalendarPort {
  CalendarAccess accessState = CalendarAccess.full;
  List<DeviceInterval> busyIntervals = [];
  final Map<String, Map<String, Object?>> events = {};
  final List<String> deleted = [];
  List<LocalReminder> reminders = [];
  int upserts = 0;
  int _next = 0;
  List<String>? lastBusyCalendars;

  @override
  bool get supported => true;
  @override
  set onChanged(VoidCallback? callback) {}
  @override
  Future<CalendarAccess> status() async => accessState;
  @override
  Future<CalendarAccess> requestAccess() async => accessState;
  @override
  Future<List<DeviceCalendarInfo>> calendars() async => const [
    DeviceCalendarInfo(
      id: 'home',
      title: 'בית',
      account: 'iCloud',
      color: '#FF0000',
      writable: true,
      isDefault: true,
    ),
    DeviceCalendarInfo(
      id: 'work',
      title: 'עבודה',
      account: 'Google',
      color: '#00FF00',
      writable: true,
      isDefault: false,
    ),
  ];
  @override
  Future<List<DeviceInterval>> busy(
    DateTime from,
    DateTime to,
    List<String> calendarIds,
  ) async {
    lastBusyCalendars = calendarIds;
    return busyIntervals;
  }

  @override
  Future<String?> upsertEvent({
    required String bookingId,
    required String? eventId,
    required String? calendarId,
    required DateTime start,
    required DateTime end,
    required String title,
    required String notes,
  }) async {
    upserts++;
    final id = eventId ?? 'ev-${_next++}';
    events[id] = {
      'bookingId': bookingId,
      'calendarId': calendarId,
      'start': start,
      'end': end,
      'title': title,
      'notes': notes,
    };
    return id;
  }

  @override
  Future<void> deleteEvent(String eventId) async {
    deleted.add(eventId);
    events.remove(eventId);
  }

  @override
  Future<int> scheduleReminders(List<LocalReminder> items) async {
    reminders = items;
    return items.length;
  }
}

class MemoryPrefs implements CalendarPrefsStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

final now = DateTime.utc(2026, 11, 17, 6); // Tue 08:00 Israel

Map<String, dynamic> booking(
  String id, {
  required DateTime start,
  int minutes = 30,
  String status = 'CONFIRMED',
  int sequence = 0,
  String name = 'דנה כהן',
  String? notes = 'ייעוץ משכנתא',
}) => {
  'id': id,
  'startsAt': start.toIso8601String(),
  'endsAt': start.add(Duration(minutes: minutes)).toIso8601String(),
  'status': status,
  'clientName': name,
  'clientPhone': '0521234567',
  'clientEmail': 'dana@example.test',
  'notes': notes,
  'sequence': sequence,
  'cancelledBy': status == 'CANCELLED' ? 'CLIENT' : null,
  'createdAt': now.toIso8601String(),
};

void agenda(
  FakeBackend b,
  List<Map<String, dynamic>> bookings, {
  List<Map<String, dynamic>> busy = const [],
  int reminderMinutes = 15,
  bool notifyNewBooking = true,
  bool enabled = true,
}) => b.json('GET', '/calendar/agenda', {
  'bookings': bookings,
  'busy': busy,
  'enabled': enabled,
  'busySyncedAt': null,
  'notifyNewBooking': notifyNewBooking,
  'reminderMinutes': reminderMinutes,
});

Map<String, dynamic> settingsJson({bool enabled = true}) => {
  'enabled': enabled,
  'slug': 'AbCdEfGhIjKlMnOpQrStUv',
  'bookingPath': '/book/AbCdEfGhIjKlMnOpQrStUv',
  'bookingUrl': 'https://invoice.tevel.space/book/AbCdEfGhIjKlMnOpQrStUv',
  'weeklyHours': [
    for (var d = 0; d < 7; d++)
      {
        'day': d,
        'ranges': d == 6
            ? []
            : [
                {'start': '09:00', 'end': '17:00'},
              ],
      },
  ],
  'slotMinutes': 30,
  'bufferMinutes': 0,
  'minNoticeMinutes': 120,
  'maxDaysAhead': 30,
  'meetingTitle': null,
  'notifyNewBooking': true,
  'reminderMinutes': 15,
  'busySyncedAt': null,
};

/// Scrolls the page's list until [target] is built and on screen.
Future<void> reveal(WidgetTester t, Finder target) async {
  await t.scrollUntilVisible(
    target,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await t.pumpAndSettle();
}

void main() {
  group('who sees it', () {
    test('owner and partner; not employee, viewer or accountant', () {
      expect(mayUseCalendar(capsOf(Preset.owner)), isTrue);
      expect(mayUseCalendar(capsOf(Preset.partner)), isTrue);
      expect(mayUseCalendar(capsOf(Preset.employee)), isFalse);
      expect(mayUseCalendar(capsOf(Preset.viewer)), isFalse);
      expect(mayUseCalendar(capsOf(Preset.accountantRep)), isFalse);
    });

    test('/calendar is a route that needs business settings', () {
      final route = AppRoute.parse('/calendar')!;
      expect(route.requiredCap, Cap.settingsBusiness);
      expect(route.allowedFor(capsOf(Preset.owner)), isTrue);
      expect(route.allowedFor(capsOf(Preset.employee)), isFalse);
    });

    test('push kinds map to the calendar notch animation', () {
      expect(systemNoticePresentation('bookingNew')?.$2, NoticeMotion.calendar);
      expect(systemNoticePresentation('bookingSoon')?.$1, 'הפגישה הבאה מתקרבת');
    });
  });

  group('sync', () {
    late FakeBackend b;
    late FakeDevice device;
    late MemoryPrefs prefs;
    late List<Booking> notices;
    late CalendarSync sync;

    setUp(() async {
      b = await eSetUp();
      device = FakeDevice();
      prefs = MemoryPrefs();
      notices = [];
      b.json('PUT', '/calendar/busy', {'stored': 1});
      b.json('GET', '/calendar/settings', {'settings': settingsJson()});
      sync = CalendarSync(
        device: device,
        store: prefs,
        clock: () => now,
        notice: notices.add,
      );
    });

    Future<void> signIn(WidgetTester t) => t.runAsync(
      () => signInAs(b, Preset.owner, businessType: 'OSEK_MURSHE'),
    );

    testWidgets('connect: reads every calendar, writes to the default one, '
        'uploads busy times as start/end only', (t) async {
      await signIn(t);
      device.busyIntervals = [
        DeviceInterval(
          DateTime.utc(2026, 11, 17, 8),
          DateTime.utc(2026, 11, 17, 9),
        ),
      ];
      agenda(b, []);
      await t.runAsync(sync.connect);
      expect(sync.prefs!.connected, isTrue);
      expect(sync.prefs!.read, ['home', 'work']);
      expect(sync.prefs!.write, 'home');
      expect(device.lastBusyCalendars, ['home', 'work']);
      final body = b.last('PUT', '/calendar/busy')!.body;
      expect(body['source'], matches(RegExp(r'^ios-[A-Za-z0-9]{20}$')));
      expect(body['blocks'], [
        {
          'start': '2026-11-17T08:00:00.000Z',
          'end': '2026-11-17T09:00:00.000Z',
        },
      ]);
      expect((body['blocks'] as List).single.keys, ['start', 'end']);
    });

    testWidgets('not connected: nothing is read from the phone', (t) async {
      await signIn(t);
      agenda(b, []);
      await t.runAsync(() => sync.sync(force: true));
      expect(b.calls('PUT', '/calendar/busy'), isEmpty);
      expect(device.lastBusyCalendars, isNull);
      expect(sync.agenda, isNotNull);
    });

    testWidgets('bookings are written into the phone calendar; a move updates '
        'the same event; a cancel removes it', (t) async {
      await signIn(t);
      final start = DateTime.utc(2026, 11, 18, 8);
      agenda(b, [booking('b1', start: start)]);
      await t.runAsync(sync.connect);
      expect(device.events, hasLength(1));
      final ev = device.events.values.single;
      expect(ev['bookingId'], 'b1');
      expect(ev['calendarId'], 'home');
      expect(ev['title'], CalendarHe.eventTitle('דנה כהן'));
      expect(ev['notes'] as String, contains('ייעוץ משכנתא'));
      // Same sequence → no rewrite.
      await t.runAsync(() => sync.sync(force: true));
      expect(device.upserts, 1);
      // Moved (sequence 1) → the same event id is updated.
      final moved = start.add(const Duration(hours: 2));
      agenda(b, [booking('b1', start: moved, sequence: 1)]);
      await t.runAsync(() => sync.sync(force: true));
      expect(device.events.keys, ['ev-0']);
      expect(device.events['ev-0']!['start'], moved);
      // Cancelled → removed from the phone.
      agenda(b, [
        booking('b1', start: moved, status: 'CANCELLED', sequence: 2),
      ]);
      await t.runAsync(() => sync.sync(force: true));
      expect(device.deleted, ['ev-0']);
      expect(device.events, isEmpty);
    });

    testWidgets('a new booking shows a notice once; the first sync only '
        'marks what exists as seen', (t) async {
      await signIn(t);
      agenda(b, [booking('old', start: DateTime.utc(2026, 11, 18, 8))]);
      await t.runAsync(() => sync.sync(force: true));
      expect(notices, isEmpty);
      agenda(b, [
        booking('old', start: DateTime.utc(2026, 11, 18, 8)),
        booking('new', start: DateTime.utc(2026, 11, 19, 8), name: 'רון'),
      ]);
      await t.runAsync(() => sync.sync(force: true));
      expect(notices.map((n) => n.id), ['new']);
      await t.runAsync(() => sync.sync(force: true));
      expect(notices, hasLength(1));
    });

    testWidgets('the owner turned "new booking" notices off: none', (t) async {
      await signIn(t);
      agenda(b, [], notifyNewBooking: false);
      await t.runAsync(() => sync.sync(force: true));
      agenda(b, [
        booking('new', start: DateTime.utc(2026, 11, 19, 8)),
      ], notifyNewBooking: false);
      await t.runAsync(() => sync.sync(force: true));
      expect(notices, isEmpty);
    });

    testWidgets('local reminders N minutes before each future meeting; none '
        'when the reminder is off', (t) async {
      await signIn(t);
      final start = DateTime.utc(2026, 11, 18, 8);
      agenda(b, [
        booking('b1', start: start),
        booking('gone', start: start, status: 'CANCELLED'),
      ], reminderMinutes: 15);
      await t.runAsync(() => sync.sync(force: true));
      expect(device.reminders, hasLength(1));
      expect(
        device.reminders.single.at,
        start.subtract(const Duration(minutes: 15)),
      );
      expect(device.reminders.single.title, CalendarHe.soon);
      agenda(b, [booking('b1', start: start)], reminderMinutes: 0);
      await t.runAsync(() => sync.sync(force: true));
      expect(device.reminders, isEmpty);
    });

    testWidgets('in-app reminder: once, when the meeting is within the '
        'reminder window', (t) async {
      final soon = <String>[];
      sync.soonNotice = (b) => soon.add(b.id);
      await signIn(t);
      final start = now.add(const Duration(minutes: 10));
      agenda(b, [booking('b1', start: start)], reminderMinutes: 15);
      await t.runAsync(() => sync.sync(force: true));
      expect(soon, ['b1']);
      await t.runAsync(() => sync.sync(force: true));
      expect(soon, ['b1']);
    });

    testWidgets('disconnect: busy times are deleted on the server', (t) async {
      await signIn(t);
      agenda(b, []);
      b.json('DELETE', '/calendar/busy', {'removed': 3});
      await t.runAsync(sync.connect);
      final source = sync.prefs!.source;
      await t.runAsync(sync.disconnect);
      expect(sync.prefs!.connected, isFalse);
      final call = b.last('DELETE', '/calendar/busy')!;
      expect(call.raw.url.queryParameters['source'], source);
    });

    testWidgets('an employee never syncs (no calendar calls)', (t) async {
      await t.runAsync(
        () => signInAs(b, Preset.employee, businessType: 'OSEK_MURSHE'),
      );
      agenda(b, []);
      await t.runAsync(() => sync.sync(force: true));
      expect(b.calls('GET', '/calendar/agenda'), isEmpty);
    });
  });

  group('agenda items', () {
    test('busy blocks that exactly cover a booking are not listed twice', () {
      final s = DateTime.utc(2026, 11, 18, 8);
      final a = CalendarAgenda.fromJson({
        'bookings': [booking('b1', start: s)],
        'busy': [
          {
            'start': s.toIso8601String(),
            'end': s.add(const Duration(minutes: 30)).toIso8601String(),
            'mine': true,
          },
          {
            'start': s.add(const Duration(hours: 2)).toIso8601String(),
            'end': s.add(const Duration(hours: 3)).toIso8601String(),
            'mine': true,
          },
        ],
        'enabled': true,
      });
      final items = agendaItems(a, s.toLocal(), 1);
      expect(items.map((i) => i.booking?.id ?? 'busy'), ['b1', 'busy']);
    });
  });

  group('screen', () {
    late FakeBackend b;
    late FakeDevice device;

    setUp(() async {
      b = await eSetUp();
      device = FakeDevice();
      b.json('GET', '/calendar/settings', {'settings': settingsJson()});
      b.json('PUT', '/calendar/busy', {'stored': 0});
    });

    Future<CalendarSync> pump(WidgetTester t) async {
      final sync = CalendarSync(
        device: device,
        store: MemoryPrefs(),
        notice: (_) {},
      );
      await pumpAs(t, b, Preset.owner, CalendarScreen(sync: sync));
      return sync;
    }

    testWidgets('today\'s bookings and busy blocks, contact actions, the '
        'connect card while the phone calendar is not connected', (t) async {
      final today = DateTime.now();
      final at = DateTime(today.year, today.month, today.day, 10).toUtc();
      agenda(
        b,
        reminderMinutes: 0,
        [booking('b1', start: at, name: 'נועה לוי', notes: 'שאלה על חוזה')],
        busy: [
          {
            'start': at.add(const Duration(hours: 2)).toIso8601String(),
            'end': at.add(const Duration(hours: 3)).toIso8601String(),
            'mine': true,
          },
        ],
      );
      await pump(t);
      expect(find.text('נועה לוי'), findsOneWidget);
      expect(find.text('שאלה על חוזה'), findsOneWidget);
      await reveal(t, find.text(CalendarHe.busyBlock));
      expect(find.text(CalendarHe.busyBlock), findsOneWidget);
      expect(find.byKey(const Key('booking-cancel-b1')), findsOneWidget);
      expect(find.byKey(const Key('calendar-connect-card')), findsOneWidget);
      expect(find.byKey(const Key('calendar-share')), findsOneWidget);
    });

    testWidgets('share sheet: the public link + WhatsApp / share / copy', (
      t,
    ) async {
      agenda(b, [], reminderMinutes: 0);
      await pump(t);
      await t.tap(find.byKey(const Key('calendar-share')));
      await settle(t);
      expect(
        find.text('https://invoice.tevel.space/book/AbCdEfGhIjKlMnOpQrStUv'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('calendar-share-whatsapp')), findsOneWidget);
      expect(find.byKey(const Key('calendar-share-other')), findsOneWidget);
      expect(find.byKey(const Key('calendar-copy')), findsOneWidget);
    });

    testWidgets('owner cancel asks first, then calls the server once', (
      t,
    ) async {
      final today = DateTime.now();
      final at = DateTime(today.year, today.month, today.day, 10).toUtc();
      agenda(b, [booking('b1', start: at)], reminderMinutes: 0);
      b.json('POST', '/calendar/bookings/:id/cancel', {
        'booking': booking('b1', start: at, status: 'CANCELLED'),
      });
      await pump(t);
      await reveal(t, find.byKey(const Key('booking-cancel-b1')));
      await t.tap(find.byKey(const Key('booking-cancel-b1')));
      await settle(t);
      expect(find.text(CalendarHe.cancelTitle), findsOneWidget);
      await t.tap(find.byKey(const Key('calendar-cancel-confirm')));
      await settle(t);
      expect(b.calls('POST', '/calendar/bookings/:id/cancel'), hasLength(1));
    });

    testWidgets('a switched-off calendar says so and can be turned on', (
      t,
    ) async {
      b.json('GET', '/calendar/settings', {
        'settings': settingsJson(enabled: false),
      });
      b.json('PUT', '/calendar/settings', {'settings': settingsJson()});
      agenda(b, [], enabled: false, reminderMinutes: 0);
      await pump(t);
      expect(find.byKey(const Key('calendar-off')), findsOneWidget);
      await t.tap(find.byKey(const Key('calendar-turn-on')));
      await settle(t);
      expect(b.last('PUT', '/calendar/settings')!.body, {'enabled': true});
      expect(find.byKey(const Key('calendar-off')), findsNothing);
    });
  });
}
