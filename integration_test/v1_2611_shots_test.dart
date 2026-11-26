// 2611 track V1 shots (tutorial, coach marks, reminder cadence, Google guide,
// inactive customers), with MOCKED data (the test FakeBackend, no server).
// Same SHOT: protocol as customer_page_shots_test:
//
//   U=<sim udid>; OUT=$PWD/docs/qa/2611-v1
//   ~/flutter/bin/flutter test integration_test/v1_2611_shots_test.dart -d $U 2>&1 |
//   while IFS= read -r l; do echo "$l"; if [[ $l == *SHOT:* ]]; then
//     n=${l##*SHOT:}; xcrun simctl io $U screenshot "$OUT/$n.png" >/dev/null 2>&1; fi; done
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/api/models/models.dart' show Me;
import 'package:invoice/router.dart';
import 'package:invoice/screens/business/collection_settings_screen.dart';
import 'package:invoice/screens/calendar/calendar_settings_screen.dart';
import 'package:invoice/screens/calendar/calendar_sync.dart';
import 'package:invoice/screens/calendar/device_calendar.dart';
import 'package:invoice/screens/calendar/google_calendar_guide.dart';
import 'package:invoice/screens/debts/debts_screen.dart';
import 'package:invoice/screens/debts/reminder_hold_tile.dart';
import 'package:invoice/screens/help/help_screen.dart';
import 'package:invoice/screens/people/people_screen.dart';
import 'package:invoice/screens/people/person_screen.dart';
import 'package:invoice/screens/tutorial/tutorial_screen.dart';
import 'package:invoice/screens/tutorial/tutorial_state.dart';
import 'package:invoice/state/business_context.dart';
import 'package:invoice/state/caps.dart';

import '../test/business/e_harness.dart';
import '../test/fakes/fake_api.dart';

late WidgetTester t;

Future<void> pumpMs(int ms) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  do {
    await t.pump(const Duration(milliseconds: 50));
  } while (DateTime.now().isBefore(end));
}

Future<void> shot(String name) async {
  await pumpMs(1200);
  print('SHOT:$name');
  await pumpMs(1300);
}

void audit(String s) => print('AUDIT: $s');

Future<bool> tapIf(Finder f, {int waitMs = 1200}) async {
  for (var i = 0; i < 20 && f.evaluate().isEmpty; i++) {
    await pumpMs(150);
  }
  if (f.evaluate().isEmpty) {
    audit('not found: $f');
    return false;
  }
  await t.ensureVisible(f.first);
  await pumpMs(300);
  await t.tap(f.first, warnIfMissed: false);
  await pumpMs(waitMs);
  return true;
}

Future<void> closeAll() async {
  navigatorKey.currentState!.popUntil((r) => r.isFirst);
  await pumpMs(900);
}

Future<void> show(Widget w) async {
  await t.pumpWidget(const SizedBox());
  await pumpMs(200);
  await t.pumpWidget(eApp(w));
  await pumpMs(2200);
}

String day(int offset) {
  final d = DateTime.now().add(Duration(days: offset));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

Map<String, dynamic> row(
  String id,
  String name, {
  String? phone,
  bool inactive = false,
  String balance = '0',
}) => {
  'id': id,
  'name': name,
  'tax_id': null,
  'email': null,
  'phone': phone,
  'archived_at': inactive ? '2026-09-01T08:00:00Z' : null,
  'vat_dealer_status': 'PRIVATE',
  'customer_type': 'INDIVIDUAL',
  'balanceMinor': balance,
  'creditMinor': '0',
  'lastDocumentAt': null,
  'isWalkIn': false,
  'consent': {'granted': true},
};

final customers = [
  row('c1', 'נועה לוי', phone: '050-0000101', balance: '284000'),
  row('c2', 'איתי כהן', phone: '050-0000102'),
  row('c3', 'קפה אלמה', phone: '050-0000103', balance: '96000'),
  row('c4', 'מאיה מזרחי', phone: '050-0000104'),
  row('c5', 'עומר פרץ', phone: '050-0000105'),
  row('c6', 'תמר ביטון', phone: '050-0000106'),
  row('c7', 'רוני שפירא', phone: '050-0000131', inactive: true),
  row('c8', 'גלריה רמה', phone: '050-0000132', inactive: true),
  row('c9', 'הילה גולן', phone: '050-0000133', inactive: true),
];

Map<String, dynamic> detail(String id, {bool inactive = false}) {
  final r = customers.firstWhere((c) => c['id'] == id);
  return {
    'customer': {
      ...r,
      'archivedAt': inactive ? '2026-09-01T08:00:00Z' : null,
      'erased': false,
      'reminderCadence': id == 'c1' ? 'WEEKLY' : null,
      'address': null,
      'contactPerson': null,
      'paymentTerms': 'EOM_30',
      'paymentTermsDays': null,
      'preferredPaymentMethod': 'BANK_TRANSFER',
      'effectivePaymentTerms': {
        'code': 'EOM_30',
        'days': null,
        'preferredPaymentMethod': 'BANK_TRANSFER',
        'source': 'CUSTOMER',
      },
      'notes': null,
      'accountKey': null,
      'consent': {'granted': true, 'method': null, 'at': null},
    },
    'stats': {
      'openMinor': r['balanceMinor'],
      'overdueMinor': '0',
      'creditMinor': '0',
      'documentsCount': 3,
      'lastDocumentAt': null,
    },
  };
}

Map<String, dynamic> debtor(
  String id,
  String name,
  String total,
  int overdue, {
  String? next,
  int manual = 0,
  int count = 1,
}) => {
  'customerId': id,
  'customerName': name,
  'phone': '050-0000101',
  'totalMinor': total,
  'documentsOpenMinor': total,
  'debtBookMinor': '0',
  'oldestOverdueDays': overdue,
  'oldestEntryDays': null,
  'lastRemindedAt': DateTime.now()
      .subtract(const Duration(days: 4))
      .toUtc()
      .toIso8601String(),
  'reminderCount': count,
  'nextReminderDate': next,
  'manualCount': manual,
  'documents': [
    {
      'id': 'd-$id',
      'documentType': 'TAX_INVOICE',
      'documentNumber': '10${id.substring(1)}7',
      'dueDate': day(-overdue),
      'openMinor': total,
      'overdueDays': overdue,
      'nextReminder': manual > 0
          ? {'state': 'MANUAL', 'date': null, 'count': 6}
          : {'state': 'SCHEDULED', 'date': next, 'count': count},
    },
  ],
  'debtEntries': <Object>[],
};

class _Device implements DeviceCalendarPort {
  _Device(this.list);
  final List<DeviceCalendarInfo> list;
  @override
  bool get supported => true;
  @override
  set onChanged(VoidCallback? callback) {}
  @override
  Future<CalendarAccess> status() async => CalendarAccess.full;
  @override
  Future<CalendarAccess> requestAccess() async => CalendarAccess.full;
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
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

DeviceCalendarInfo cal(String id, String title, String account, String c) =>
    DeviceCalendarInfo(
      id: id,
      title: title,
      account: account,
      color: c,
      writable: true,
      isDefault: id == 'home',
    );

FakeBackend backend() {
  final b = FakeBackend()..install();
  installBusinessFakes(b);
  installPeopleFakes(b, customers: customers, be09: true);
  b
    ..on('GET', '/customers', (r) {
      return FakeResponse(200, {
        'customers': customers,
        'total': customers.length,
        'counts': {'active': 30, 'inactive': 10, 'all': 40},
      });
    })
    ..on(
      'GET',
      '/customers/:id',
      (r) => FakeResponse(
        200,
        detail(r.params['id']!, inactive: r.params['id'] == 'c7'),
      ),
    )
    ..json('GET', '/crm/customers', {'total': 0, 'records': <Object>[]})
    ..json('GET', '/settings/payment-terms', {
      'paymentTerms': 'EOM_30',
      'paymentTermsDays': null,
      'preferredPaymentMethod': null,
    })
    ..json('GET', '/settings/reminders', {
      'enabled': true,
      'cadence': 'WEEKLY',
      'steps': [
        {'offsetDays': -3, 'enabled': true, 'template': null},
        {'offsetDays': 0, 'enabled': true, 'template': null},
        {'offsetDays': 7, 'enabled': true, 'template': null},
      ],
      'maxPerDocument': 3,
      'channels': {'email': true, 'whatsapp': true},
      'dailySummary': true,
      'defaultTemplates': {'before': '', 'onDue': '', 'after': ''},
    })
    ..json('GET', '/debts', {
      'today': day(0),
      'documentsOpenMinor': '1196000',
      'documentsOverdueMinor': '1196000',
      'debtBookOpenMinor': '0',
      'totalMinor': '1196000',
      'customers': [
        debtor('c1', 'נועה לוי', '284000', 64, manual: 1, count: 6),
        debtor('c3', 'קפה אלמה', '96000', 12, next: day(2), count: 2),
        debtor('c4', 'מאיה מזרחי', '816000', 3, next: day(4)),
      ],
    })
    ..json('GET', '/collection-reminders/ready', {
      'count': 0,
      'reminders': <Object>[],
    })
    ..json('GET', '/calendar/settings', {
      'settings': {
        'enabled': true,
        'slug': 'AbCd',
        'bookingUrl': 'https://invoice.tevel.space/book/AbCd',
        'weeklyHours': [
          for (var d = 0; d < 7; d++)
            {
              'day': d,
              'ranges': d == 6
                  ? []
                  : [
                      {'start': '09:00', 'end': d == 5 ? '13:00' : '17:00'},
                    ],
            },
        ],
        'slotMinutes': 30,
      },
    })
    ..json('GET', '/calendar/agenda', {'bookings': <Object>[], 'busy': []})
    ..json('PUT', '/calendar/busy', {'stored': 0})
    ..json('GET', '/help/status', {'available': true})
    ..json('GET', '/documents', {'documents': <Object>[]});
  return b;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('2611 V1 shots', (tester) async {
    t = tester;
    await eSetUp();
    loadReminderHold = ({customerId, documentId}) async => false;
    final b = backend();
    await signInAs(b, Preset.owner);
    final caps = businessContext.caps;

    // §1 · the four cards.
    await show(TutorialScreen(cards: tutorialCardsFor(caps)));
    await shot('01-tutorial-1-document');
    for (var i = 2; i <= 4; i++) {
      await tapIf(find.byKey(const Key('tutorial-next')), waitMs: 1500);
      await shot('0$i-tutorial-$i-${tutorialCardsFor(caps)[i - 1].name}');
    }
    // The employee's short version.
    await show(
      TutorialScreen(cards: tutorialCardsFor(capsOfPreset(Preset.employee))),
    );
    await shot('05-tutorial-employee-1');

    // §1 · a coach mark (armed as after the tutorial) on the customers list.
    tutorialState.storage = MemoryTutorialStorage();
    await tutorialState.arm();
    await tutorialState.takeCards();
    await show(const PeopleScreen());
    await pumpMs(1500);
    await shot('06-coach-people');
    await t.tapAt(const Offset(30, 120));
    await pumpMs(800);

    // §4 · chips with counts, inactive list, all.
    await shot('07-people-active');
    await tapIf(find.text('לא פעילים 10'));
    await shot('08-people-inactive');
    await tapIf(find.text('הכול 40'));
    await shot('09-people-all');

    // §4 · an inactive customer page + the "סמן כלא פעיל" dialog.
    await tutorialState.takeCoach(CoachIds.person);
    await show(const PersonScreen(id: 'c7'));
    await shot('10-person-inactive');
    await show(const PersonScreen(id: 'c1'));
    final menu = find.byTooltip('עוד');
    if (await tapIf(menu.last)) {
      await shot('11-person-menu');
      if (await tapIf(find.text('סמן כלא פעיל').last)) {
        await shot('12-mark-inactive-dialog');
      }
      await closeAll();
    }

    // §2 · terms + reminders on the customer page.
    await show(const PersonScreen(id: 'c1'));
    if (await tapIf(find.byKey(const Key('person-details')))) {
      if (await tapIf(find.byKey(const Key('person-terms')))) {
        await shot('13-terms-and-reminders-sheet');
        await t.drag(
          find.byKey(const Key('terms-sheet')),
          const Offset(0, -400),
        );
        await shot('14-terms-cadence');
      }
    }
    await closeAll();

    // §2 · business cadence + "תזכורת הבאה" / "לטיפול ידני".
    await show(const CollectionSettingsScreen());
    await shot('15-collection-cadence');
    await show(DebtsScreen(now: DateTime.now));
    await shot('16-debts-next-reminder');
    if (await tapIf(find.text('קפה אלמה'))) {
      await shot('17-debts-document-next');
    }

    // §3א · the Google guide (found / not found) + the calendar settings row.
    final found = CalendarSync(
      device: _Device([
        cal('home', 'בית', 'iCloud', '#34C759'),
        cal('g1', 'סטודיו נורה', 'nora.studio@gmail.com', '#4285F4'),
        cal('g2', 'משפחה', 'nora.studio@gmail.com', '#DB4437'),
      ]),
      store: _Prefs(),
    );
    await show(GoogleCalendarGuideScreen(sync: found));
    await shot('18-google-found');
    final none = CalendarSync(
      device: _Device([cal('home', 'בית', 'iCloud', '#34C759')]),
      store: _Prefs(),
    );
    await show(GoogleCalendarGuideScreen(sync: none));
    await shot('19-google-not-found');
    await show(CalendarSettingsScreen(sync: found));
    for (var i = 0; i < 12; i++) {
      final s = find.byType(Scrollable).first;
      await t.drag(s, const Offset(0, -500));
      await pumpMs(300);
      if (find
          .byKey(const Key('calendar-google-connect'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    await shot('20-calendar-settings-google-row');

    // §1 · "הצג שוב את ההדרכה" in עזרה.
    await show(const HelpScreen());
    await shot('21-help-replay');
  });
}

Caps capsOfPreset(Preset p) => Caps.fromMe(Me.fromJson(meJson(p)));
