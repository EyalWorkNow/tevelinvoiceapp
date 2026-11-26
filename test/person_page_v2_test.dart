// כרטיס לקוח v2 (owner spec 2026-11-23): quick-action order and the "עוד"
// sheet, the unified visits list (CRM jobs + calendar bookings), the status
// card states and what an employee sees.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/screens/calendar/calendar_api.dart';
import 'package:invoice/screens/debts/reminder_hold_tile.dart';
import 'package:invoice/screens/people/person_logic.dart';
import 'package:invoice/screens/people/person_screen.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/customer_crm_store.dart';
import 'package:invoice/ui/ds.dart';
import 'package:invoice/util/labels/person_page_he.dart';

import 'business/e_harness.dart';
import 'fakes/fake_api.dart';

PersonActionFacts _with({
  bool owes = false,
  bool hasPhone = true,
  bool hasEmail = true,
  bool manage = true,
  bool calendar = true,
  bool statement = true,
}) => PersonActionFacts(
  hasPhone: hasPhone,
  hasWhatsapp: hasPhone,
  hasEmail: hasEmail,
  hasAddress: true,
  owes: owes,
  canDraft: true,
  canPaymentIssue: true,
  canMoneyView: manage,
  canCalendar: calendar,
  canManage: manage,
  crmReady: true,
  canRepeat: true,
  statement: statement,
);

Booking _booking(String id, DateTime at, {String status = 'CONFIRMED'}) =>
    Booking(
      id: id,
      startsAt: at.toUtc(),
      endsAt: at.add(const Duration(minutes: 30)).toUtc(),
      status: status,
      clientName: 'דנה',
      clientPhone: '0501234567',
      clientEmail: '',
      sequence: 0,
      createdAt: DateTime(2026, 11, 1),
      customerId: 'c1',
    );

CustomerCrmJob _job(
  String id,
  DateTime at, {
  CustomerCrmJobStatus status = CustomerCrmJobStatus.scheduled,
}) => CustomerCrmJob(
  id: id,
  customerId: 'c1',
  customerName: 'דנה',
  title: 'עבודה $id',
  scheduledAt: at,
  createdAt: DateTime(2026, 11, 1),
  status: status,
);

DocumentSummary _doc(
  String id, {
  required String issue,
  String? due,
  int open = 0,
  int total = 10000,
}) => DocumentSummary.fromJson({
  'id': id,
  'documentType': 'TAX_INVOICE',
  'status': 'FINALIZED',
  'documentNumber': id,
  'issueDate': issue,
  'dueDate': due,
  'totalMinor': '$total',
  'openMinor': '$open',
  'balanceMinor': '$open',
});

void main() {
  group('quick actions', () {
    test('balance > 0: בקשת תשלום 3rd, חשבונית 6th, עוד 8th', () {
      expect(personRowActions(_with(owes: true)), [
        'call',
        'whatsapp',
        'payment-request',
        'book',
        'paid',
        'invoice',
        'reminder',
        'more',
      ]);
    });

    test('no balance: חשבונית 3rd, הצעת מחיר 6th', () {
      expect(personRowActions(_with()), [
        'call',
        'whatsapp',
        'invoice',
        'book',
        'paid',
        'quote',
        'reminder',
        'more',
      ]);
    });

    test('no phone and no e-mail: one "הוספת טלפון" orb instead of both', () {
      final row = personRowActions(_with(hasPhone: false, hasEmail: false));
      expect(row.first, 'add-phone');
      expect(row, isNot(contains('call')));
      expect(row, isNot(contains('whatsapp')));
    });

    test('an e-mail only: no call / WhatsApp orbs, אימייל first in עוד', () {
      final f = _with(hasPhone: false);
      final row = personRowActions(f);
      expect(row.take(2), ['invoice', 'book']);
      expect(personMoreActions(f, row).first, 'email');
    });

    test('a missing permission pulls the next action up', () {
      final row = personRowActions(_with(calendar: false));
      expect(row, [
        'call',
        'whatsapp',
        'invoice',
        'paid',
        'quote',
        'reminder',
        'more',
      ]);
    });

    test('employee (no customer.manage, no calendar): call / WhatsApp + '
        'documents only; no reminder, no add-phone', () {
      const f = PersonActionFacts(
        hasPhone: true,
        hasWhatsapp: true,
        canDraft: true,
        crmReady: true,
        canRepeat: true,
      );
      final row = personRowActions(f);
      expect(row, ['call', 'whatsapp', 'invoice', 'quote', 'more']);
      expect(personMoreActions(f, row), ['repeat']);
      expect(
        personRowActions(const PersonActionFacts()),
        isEmpty,
        reason: 'no "עוד" without anything inside',
      );
    });

    test('"עוד": fixed order, nothing from the row, ארכוב last', () {
      final row = personRowActions(_with(owes: true));
      expect(personMoreActions(_with(owes: true), row), [
        'email',
        'repeat',
        'debt',
        'job',
        'note',
        'navigate',
        'statement',
        'portal',
        'edit',
        'terms',
        'archive',
      ]);
      final viewer = _with(manage: false, statement: false);
      expect(
        personMoreActions(viewer, personRowActions(viewer)),
        isNot(contains('archive')),
      );
    });

    test('supplier: חיוג · וואטסאפ · הוצאה · אימייל · עוד', () {
      const f = PersonActionFacts(
        supplier: true,
        hasPhone: true,
        hasWhatsapp: true,
        hasEmail: true,
        canExpense: true,
        canManage: true,
      );
      final row = personRowActions(f);
      expect(row, ['call', 'whatsapp', 'expense', 'email', 'more']);
      expect(personMoreActions(f, row), ['edit', 'archive']);
    });
  });

  group('visits', () {
    final now = DateTime(2026, 11, 23, 12);

    test('jobs and bookings in one list by date; finished jobs and '
        'cancelled / past bookings left out', () {
      final items = upcomingVisits(
        [
          _job('late', DateTime(2026, 11, 22, 9)),
          _job('next-week', DateTime(2026, 11, 30, 9)),
          _job(
            'done',
            DateTime(2026, 11, 24, 9),
            status: CustomerCrmJobStatus.completed,
          ),
        ],
        [
          _booking('b-tomorrow', DateTime(2026, 11, 24, 10)),
          _booking('b-pending', DateTime(2026, 11, 26, 10), status: 'PENDING'),
          _booking(
            'b-cancelled',
            DateTime(2026, 11, 25, 10),
            status: 'CANCELLED',
          ),
          _booking('b-past', DateTime(2026, 11, 20, 10)),
        ],
        now,
      );
      expect(
        [for (final i in items) i.id],
        [
          'job-late',
          'booking-b-tomorrow',
          'booking-b-pending',
          'job-next-week',
        ],
      );
      expect(
        [for (final i in items) i.tag(now)],
        [
          PersonPageHe.tagOverdue,
          PersonPageHe.tagScheduled,
          PersonPageHe.tagPending,
          PersonPageHe.tagScheduled,
        ],
      );
    });

    test('next thing: a late follow-up first, else the nearest visit', () {
      final visits = upcomingVisits(
        [_job('a', DateTime(2026, 11, 25, 9, 30))],
        [_booking('b', DateTime(2026, 11, 24, 10))],
        now,
      );
      final late = CustomerCrmReminder(
        id: 'r',
        customerId: 'c1',
        customerName: 'דנה',
        title: 'לחזור לדנה',
        dueAt: DateTime(2026, 11, 22, 9),
      );
      expect(
        nextThing(visits, [late], now)!.text,
        'תזכורת: לחזור לדנה · באיחור',
      );
      final next = nextThing(visits, const [], now)!;
      expect(next.visit!.booking!.id, 'b');
      expect(next.text, 'פגישה · יום ג׳ 24.11 · 10:00');
      expect(nextThing(const [], const [], now), isNull);
    });

    test('dates read "יום ג׳ 25.11 · 09:30"', () {
      expect(whenLabel(DateTime(2026, 11, 25, 9, 30)), 'יום ד׳ 25.11 · 09:30');
      expect(dayWithWeekday(DateTime(2026, 11, 24)), 'יום ג׳ 24.11');
    });
  });

  group('status card lines', () {
    final now = DateTime(2026, 11, 23);
    String name(DocumentSummary d) => 'חשבונית ${d.documentNumber}';

    test('the oldest late document, with its days late', () {
      final line = oldestOpenDoc(
        [
          _doc('1050', issue: '2026-10-20', due: '2026-11-19', open: 500),
          _doc('1042', issue: '2026-10-10', due: '2026-11-11', open: 500),
          _doc('1060', issue: '2026-11-01', due: '2026-12-01', open: 500),
          _doc('1001', issue: '2026-09-01', due: '2026-10-01'),
        ],
        now,
        name,
      )!;
      expect(line.doc.id, '1042');
      expect(line.overdue, isTrue);
      expect(line.text, 'חשבונית 1042 באיחור 12 ימים');
    });

    test('nothing late: the oldest open one, with its due date', () {
      final line = oldestOpenDoc(
        [_doc('1060', issue: '2026-11-01', due: '2026-12-01', open: 500)],
        now,
        name,
      )!;
      expect(line.overdue, isFalse);
      expect(line.text, 'חשבונית 1060 · לתשלום עד 01.12');
    });

    test('documents list: open ones first, then the latest', () {
      final docs = docsForCard([
        _doc('old-paid', issue: '2026-09-01'),
        _doc('new-paid', issue: '2026-11-20'),
        _doc('open', issue: '2026-10-01', open: 100),
      ]);
      expect([for (final d in docs) d.id], ['open', 'new-paid', 'old-paid']);
    });
  });

  group('page', () {
    late FakeBackend b;

    setUp(() async {
      b = await eSetUp();
      loadReminderHold = ({customerId, documentId}) async => false;
    });

    Map<String, dynamic> crm(CustomerCrmEntry e) => {
      'total': 1,
      'records': [
        {'customerId': 'c1', 'revision': 1, 'record': e.toJson()},
      ],
    };

    Future<void> open(
      WidgetTester t,
      Preset p, {
      List<Map<String, dynamic>> docs = const [],
      String? lastDoc,
    }) async {
      installPeopleFakes(
        b,
        customers: [
          {
            ...customerJson('c1', 'דנה', phone: '050-1234567'),
            'lastDocumentAt': lastDoc,
          },
        ],
        documents: docs,
      );
      phone(t);
      await t.runAsync(() async {
        await signInAs(b, p);
        await CustomerCrmStore.instance.loadForBusiness('b1', force: true);
      });
      await t.pumpWidget(const SizedBox()); // a fresh State per open
      await t.pumpWidget(eApp(const PersonScreen(id: 'c1')));
      await settle(t);
    }

    Map<String, dynamic> docJson(String id, String issue, String due, int o) =>
        {
          'id': id,
          'documentType': 'TAX_INVOICE',
          'status': 'FINALIZED',
          'customerId': 'c1',
          'customerName': 'דנה',
          'documentNumber': id,
          'issueDate': issue,
          'dueDate': due,
          'totalMinor': '$o',
          'balanceMinor': '$o',
          'openMinor': '$o',
        };

    String ymdOf(DateTime d) => ymd(d);

    testWidgets('status: owes + the late document (warn) opens it', (t) async {
      final n = DateTime.now();
      await open(
        t,
        Preset.owner,
        docs: [
          docJson(
            '1042',
            ymdOf(n.subtract(const Duration(days: 40))),
            ymdOf(n.subtract(const Duration(days: 12))),
            59900,
          ),
        ],
      );
      expect(find.byKey(const Key('person-owes')), findsOneWidget);
      expect(find.textContaining('באיחור 12 ימים'), findsOneWidget);
      expect(find.byKey(const Key('person-status-doc')), findsOneWidget);
    });

    testWidgets('status: no balance → "אין יתרה פתוחה" + the last document '
        'age; a new customer → "עוד אין מסמכים"', (t) async {
      final n = DateTime.now();
      await open(
        t,
        Preset.owner,
        lastDoc: ymdOf(n.subtract(const Duration(days: 5))),
      );
      expect(find.text(PersonPageHe.noBalance), findsOneWidget);
      expect(find.text(PersonPageHe.lastDocAgo(5)), findsOneWidget);
      await open(t, Preset.owner);
      expect(find.text(PersonPageHe.noBalance), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('person-status')),
          matching: find.text(PersonPageHe.noDocsYet),
        ),
        findsOneWidget,
      );
    });

    testWidgets('one visits list (job + meeting) with the pinned note above '
        'the nearest; a late follow-up is the next thing; "עוד" sheet', (
      t,
    ) async {
      final n = DateTime.now();
      final job = DateTime(n.year, n.month, n.day + 3, 9, 30);
      final meet = DateTime(n.year, n.month, n.day + 1, 11);
      b
        ..json(
          'GET',
          '/crm/customers',
          crm(
            CustomerCrmEntry(
              notes: [
                CustomerCrmNote(
                  id: 'n1',
                  text: 'קוד לשער 4590',
                  pinned: true,
                  createdAt: DateTime(2026, 11, 1),
                ),
              ],
              reminders: [
                CustomerCrmReminder(
                  id: 'r1',
                  customerId: 'c1',
                  customerName: 'דנה',
                  title: 'לחזור לדנה',
                  dueAt: n.subtract(const Duration(days: 1)),
                ),
              ],
              jobs: [_job('j1', job)],
            ),
          ),
        )
        ..json('GET', '/calendar/agenda', {
          'enabled': true,
          'busy': <Object>[],
          'bookings': [
            {
              'id': 'bk1',
              'startsAt': meet.toUtc().toIso8601String(),
              'endsAt': meet
                  .add(const Duration(minutes: 30))
                  .toUtc()
                  .toIso8601String(),
              'status': 'CONFIRMED',
              'clientName': 'דנה',
              'clientPhone': '0501234567',
              'clientEmail': '',
              'createdAt': '2026-11-01T10:00:00Z',
              'customerId': 'c1',
            },
            {
              'id': 'bk-other',
              'startsAt': meet.toUtc().toIso8601String(),
              'endsAt': meet
                  .add(const Duration(minutes: 30))
                  .toUtc()
                  .toIso8601String(),
              'status': 'CONFIRMED',
              'createdAt': '2026-11-01T10:00:00Z',
              'customerId': 'c2',
            },
          ],
        });
      await open(t, Preset.owner);
      expect(
        find.descendant(
          of: find.byKey(const Key('person-next')),
          matching: find.text('תזכורת: לחזור לדנה · באיחור'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('person-action-reminder')), findsOneWidget);
      final list = find.descendant(
        of: find.byKey(const Key('person-list')),
        matching: find.byType(Scrollable),
      );
      await t.scrollUntilVisible(
        find.byKey(const Key('person-visit-job-j1')),
        200,
        scrollable: list.first,
      );
      final meetRow = t.getRect(
        find.byKey(const Key('person-visit-booking-bk1')),
      );
      final jobRow = t.getRect(find.byKey(const Key('person-visit-job-j1')));
      final pin = t.getRect(find.byKey(const ValueKey('crm-pinned-n1')));
      expect(pin.top, lessThan(meetRow.top));
      expect(meetRow.top, lessThan(jobRow.top));
      expect(
        find.byKey(const Key('person-visit-booking-bk-other')),
        findsNothing,
      );
      // "עוד": the rest, in order, "ארכוב" last.
      await t.tap(find.byKey(const Key('person-action-more')));
      await settle(t);
      final ids = [
        for (final w in t.widgetList<ListTile>(
          find.descendant(
            of: find.byKey(const Key('person-more-sheet')),
            matching: find.byType(ListTile),
          ),
        ))
          (w.key! as ValueKey<String>).value.substring('person-more-'.length),
      ];
      expect(ids, ['debt', 'job', 'note', 'edit', 'terms', 'archive']);
    });

    testWidgets('employee: a CRM the server refuses (403) hides the visits '
        'quietly; no money, no ⋯', (t) async {
      b.error('GET', '/crm/customers', 403, 'FORBIDDEN');
      await open(t, Preset.employee);
      expect(find.text(PersonPageHe.visits), findsNothing);
      expect(find.text(PersonPageHe.notes), findsNothing);
      expect(find.byKey(const Key('person-owes')), findsNothing);
      expect(find.text(PersonPageHe.documents), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MoreMenu),
          matching: find.byType(IconButton),
        ),
        findsNothing,
      );
      expect(find.byKey(const Key('person-action-call')), findsOneWidget);
      expect(find.byKey(const Key('person-action-whatsapp')), findsOneWidget);
    });

    testWidgets('employee: a readable CRM shows the visits read-only', (
      t,
    ) async {
      final n = DateTime.now();
      b.json(
        'GET',
        '/crm/customers',
        crm(
          CustomerCrmEntry(
            jobs: [_job('j1', DateTime(n.year, n.month, n.day + 2, 9))],
          ),
        ),
      );
      await open(t, Preset.employee);
      final row = find.byKey(const Key('person-visit-job-j1'));
      await t.scrollUntilVisible(
        row,
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('person-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(t.widget<InkWell>(row).onTap, isNull);
      expect(find.byKey(const Key('person-action-reminder')), findsNothing);
    });
  });
}
