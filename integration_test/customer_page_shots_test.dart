// Customer page (כרטיס לקוח) audit shots, 2026-11-23, with MOCKED data (the
// test FakeBackend, no server). Prints SHOT: markers (same protocol as
// accountant_shots_test):
//
//   U=<sim udid>; OUT=$PWD/docs/qa/customer-page-2026-11-23/after
//   ~/flutter/bin/flutter test integration_test/customer_page_shots_test.dart -d $U 2>&1 |
//   while IFS= read -r l; do echo "$l"; if [[ $l == *SHOT:* ]]; then
//     n=${l##*SHOT:}; xcrun simctl io $U screenshot "$OUT/$n.png" >/dev/null 2>&1; fi; done
//
// Also prints AUDIT: lines (what the harness found while tapping).
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/debts/reminder_hold_tile.dart';
import 'package:invoice/screens/people/person_screen.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/customer_crm_store.dart';
import 'package:invoice/state/customer_crm_job_budget.dart';
import 'package:invoice/ui/ds.dart' show MoreMenu;

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
  if (f.evaluate().isEmpty && find.byType(Scrollable).evaluate().isNotEmpty) {
    // Lazily built list rows: scroll the page until the row exists.
    try {
      await t.scrollUntilVisible(
        f,
        300,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 30,
      );
      await pumpMs(400);
    } on Object {
      // reported below
    }
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

Future<void> back() async {
  navigatorKey.currentState!.maybePop();
  await pumpMs(900);
}

Future<void> closeAll() async {
  navigatorKey.currentState!.popUntil((r) => r.isFirst);
  await pumpMs(900);
}

/// Drags the page's list up by [dy]; false when it no longer moves.
Future<bool> scrollDown({double dy = 520}) async {
  final s = find.byType(Scrollable).first;
  final pos = t.state<ScrollableState>(s).position;
  final before = pos.pixels;
  // At the end already (the drag would only bounce): no new page.
  if (before >= pos.maxScrollExtent - 1) return false;
  await t.drag(s, Offset(0, -dy));
  await pumpMs(700);
  return t.state<ScrollableState>(s).position.pixels > before + 2;
}

Future<void> scrollTop() async {
  final st = t.state<ScrollableState>(find.byType(Scrollable).first);
  st.position.jumpTo(0);
  await pumpMs(500);
}

String day(int offset) {
  final d = DateTime.now().add(Duration(days: offset));
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

String iso(int dayOffset, int hour, [int minute = 0]) {
  final n = DateTime.now();
  return DateTime(
    n.year,
    n.month,
    n.day + dayOffset,
    hour,
    minute,
  ).toUtc().toIso8601String();
}

// ── data ──────────────────────────────────────────────────────────────────

Map<String, dynamic> customer(
  String id,
  String name, {
  String? phone,
  String? email,
  String open = '0',
  String overdue = '0',
  String? last,
  String? terms,
  int docs = 0,
}) => {
  'customer': {
    'id': id,
    'name': name,
    'tax_id': null,
    'email': email,
    'phone': phone,
    'archived_at': null,
    'vat_dealer_status': 'PRIVATE',
    'customer_type': 'INDIVIDUAL',
    'address': phone == null
        ? null
        : {
            'street': 'הנרקיסים',
            'number': '14',
            'city': 'רמת השרון',
            'postalCode': '4724114',
          },
    'contactPerson': null,
    'paymentTerms': terms,
    'paymentTermsDays': null,
    'preferredPaymentMethod': terms == null ? null : 'BANK_TRANSFER',
    'effectivePaymentTerms': terms == null
        ? {'code': 'IMMEDIATE', 'days': null, 'source': 'BUSINESS'}
        : {
            'code': terms,
            'days': null,
            'preferredPaymentMethod': 'BANK_TRANSFER',
            'source': 'CUSTOMER',
          },
    'notes': null,
    'accountKey': null,
    'balanceMinor': open,
    'lastDocumentAt': last,
    'isWalkIn': false,
    'consent': {'granted': true, 'method': 'VERBAL_IN_APP', 'at': iso(-90, 10)},
  },
  'stats': {
    'openMinor': open,
    'overdueMinor': overdue,
    'creditMinor': '0',
    'documentsCount': docs,
    'lastDocumentAt': last,
  },
};

Map<String, dynamic> listRow(
  String id,
  String name, {
  String? phone,
  String? email,
  String balance = '0',
}) => {
  'id': id,
  'name': name,
  'tax_id': null,
  'email': email,
  'phone': phone,
  'archived_at': null,
  'vat_dealer_status': 'PRIVATE',
  'customer_type': 'INDIVIDUAL',
  'balanceMinor': balance,
  'creditMinor': '0',
  'lastDocumentAt': null,
  'isWalkIn': false,
  'consent': {'granted': true},
};

List<Map<String, dynamic>> danielDocs() => [
  {
    'id': 'd-open',
    'documentType': 'TAX_INVOICE',
    'status': 'FINALIZED',
    'customerId': 'c1',
    'customerName': 'דניאל רוזן',
    'documentNumber': '1057',
    'issueDate': day(-48),
    'dueDate': day(-18),
    'totalMinor': '284000',
    'balanceMinor': '284000',
    'openMinor': '284000',
    'creditedMinor': '0',
    'sentAt': iso(-48, 9),
  },
  {
    'id': 'd-credit',
    'documentType': 'CREDIT_DOCUMENT',
    'status': 'FINALIZED',
    'customerId': 'c1',
    'customerName': 'דניאל רוזן',
    'documentNumber': '1061',
    'issueDate': day(-30),
    'totalMinor': '35000',
    'openMinor': '0',
  },
  {
    'id': 'd-paid',
    'documentType': 'TAX_INVOICE',
    'status': 'FINALIZED',
    'customerId': 'c1',
    'customerName': 'דניאל רוזן',
    'documentNumber': '1034',
    'issueDate': day(-75),
    'dueDate': day(-45),
    'totalMinor': '196000',
    'balanceMinor': '0',
    'openMinor': '0',
    'creditedMinor': '0',
    'sentAt': iso(-75, 9),
  },
  {
    'id': 'd-receipt',
    'documentType': 'RECEIPT',
    'status': 'FINALIZED',
    'customerId': 'c1',
    'customerName': 'דניאל רוזן',
    'documentNumber': '2210',
    'issueDate': day(-60),
    'totalMinor': '196000',
  },
  // A quote is its own object (/quotes): the server never lists it in
  // GET /documents, so the card shows 4 rows; the quote is in the timeline.
];

CustomerCrmEntry danielCrm() {
  final now = DateTime.now();
  DateTime at(int d, int h, [int m = 0]) =>
      DateTime(now.year, now.month, now.day + d, h, m);
  return CustomerCrmEntry(
    stage: CustomerCrmStage.orderApproved,
    notes: [
      CustomerCrmNote(
        id: 'n1',
        text: 'קוד לשער 4590#. כלב בחצר — להתקשר לפני שנכנסים.',
        pinned: true,
        createdAt: at(-20, 18, 12),
      ),
      CustomerCrmNote(
        id: 'n2',
        text: 'מעדיף הודעות בוואטסאפ ולא שיחות בשעות העבודה.',
        createdAt: at(-6, 11, 40),
      ),
    ],
    reminders: [
      CustomerCrmReminder(
        id: 'r1',
        customerId: 'c1',
        customerName: 'דניאל רוזן',
        title: 'לחזור לדניאל לגבי התשלום על חשבונית 1057',
        dueAt: at(-2, 9),
      ),
      CustomerCrmReminder(
        id: 'r2',
        customerId: 'c1',
        customerName: 'דניאל רוזן',
        title: 'לשלוח הצעת מחיר לפרגולה',
        dueAt: at(3, 10),
      ),
    ],
    jobs: [
      CustomerCrmJob(
        id: 'j1',
        customerId: 'c1',
        customerName: 'דניאל רוזן',
        title: 'החלפת ברז במטבח ובדיקת נזילה',
        address: 'הנרקיסים 14, רמת השרון',
        details: 'הברז הישן מטפטף. ללקוח יש ברז חדש בקופסה.',
        scheduledAt: at(2, 9, 30),
        createdAt: at(-4, 12),
        budget: CustomerCrmJobBudget(
          priceMinor: 65000,
          costMinor: 12000,
          workMinutes: 90,
          paidMinor: 20000,
          paymentDueAt: at(2, 0),
        ),
        checklist: const [
          CustomerCrmChecklistItem(id: 'k1', text: 'לקנות אטמים', done: true),
          CustomerCrmChecklistItem(id: 'k2', text: 'לסגור ברז ראשי'),
          CustomerCrmChecklistItem(id: 'k3', text: 'לצלם לפני ואחרי'),
        ],
      ),
      CustomerCrmJob(
        id: 'j2',
        customerId: 'c1',
        customerName: 'דניאל רוזן',
        title: 'תחזוקת מזגן תקופתית',
        address: 'הנרקיסים 14, רמת השרון',
        scheduledAt: at(16, 14),
        createdAt: at(-4, 12),
        repeatEveryDays: 90,
        budget: const CustomerCrmJobBudget(priceMinor: 35000),
      ),
      CustomerCrmJob(
        id: 'j3',
        customerId: 'c1',
        customerName: 'דניאל רוזן',
        title: 'התקנת גוף תאורה בסלון',
        address: 'הנרקיסים 14, רמת השרון',
        scheduledAt: at(-30, 10),
        createdAt: at(-35, 12),
        status: CustomerCrmJobStatus.completed,
        budget: CustomerCrmJobBudget(
          priceMinor: 48000,
          costMinor: 9000,
          workMinutes: 60,
          paidMinor: 0,
          paymentDueAt: at(-10, 0),
        ),
      ),
    ],
  );
}

/// Free times of [date] (09:00–16:30 every 30 min, minus a "busy" pattern
/// so days differ); Fridays short, Saturdays closed, one full day.
List<Map<String, dynamic>> daySlots(DateTime date) {
  final out = <Map<String, dynamic>>[];
  if (date.weekday == DateTime.saturday) return out;
  final end = date.weekday == DateTime.friday ? 13 : 17;
  var d = DateTime(date.year, date.month, date.day, 9);
  var i = 0;
  while (d.hour < end) {
    final e = d.add(const Duration(minutes: 30));
    if ((i + date.day) % 3 != 0) {
      out.add({
        'start': d.toUtc().toIso8601String(),
        'end': e.toUtc().toIso8601String(),
        'date':
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
        'time':
            '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
      });
    }
    d = e;
    i++;
  }
  return out;
}

String ymdOf(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The horizon: tomorrow .. +20 days; day +4 is fully booked.
List<DateTime> horizon() {
  final n = DateTime.now();
  return [
    for (var i = 1; i <= 20; i++)
      if (i != 4) DateTime(n.year, n.month, n.day + i),
  ];
}

FakeResponse freeSlots(FakeRequest r, bool on) {
  if (!on) {
    return const FakeResponse(200, {'enabled': false, 'slots': [], 'days': []});
  }
  final days = [
    for (final d in horizon())
      if (daySlots(d).isNotEmpty) d,
  ];
  final date = r.query['date'];
  final slots = date == null
      ? daySlots(days.first).take(12).toList()
      : daySlots(DateTime.parse(date));
  return FakeResponse(200, {
    'enabled': true,
    'slots': slots,
    'days': [
      for (final d in days) {'date': ymdOf(d), 'count': daySlots(d).length},
    ],
  });
}

Map<String, dynamic> agendaJson() {
  final n = DateTime.now();
  Map<String, dynamic> bk(
    String id,
    DateTime at,
    String status,
    String cid,
  ) => {
    'id': id,
    'startsAt': at.toUtc().toIso8601String(),
    'endsAt': at.add(const Duration(minutes: 30)).toUtc().toIso8601String(),
    'status': status,
    'clientName': cid == 'c1' ? 'דניאל רוזן' : 'אחר',
    'clientPhone': '0524718830',
    'clientEmail': 'daniel.rosen@gmail.com',
    'sequence': 0,
    'createdAt': DateTime(n.year, n.month, n.day - 3).toUtc().toIso8601String(),
    'notes': id == 'bk1' ? 'פגישת תכנון לפרגולה' : null,
    'customerId': cid,
  };
  return {
    'enabled': true,
    'busy': <Object>[],
    'bookings': [
      bk('bk1', DateTime(n.year, n.month, n.day + 1, 11), 'CONFIRMED', 'c1'),
      bk('bk2', DateTime(n.year, n.month, n.day + 6, 16), 'PENDING', 'c1'),
      bk('bk3', DateTime(n.year, n.month, n.day + 1, 13), 'CONFIRMED', 'c9'),
    ],
  };
}

Map<String, dynamic> tl(
  String id,
  String kind,
  int dayOffset,
  int hour, {
  String? amount,
  Map<String, dynamic> data = const {},
  String? linkType,
  String? linkId,
  String? actor,
  bool mine = false,
}) {
  final n = DateTime.now();
  final d = DateTime(n.year, n.month, n.day + dayOffset, hour, 5);
  final israel =
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:05';
  return {
    'id': id,
    'kind': kind,
    'at': d.toUtc().toIso8601String(),
    'atIsrael': israel,
    'amountMinor': amount,
    'actor': actor == null ? null : {'id': 'u-x', 'name': actor},
    'link': linkType == null ? null : {'type': linkType, 'id': linkId},
    'mine': mine,
    'data': data,
  };
}

FakeBackend backendFor({bool calendarOn = true}) {
  final b = FakeBackend()..install();
  installBusinessFakes(b);
  installPeopleFakes(
    b,
    customers: [
      listRow(
        'c1',
        'דניאל רוזן',
        phone: '052-4718830',
        email: 'daniel.rosen@gmail.com',
        balance: '284000',
      ),
      listRow('c2', 'משה לוי'),
    ],
    suppliers: [
      {
        'id': 's1',
        'name': 'חומרי בניין הגליל',
        'tax_id': '514789632',
        'email': 'orders@galil-build.co.il',
        'phone': '04-6981234',
        'archived_at': null,
      },
    ],
    documents: danielDocs(),
    be16: true,
    be17: true,
  );
  final entry = danielCrm();
  b
    ..json(
      'GET',
      '/customers/c1',
      customer(
        'c1',
        'דניאל רוזן',
        phone: '052-4718830',
        email: 'daniel.rosen@gmail.com',
        open: '284000',
        overdue: '284000',
        last: day(-30),
        terms: 'EOM_30',
        docs: 4,
      ),
    )
    ..json('GET', '/customers/c2', customer('c2', 'משה לוי'))
    ..json('GET', '/crm/customers', {
      'total': 1,
      'records': [
        {'customerId': 'c1', 'revision': 3, 'record': entry.toJson()},
      ],
    })
    ..on(
      'PUT',
      '/crm/customers/:id',
      (r) => FakeResponse(200, {
        'customerId': r.params['id'],
        'revision': 4,
        'record': r.body['record'],
      }),
    )
    ..json('GET', '/settings/payment-terms', {
      'paymentTerms': 'IMMEDIATE',
      'paymentTermsDays': null,
      'preferredPaymentMethod': null,
    })
    ..on('GET', '/calendar/free-slots', (r) => freeSlots(r, calendarOn))
    ..json('GET', '/calendar/agenda', agendaJson())
    ..json('GET', '/calendar/settings', {
      'settings': {
        'enabled': calendarOn,
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
    ..json('GET', '/customers/:id/timeline', {
      'nextCursor': null,
      'sources': [
        'documents',
        'quotes',
        'payments',
        'debts',
        'reminders',
        'notes',
        'calendar',
      ],
      'items': [
        tl(
          't1',
          'note',
          -1,
          16,
          data: {
            'body': 'דיבר איתי, ישלם עד סוף החודש.',
            'source': 'customerCard',
          },
          actor: 'אייל',
          mine: true,
          linkType: 'customerNote',
          linkId: 'cn1',
        ),
        tl(
          't2',
          'reminder.sent',
          -5,
          9,
          data: {
            'channel': 'WHATSAPP',
            'documentNumber': '1057',
            'documentType': 'TAX_INVOICE',
          },
        ),
        tl(
          't3',
          'quote.sent',
          -9,
          12,
          amount: '1250000',
          data: {'quoteNumber': '88', 'channel': 'WHATSAPP'},
          linkType: 'quote',
          linkId: 'q88',
        ),
        tl(
          't4',
          'document.issued',
          -30,
          10,
          amount: '35000',
          data: {'documentType': 'CREDIT_DOCUMENT', 'documentNumber': '1061'},
          linkType: 'document',
          linkId: 'd-credit',
        ),
        tl(
          't5',
          'document.sent',
          -48,
          9,
          amount: '284000',
          data: {
            'documentType': 'TAX_INVOICE',
            'documentNumber': '1057',
            'channel': 'EMAIL',
          },
          linkType: 'document',
          linkId: 'd-open',
        ),
        tl(
          't6',
          'payment.recorded',
          -60,
          13,
          amount: '196000',
          data: {'method': 'BANK_TRANSFER'},
        ),
        tl(
          't7',
          'calendar.booked',
          -70,
          8,
          data: {'startsAtIsrael': '${day(-68)} 09:00'},
        ),
      ],
    });
  return b;
}

Future<void> openCard(
  Preset p,
  String id, {
  bool supplier = false,
  Brightness brightness = Brightness.light,
  bool calendarOn = true,
}) async {
  final b = backendFor(calendarOn: calendarOn);
  await signInAs(b, p);
  await CustomerCrmStore.instance.loadForBusiness('b1', force: true);
  // A fresh State per card (PersonScreen has no didUpdateWidget).
  await t.pumpWidget(const SizedBox());
  await pumpMs(200);
  await t.pumpWidget(
    eApp(
      PersonScreen(id: id, isSupplier: supplier),
      brightness: brightness,
    ),
  );
  await pumpMs(2500);
}

Future<void> openMore() async {
  await tapIf(find.byKey(const Key('person-action-more')));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('customer page shots', (tester) async {
    t = tester;
    await eSetUp();
    loadReminderHold = ({customerId, documentId}) async => false;

    // 1 · the full owner card, top → bottom.
    await openCard(Preset.owner, 'c1');
    await shot('01-owner-top');
    var i = 2;
    while (i < 12 && await scrollDown()) {
      await shot('${i.toString().padLeft(2, '0')}-owner-scroll');
      i++;
    }
    audit('owner card scroll pages: ${i - 1}');

    // Folded sections opened.
    if (await tapIf(find.byKey(const Key('person-money')))) {
      await t.ensureVisible(find.byKey(const Key('person-money')));
      await pumpMs(300);
      await shot('10-money-open');
    }
    if (await tapIf(find.byKey(const Key('person-details')))) {
      await scrollDown(dy: 900);
      await shot('11-details-open');
    }
    // payment terms (only from the details).
    if (await tapIf(find.byKey(const Key('person-terms')))) {
      await shot('50-payment-terms-sheet');
      await closeAll();
    }
    await scrollTop();

    // Stage menu.
    if (await tapIf(find.byKey(const Key('person-stage')))) {
      await shot('22-crm-stage-menu');
      await back();
    }

    // "הכל" of the visits → the full page + a job's ⋯ menu.
    if (await tapIf(find.byKey(const Key('person-visits-all')), waitMs: 1500)) {
      await shot('20-visits-all');
      final jobMenu = find.byKey(const ValueKey('crm-job-menu-j1'));
      if (await tapIf(jobMenu)) {
        await shot('23-crm-job-menu');
        await back();
      }
      await closeAll();
    }
    await openCard(Preset.owner, 'c1');

    // A meeting row → its card.
    if (await tapIf(find.byKey(const Key('person-visit-booking-bk1')))) {
      await shot('21-booking-detail');
      await closeAll();
    }
    await scrollTop();

    // 3 · "עוד" sheet + ⋯ menu.
    await openMore();
    await shot('30-more-sheet');
    await closeAll();
    if (await tapIf(
      find.descendant(
        of: find.byType(MoreMenu),
        matching: find.byType(IconButton),
      ),
    )) {
      await shot('31-header-menu');
      await back();
    }

    // "תזכורת לעצמי".
    if (await tapIf(find.byKey(const Key('person-action-reminder')))) {
      await shot('32-quick-reminder');
      await closeAll();
    }

    // 4 · פרטים ועריכה (from "עוד").
    await openMore();
    if (await tapIf(find.byKey(const Key('person-more-edit')))) {
      await shot('40-details-edit-sheet');
      await closeAll();
    }

    // 6 · קביעת פגישה.
    if (await tapIf(
      find.byKey(const Key('person-action-book')),
      waitMs: 2500,
    )) {
      await shot('60-book-suggest');
      await tapIf(find.byKey(const Key('customer-slot-0')), waitMs: 400);
      await tapIf(find.byKey(const Key('customer-slot-3')), waitMs: 400);
      // A later day: the strip scrolls, its own times load.
      final later = find.byKey(Key('customer-day-${ymdOf(horizon()[7])}'));
      if (later.evaluate().isNotEmpty) {
        await t.ensureVisible(later);
        await pumpMs(300);
      }
      await tapIf(later, waitMs: 1500);
      await tapIf(find.byKey(const Key('customer-slot-2')), waitMs: 400);
      await shot('61-book-suggest-3-picked-later-day');
      await tapIf(find.text('קביעה בשמו'));
      await tapIf(find.byKey(const Key('customer-slot-1')), waitMs: 400);
      await shot('63-book-for-them');
      if (await scrollDown(dy: 400)) await shot('63b-book-for-them-notes');
      await tapIf(find.text('קישור ליומן'));
      await shot('62-book-link');
      await closeAll();
    }

    // 7 · statement confirm (⋯).
    if (await tapIf(
      find.descendant(
        of: find.byType(MoreMenu),
        matching: find.byType(IconButton),
      ),
    )) {
      if (await tapIf(find.text('שליחת כרטסת'))) {
        await shot('70-statement-confirm');
      }
      await closeAll();
    }

    // 8 · timeline ("הכל" of the documents).
    if (await tapIf(find.byKey(const Key('person-timeline')), waitMs: 2000)) {
      await shot('80-timeline');
      await closeAll();
    }

    audit(
      'bottom bar gone: ${find.byKey(const Key('person-primary')).evaluate().isEmpty}',
    );

    // 9 · calendar switched off.
    await openCard(Preset.owner, 'c1', calendarOn: false);
    if (await tapIf(
      find.byKey(const Key('person-action-book')),
      waitMs: 2500,
    )) {
      await shot('64-book-calendar-off');
      await closeAll();
    }

    // 10 · employee (no customer.manage, no money.view).
    await openCard(Preset.employee, 'c1');
    await shot('90-employee-top');
    if (await scrollDown()) await shot('91-employee-scroll');

    // 10b · office manager (money.view, no manage).
    await openCard(Preset.officeManager, 'c1');
    await shot('92-office-manager-top');

    // 11 · a customer without phone / e-mail.
    await openCard(Preset.owner, 'c2');
    await shot('93-no-contact-top');
    if (await scrollDown()) await shot('94-no-contact-scroll');

    // 12 · supplier card.
    await openCard(Preset.owner, 's1', supplier: true);
    await shot('95-supplier');
    if (await tapIf(find.byKey(const Key('person-action-more')))) {
      await shot('96-supplier-more-sheet');
      await closeAll();
    }

    // 13 · dark mode.
    await openCard(Preset.owner, 'c1', brightness: Brightness.dark);
    await shot('97-dark-top');
    if (await scrollDown()) await shot('98-dark-scroll');
    await scrollTop();
    await openMore();
    await shot('99-dark-more-sheet');
    await closeAll();
  });
}
