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
//   PHASE=after  (flutter test reinstalls the app) sign in, grant, connect →
//                the existing bookings are written into the phone calendar →
//                a client books now (host) → the notch animation names them →
//                the week agenda → the in-app reminder before the soonest
//                meeting fires with the same animation.
//
// Same SHOT: protocol as persona_screens_test.dart (the host takes the
// screenshot when it reads the line).
// ignore_for_file: avoid_print, use_build_context_synchronously
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/screens/calendar/calendar_api.dart' show ymd;
import 'package:invoice/screens/calendar/calendar_screen.dart';
import 'package:invoice/screens/calendar/calendar_sync.dart';
import 'package:invoice/util/labels/calendar_he.dart';

import 'crash_sweep_test.dart' show t, pumpMs, waitFor;
import 'persona_screens_test.dart'
    show role, shot, runCaptured, owner, ctx, startPlansGuard, plansGuardOn;
import 'v2_qa_gate_helpers.dart' show launchSignedInAs;

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

/// `flutter test` reinstalls the app, which resets its iOS privacy grants: the
/// host grants calendar access (simctl privacy) when it reads GRANT-CALENDAR
/// and drops a marker file next to the mail folder.
Future<void> _hostGrantsCalendar() async {
  final marker = File(
    '${const String.fromEnvironment('MAILDIR')}/../calendar-granted',
  );
  print('GRANT-CALENDAR');
  final until = DateTime.now().add(const Duration(minutes: 4));
  while (!marker.existsSync() && DateTime.now().isBefore(until)) {
    await pumpMs(500);
  }
  if (!marker.existsSync()) throw StateError('host did not grant calendar');
}

Future<void> _hostBooks() async {
  final marker = File('${const String.fromEnvironment('MAILDIR')}/../booked');
  print('BOOK-NOW');
  final until = DateTime.now().add(const Duration(minutes: 3));
  while (!marker.existsSync() && DateTime.now().isBefore(until)) {
    await pumpMs(500);
  }
  if (!marker.existsSync()) throw StateError('host did not book');
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
  // A clean start on a phone that ran this before: not connected.
  if ((await calendarSync.loadPrefs())?.connected ?? false) {
    await calendarSync.disconnect();
    await pumpMs(1500);
  }
  await shot('agenda-before-connect');

  // The Hebrew iOS prompt itself is in ios-permission-prompt-he.png; here the
  // host grants access, so the tap below gets "full access" at once.
  await _hostGrantsCalendar();
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
  // Tomorrow, day view (month grid → tap the day).
  await t.tap(find.byKey(Key('calendar-day-${ymd(_tomorrowAt(0))}')));
  await pumpMs(1500);
  await shot('agenda-busy-from-phone');

  await t.tap(find.byKey(const Key('calendar-more')));
  await pumpMs(800);
  await t.tap(find.text(CalendarHe.hoursButton).last);
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

  await t.tap(find.byKey(const Key('calendar-more')));
  await pumpMs(800);
  await t.tap(find.text(CalendarHe.share).last);
  await pumpMs(1800);
  await shot('share-sheet');
  Navigator.of(ctx).pop();
  await pumpMs(800);
  print('SETUP-DONE');
}

Future<void> _after() async {
  // `flutter test` reinstalls the app (Keychain + privacy grants are gone):
  // sign in again, the host grants calendar access, connect.
  await launchSignedInAs(t, owner);
  await waitFor(find.byKey(const Key('tab-home')), ms: 40000);
  await pumpMs(2500);
  // The reminder is switched on at the end, timed to fire during the run.
  await ApiClient.instance.put('/calendar/settings', {'reminderMinutes': 0});
  await _hostGrantsCalendar();
  await calendarSync.connect();
  // The first sync on this phone marks the bookings that exist as seen and
  // writes them into the phone calendar.
  await calendarSync.sync(force: true);
  await pumpMs(3000);
  // A client books NOW (the host posts the public form) → the next sync shows
  // the notch with the client's name and time.
  await _hostBooks();
  await calendarSync.sync(force: true);
  await waitFor(find.byKey(const Key('notch-notice')), ms: 30000);
  await shot('notch-new-booking', settleMs: 900);
  await pumpMs(5000);
  await _openCalendar();
  await t.tap(find.byKey(const Key('calendar-list-toggle')));
  await pumpMs(1500);
  await shot('agenda-list-with-bookings');
  print('WRITTEN-EVENTS:${calendarSync.prefs?.events.length ?? 0}');

  // Reminder before a meeting: the booking that starts soonest (the one just
  // made), with the reminder set so it fires about a minute from now.
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
