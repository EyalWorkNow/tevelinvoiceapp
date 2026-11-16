// 0106 "יומן" — end-to-end on a simulator against a LOCAL staging API (never
// production), in two phases with host steps in between
// (docs/calendar/E2E-he.md, ops/calendar-e2e.sh):
//
//   PHASE=setup  owner signs in → settings on the server → ניהול → יומן →
//                connect the phone calendar (permission granted beforehand on
//                the simulator) → a PRIVATE event is added to the phone's own
//                calendar → sync → the agenda shows it as "תפוס"; prints
//                PUBLIC:<booking url> and BUSY:<start>.
//   (host)       Calendar app + the public page in Safari (the busy time is
//                gone, no title) → a client books in Safari → mail catcher.
//   PHASE=after  the app opens again (same phone, no reset) → the new booking
//                arrives with the notch animation, is written into the phone
//                calendar, and the local reminder before the meeting fires
//                with the same animation while the app is open.
//
// Same SHOT: protocol as persona_screens_test.dart (the host takes the
// screenshot when it reads the line).
// ignore_for_file: avoid_print, use_build_context_synchronously
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/main.dart' as app;
import 'package:invoice/screens/calendar/calendar_screen.dart';
import 'package:invoice/screens/calendar/calendar_sync.dart';

import 'crash_sweep_test.dart' show t, pumpMs, waitFor;
import 'persona_screens_test.dart'
    show role, shot, runCaptured, owner, ctx, startPlansGuard, plansGuardOn;
import 'v2_qa_gate_helpers.dart' show launchSignedInAs, keychain;

const phase = String.fromEnvironment('PHASE', defaultValue: 'setup');

/// 08:00–20:00 every day except Saturday; TODAY opens from the current half
/// hour for two hours, so a meeting "soon" exists at any hour of the run.
List<Map<String, Object>> _hours() {
  final now = DateTime.now();
  String hm(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  final from = (now.hour * 60 + now.minute) ~/ 30 * 30;
  final to = (from + 150).clamp(0, 24 * 60);
  final today = now.weekday % 7;
  return [
    for (var d = 0; d < 7; d++)
      {
        'day': d,
        'ranges': d == today
            ? [
                {'start': hm(from), 'end': hm(to)},
              ]
            : d == 6
            ? <Map<String, String>>[]
            : [
                {'start': '08:00', 'end': '20:00'},
              ],
      },
  ];
}

DateTime _tomorrowAt(int hour) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day + 1, hour);
}

Future<void> _openCalendar() async {
  await t.tap(find.byKey(const Key('tab-business')));
  await pumpMs(1500);
  final entry = find.text('יומן').hitTestable();
  if (entry.evaluate().isNotEmpty) {
    await shot('manage-entry');
    await t.tap(entry.first);
  } else {
    unawaited(openCalendar(ctx));
  }
  await pumpMs(3500);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  startPlansGuard();

  testWidgets('calendar e2e ($phase)', (tester) async {
    await runCaptured(tester, () async {
      role = 'calendar';
      // The "מקום לגדול" plans sheet on staging is closed as in the other QA runs.
      plansGuardOn = true;
      if (phase == 'setup') {
        await _setup();
      } else {
        await _after();
      }
    });
  });
}

Future<void> _setup() async {
  await launchSignedInAs(t, owner);
  await waitFor(find.byKey(const Key('tab-home')), ms: 40000);
  await pumpMs(2500);
  final api = ApiClient.instance;
  final settings = await api.put('/calendar/settings', {
    'enabled': true,
    'weeklyHours': _hours(),
    'slotMinutes': 30,
    'bufferMinutes': 0,
    'minNoticeMinutes': 0,
    'maxDaysAhead': 14,
    'meetingTitle': 'פגישת ייעוץ',
    'notifyNewBooking': true,
    'reminderMinutes': 15,
  });
  final url = (settings['settings'] as Map)['bookingUrl'] as String;
  print('PUBLIC:$url');

  await _openCalendar();
  await shot('agenda-before-connect');

  // iOS permission was granted to the app on the simulator before this run
  // (simctl privacy … grant calendar): the tap below gets "full access" at once.
  await t.tap(find.byKey(const Key('calendar-connect')));
  await pumpMs(3000);

  // The owner's own PRIVATE event (as if typed in the Calendar app): tomorrow 10:00–11:00.
  final start = _tomorrowAt(10);
  final end = _tomorrowAt(11);
  await const MethodChannel(
    'tevel/calendar',
  ).invokeMethod<String>('debugAddEvent', {
    'title': 'טיפול שיניים — פרטי',
    'start': start.millisecondsSinceEpoch,
    'end': end.millisecondsSinceEpoch,
  });
  print('BUSY:${start.toUtc().toIso8601String()}');
  await calendarSync.sync(force: true);
  await pumpMs(2500);
  // Tomorrow, day view.
  await t.tap(find.byKey(const Key('calendar-next')));
  await pumpMs(1500);
  await shot('agenda-busy-from-phone');

  await t.tap(find.byKey(const Key('calendar-settings')));
  await pumpMs(3500);
  await shot('settings-top');
  await t.drag(find.byType(Scrollable).first, const Offset(0, -700));
  await pumpMs(1200);
  await shot('settings-hours');
  await t.drag(find.byType(Scrollable).first, const Offset(0, -900));
  await pumpMs(1200);
  await shot('settings-notifications-calendars');
  Navigator.of(ctx).pop();
  await pumpMs(2000);

  await t.tap(find.byKey(const Key('calendar-share')));
  await pumpMs(1800);
  await shot('share-sheet');
  Navigator.of(ctx).pop();
  await pumpMs(800);
  print('SETUP-DONE');
}

Future<void> _after() async {
  // Same phone, same sign-in: no reset (the calendar choices stay).
  final token = await keychain.read(key: 'device_token');
  if (token == null) throw StateError('run PHASE=setup first');
  app.main();
  await waitFor(find.byKey(const Key('tab-home')), ms: 40000);
  // The sync on launch sees the client's booking → notch (shot mid-animation).
  await waitFor(find.byKey(const Key('notch-notice')), ms: 30000);
  await shot('notch-new-booking', settleMs: 700);
  await pumpMs(5000);
  await _openCalendar();
  await t.tap(find.byKey(const Key('calendar-view')).first);
  await pumpMs(500);
  await t.tap(find.text('שבוע').first);
  await pumpMs(1500);
  await shot('agenda-week-with-booking');
  final written = calendarSync.prefs?.events.length ?? 0;
  print('WRITTEN-EVENTS:$written');

  // Reminder before a meeting: a booking that starts soon (made by the host
  // script), with the reminder set so it fires about a minute from now.
  final agenda = calendarSync.agenda!;
  final soon = agenda.bookings
      .where((b) => b.confirmed && b.startsAt.isAfter(DateTime.now()))
      .reduce((a, b) => a.startsAt.isBefore(b.startsAt) ? a : b);
  final minutes = soon.startsAt.difference(DateTime.now()).inSeconds ~/ 60 - 1;
  print('SOON:${soon.startsAt.toUtc().toIso8601String()} reminder=$minutes');
  await ApiClient.instance.put('/calendar/settings', {
    'reminderMinutes': minutes,
  });
  await calendarSync.sync(force: true);
  await pumpMs(1000);
  // Wait for the in-app reminder (foreground → notch).
  final until = DateTime.now().add(const Duration(minutes: 3));
  var seen = false;
  while (DateTime.now().isBefore(until)) {
    await pumpMs(500);
    if (find.textContaining('הפגישה הבאה מתקרבת').evaluate().isNotEmpty) {
      seen = true;
      break;
    }
  }
  if (seen) await shot('notch-reminder', settleMs: 600);
  print('REMINDER-NOTCH:$seen');
  await ApiClient.instance.put('/calendar/settings', {'reminderMinutes': 15});
  await pumpMs(5000);
  print('AFTER-DONE');
}
