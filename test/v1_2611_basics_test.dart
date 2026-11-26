// 2611 track V1: the first-run tutorial + coach marks (§1), the reminder
// cadence labels / next-reminder line (§2), the Google-calendar guide (§3א),
// and the inactive-customer action rules (§4).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/screens/calendar/calendar_sync.dart';
import 'package:invoice/screens/calendar/device_calendar.dart';
import 'package:invoice/screens/calendar/google_calendar_guide.dart';
import 'package:invoice/screens/debts/next_reminder.dart';
import 'package:invoice/screens/people/person_logic.dart';
import 'package:invoice/screens/tutorial/coach_mark.dart';
import 'package:invoice/screens/tutorial/tutorial_screen.dart';
import 'package:invoice/screens/tutorial/tutorial_state.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/ds.dart';
import 'package:invoice/util/labels/calendar_he.dart';
import 'package:invoice/util/labels/collection_he.dart';
import 'package:invoice/util/labels/tutorial_he.dart';

import 'fakes/fake_api.dart';

Caps capsOf(Preset p) => Caps.fromMe(Me.fromJson(meJson(p)));

Widget app(Widget home) => MaterialApp(
  locale: const Locale('he', 'IL'),
  supportedLocales: const [Locale('he', 'IL')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: buildTheme(Brightness.light),
  home: home,
);

DeviceCalendarInfo cal(String id, String account) => DeviceCalendarInfo(
  id: id,
  title: id,
  account: account,
  color: '#00AA00',
  writable: true,
  isDefault: false,
);

class _Device implements DeviceCalendarPort {
  _Device(this.access, this.list);

  CalendarAccess access;
  List<DeviceCalendarInfo> list;

  @override
  bool get supported => true;
  @override
  set onChanged(VoidCallback? callback) {}
  @override
  Future<CalendarAccess> status() async => access;
  @override
  Future<CalendarAccess> requestAccess() async => access;
  @override
  Future<List<DeviceCalendarInfo>> calendars() async => list;
  @override
  Future<List<DeviceInterval>> busy(
    DateTime from,
    DateTime to,
    List<String> calendarIds,
  ) async => const [];
  @override
  Future<String?> upsertEvent({
    required String bookingId,
    required String? eventId,
    required String? calendarId,
    required DateTime start,
    required DateTime end,
    required String title,
    required String notes,
  }) async => null;
  @override
  Future<void> deleteEvent(String eventId) async {}
  @override
  Future<int> scheduleReminders(List<LocalReminder> items) async => 0;
}

class _Prefs implements CalendarPrefsStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

void main() {
  group('§2 next reminder line (pure)', () {
    test('"יום ב׳ 1.12" — weekday and day.month without padding', () {
      expect(reminderDayLabel('2026-12-01'), 'יום ג׳ 1.12');
      expect(reminderDayLabel('2026-11-30'), 'יום ב׳ 30.11');
      expect(reminderDayLabel('nonsense'), isNull);
      expect(reminderDayLabel(null), isNull);
    });

    test('scheduled / manual / paused / off', () {
      expect(
        nextReminderLine(state: 'SCHEDULED', date: '2026-12-07'),
        'תזכורת הבאה: יום ב׳ 7.12',
      );
      expect(
        nextReminderLine(state: 'MANUAL', date: null),
        CollectionHe.manualHandling,
      );
      expect(
        nextReminderLine(state: 'PAUSED', date: null),
        CollectionHe.remindersPaused,
      );
      expect(nextReminderLine(state: 'OFF', date: null), isNull);
      expect(nextReminderLine(state: 'NONE', date: null), isNull);
      expect(nextReminderLine(state: null, date: null), isNull);
    });

    test('cadence labels cover every choice', () {
      for (final c in [
        'BUSINESS',
        'WEEKLY',
        'BIWEEKLY',
        'MONTHLY',
        'NONE',
        'LADDER',
      ]) {
        expect(CollectionHe.cadenceLabel(c), isNot(c));
        expect(CollectionHe.cadenceHint(c), isNotEmpty);
      }
    });
  });

  group('§4 inactive customer actions (pure)', () {
    const base = PersonActionFacts(canManage: false, canRestore: true);
    test('"החזר לפעיל" is never in "עוד" (header ⋯ + the inactive banner)', () {
      expect(
        personMoreActions(
          const PersonActionFacts(archived: true, canRestore: true),
          const [],
        ),
        isNot(contains('restore')),
      );
      expect(personMoreActions(base, const []), isNot(contains('restore')));
      expect(
        personMoreActions(const PersonActionFacts(archived: true), const []),
        isNot(contains('restore')),
      );
    });
  });

  group('§3א Google calendars on the iPhone', () {
    test('detected by the account (Gmail address / Google)', () {
      expect(isGoogleCalendar(cal('a', 'dana@gmail.com')), isTrue);
      expect(isGoogleCalendar(cal('b', 'Gmail')), isTrue);
      expect(isGoogleCalendar(cal('c', 'Google')), isTrue);
      expect(isGoogleCalendar(cal('d', 'iCloud')), isFalse);
      expect(isGoogleCalendar(cal('e', 'Outlook')), isFalse);
      expect(
        googleCalendars([
          cal('a', 'iCloud'),
          cal('b', 'x@googlemail.com'),
        ]).map((c) => c.id),
        ['b'],
      );
    });

    Future<CalendarSync> pumpGuide(WidgetTester t, _Device device) async {
      t.view
        ..physicalSize = const Size(1170, 2532)
        ..devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final backend = FakeBackend()..install();
      await t.runAsync(() => signInAs(backend, Preset.owner));
      backend.json('PUT', '/calendar/busy', const {'ok': true});
      backend.json('GET', '/calendar/agenda', const {'bookings': []});
      final sync = CalendarSync(device: device, store: _Prefs());
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(app(GoogleCalendarGuideScreen(sync: sync)));
      await t.runAsync(() => Future<void>.delayed(Duration.zero));
      await t.pumpAndSettle();
      return sync;
    }

    testWidgets('found → the Google calendars to tick; ticking reads them', (
      t,
    ) async {
      final device = _Device(CalendarAccess.full, [
        cal('home', 'iCloud'),
        cal('work', 'nora@gmail.com'),
      ]);
      final sync = await pumpGuide(t, device);
      expect(find.text(CalendarHe.googleFound), findsOneWidget);
      expect(find.byKey(const Key('google-calendar-work')), findsOneWidget);
      expect(find.byKey(const Key('google-calendar-home')), findsNothing);
      expect(find.text(CalendarHe.googleStep1Title), findsOneWidget);
      expect(find.byKey(const Key('google-open-settings')), findsOneWidget);
      await t.tap(find.byKey(const Key('google-calendar-work')));
      await t.runAsync(() => Future<void>.delayed(Duration.zero));
      await t.pumpAndSettle();
      expect(sync.prefs?.read, contains('work'));
    });

    testWidgets('not found yet / no access / denied', (t) async {
      final device = _Device(CalendarAccess.full, [cal('home', 'iCloud')]);
      await pumpGuide(t, device);
      expect(find.byKey(const Key('google-not-found')), findsOneWidget);

      device.access = CalendarAccess.notDetermined;
      await pumpGuide(t, device);
      expect(find.byKey(const Key('google-allow')), findsOneWidget);

      device.access = CalendarAccess.denied;
      await pumpGuide(t, device);
      expect(find.byKey(const Key('google-denied')), findsOneWidget);
    });
  });

  group('§1 tutorial state (device only)', () {
    test(
      'armed once: cards once, each coach mark once; replay re-arms',
      () async {
        final s = TutorialState(MemoryTutorialStorage());
        expect(await s.takeCards(), isFalse, reason: 'an existing user');
        expect(await s.coachDue(CoachIds.home), isFalse);
        await s.arm();
        expect(await s.takeCards(), isTrue);
        expect(await s.takeCards(), isFalse);
        expect(await s.coachDue(CoachIds.people), isTrue);
        expect(await s.takeCoach(CoachIds.people), isTrue);
        expect(await s.takeCoach(CoachIds.people), isFalse);
        expect(await s.takeCoach(CoachIds.home), isTrue);
        await s.replay();
        expect(await s.takeCards(), isFalse, reason: 'help opens them itself');
        expect(await s.takeCoach(CoachIds.people), isTrue);
      },
    );

    test(
      'owner: 4 cards; employee: the short version (no money, no calendar)',
      () {
        expect(tutorialCardsFor(capsOf(Preset.owner)), TutorialCard.values);
        expect(tutorialCardsFor(capsOf(Preset.employee)), [
          TutorialCard.document,
          TutorialCard.customers,
        ]);
      },
    );
  });

  group('§1 tutorial screen', () {
    Future<void> pumpCards(WidgetTester t, List<TutorialCard> cards) async {
      t.view
        ..physicalSize = const Size(1170, 2532)
        ..devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: app(
            Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TutorialScreen(cards: cards),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }

    testWidgets('swipe through the cards; "בוא נתחיל" on the last closes', (
      t,
    ) async {
      await pumpCards(t, TutorialCard.values);
      expect(find.text(TutorialHe.docTitle), findsOneWidget);
      expect(find.text(TutorialHe.skip), findsOneWidget);
      expect(find.text(TutorialHe.next), findsOneWidget);
      await t.tap(find.byKey(const Key('tutorial-next')));
      await t.pumpAndSettle();
      expect(find.text(TutorialHe.debtsTitle), findsOneWidget);
      await t.tap(find.byKey(const Key('tutorial-next')));
      await t.pumpAndSettle();
      expect(find.text(TutorialHe.customersTitle), findsOneWidget);
      await t.tap(find.byKey(const Key('tutorial-next')));
      await t.pumpAndSettle();
      expect(find.text(TutorialHe.calendarTitle), findsOneWidget);
      expect(find.text(TutorialHe.start), findsOneWidget);
      await t.tap(find.byKey(const Key('tutorial-next')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tutorial')), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('"דלג" closes at once; the first semantic node is "דלג"', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      await pumpCards(t, const [TutorialCard.document, TutorialCard.customers]);
      expect(find.text(TutorialHe.debtsTitle), findsNothing);
      final skip = t.getSemantics(find.byKey(const Key('tutorial-skip')));
      expect(skip.label, TutorialHe.skip);
      await t.tap(find.byKey(const Key('tutorial-skip')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tutorial')), findsNothing);
      handle.dispose();
    });
  });

  group('§1 coach marks', () {
    testWidgets('due once → a bubble at the target; a tap anywhere closes', (
      t,
    ) async {
      final state = TutorialState(MemoryTutorialStorage());
      await state.arm();
      await t.pumpWidget(
        app(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  key: const Key('target'),
                  onPressed: () => unawaited(
                    maybeShowCoachMark(
                      context,
                      id: CoachIds.people,
                      target: const Key('target'),
                      text: TutorialHe.coachPeople,
                      state: state,
                    ),
                  ),
                  child: const Text('יעד'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.byKey(const Key('target')));
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      expect(find.text(TutorialHe.coachPeople), findsOneWidget);
      await t.tapAt(const Offset(20, 20));
      await t.pumpAndSettle();
      expect(find.text(TutorialHe.coachPeople), findsNothing);
      // Once only.
      await t.tap(find.byKey(const Key('target')));
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      expect(find.text(TutorialHe.coachPeople), findsNothing);
    });
  });
}
