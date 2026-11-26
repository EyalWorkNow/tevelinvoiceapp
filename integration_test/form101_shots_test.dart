// 0134 "עובדים וטופס 101" screenshots with MOCKED data (the test FakeBackend,
// no server). Same SHOT: protocol as customer_page_shots_test:
//
//   U=<sim udid>; OUT=$PWD/docs/qa/2611-v5
//   ~/flutter/bin/flutter test integration_test/form101_shots_test.dart -d $U 2>&1 |
//   while IFS= read -r l; do echo "$l"; if [[ $l == *SHOT:* ]]; then
//     n=${l##*SHOT:}; xcrun simctl io $U screenshot "$OUT/$n.png" >/dev/null 2>&1; fi; done
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/api/form101_api.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/business/employees_screen.dart';
import 'package:invoice/screens/business/form101_screen.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/util/allowed_urls.dart';

import '../test/business/e_harness.dart';
import '../test/fakes/fake_api.dart';
import 'host_shot.dart';

late WidgetTester t;

Future<void> pumpMs(int ms) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  do {
    await t.pump(const Duration(milliseconds: 50));
  } while (DateTime.now().isBefore(end));
}

Future<void> shot(String name) async {
  await pumpMs(1200);
  await hostShot(name);
  await pumpMs(1300);
}

Future<void> tapKey(String key) async {
  final f = find.byKey(Key(key));
  for (var i = 0; i < 20 && f.evaluate().isEmpty; i++) {
    await pumpMs(150);
  }
  await t.ensureVisible(f.first);
  await pumpMs(300);
  await t.tap(f.first, warnIfMissed: false);
  await pumpMs(1200);
}

Map<String, dynamic> form(
  String id,
  String status,
  String employeeId,
  String name,
) => {
  'id': id,
  'employeeId': employeeId,
  'employeeName': name,
  'taxYear': 2026,
  'kind': 'ANNUAL',
  'status': status,
  'sentAt': '2026-11-20T08:00:00.000Z',
  'viewedAt': status == 'SENT' ? null : '2026-11-20T10:12:00.000Z',
  'completedAt': status == 'COMPLETED' ? '2026-11-21T09:04:00.000Z' : null,
  'expiresOn': '2026-12-04',
  'currentStep': status == 'VIEWED' ? 4 : 0,
};

Map<String, dynamic> emp(
  String id,
  String name,
  String phone, {
  Map<String, dynamic>? f,
  int? last,
}) => {
  'id': id,
  'fullName': name,
  'phone': phone,
  'email': null,
  'archived': false,
  'form101': f,
  'lastCompletedYear': last,
};

Map<String, dynamic> detail(String status) => {
  ...form('f1', status, 'e1', 'דנה לוי'),
  'employeePhone': '050-1234567',
  'employeeEmail': 'dana@example.com',
  'verifiedTo': 'טלפון 050-1234567',
  'completedSignerName': status == 'COMPLETED' ? 'דנה לוי' : null,
  'retainUntil': status == 'COMPLETED' ? '2033-11-21' : null,
  'prefilledFrom': null,
  'codePending': status != 'COMPLETED',
  'code': status != 'COMPLETED' ? '482913' : null,
  'events': [
    {
      'type': 'SENT',
      'occurredAt': '2026-11-20T08:00:00.000Z',
      'channel': 'WHATSAPP',
    },
    {
      'type': 'VIEWED',
      'occurredAt': '2026-11-20T10:12:00.000Z',
      'ip': '81.218.4.17',
    },
    {
      'type': 'VERIFIED',
      'occurredAt': '2026-11-20T10:13:00.000Z',
      'detail': 'טלפון 050-1234567',
      'ip': '81.218.4.17',
    },
    if (status == 'COMPLETED') ...[
      {
        'type': 'COMPLETED',
        'occurredAt': '2026-11-21T09:04:00.000Z',
        'detail': 'דנה לוי',
        'ip': '81.218.4.17',
      },
      {
        'type': 'PDF_VIEWED',
        'occurredAt': '2026-11-21T09:30:00.000Z',
        'actorName': 'נורה כהן',
      },
    ],
  ],
  'attachments': [
    if (status == 'COMPLETED') ...[
      {
        'id': 'a1',
        'kind': 'ID',
        'contentType': 'image/jpeg',
        'byteSize': 840000,
      },
      {
        'id': 'a2',
        'kind': 'DISCHARGE_CERT',
        'contentType': 'application/pdf',
        'byteSize': 120000,
      },
    ],
  ],
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('form 101 screens', (tester) async {
    t = tester;
    final backend = await eSetUp();
    urlOpener = (uri, {inApp = false}) async => true;
    form101Today = () => DateTime(2026, 11, 25);
    final employees = [
      emp(
        'e1',
        'דנה לוי',
        '050-1234567',
        f: form('f1', 'COMPLETED', 'e1', 'דנה לוי'),
      ),
      emp(
        'e2',
        'יוסי כהן',
        '052-7654321',
        f: form('f2', 'VIEWED', 'e2', 'יוסי כהן'),
      ),
      emp(
        'e3',
        'מיכל ברק',
        '054-1112233',
        f: form('f3', 'EXPIRED', 'e3', 'מיכל ברק'),
      ),
      emp('e4', 'אבי שרון', '053-9876543', last: 2025),
    ];
    backend
      ..on(
        'GET',
        '/employees',
        (_) => FakeResponse(200, {
          'taxYear': 2026,
          'items': employees,
          'renewable': 1,
        }),
      )
      ..on(
        'POST',
        '/form101',
        (_) => FakeResponse(201, {
          'url': 'https://invoice.crm.tevel.space/f/abc',
          'code': '482913',
          'emailed': false,
          'form101': detail('SENT'),
        }),
      )
      ..on(
        'POST',
        '/form101/season',
        (_) => FakeResponse(200, {
          'taxYear': 2026,
          'items': [
            {
              'employeeId': 'e4',
              'employeeName': 'אבי שרון',
              'phone': '053-9876543',
              'email': null,
              'channel': 'WHATSAPP',
              'url': 'https://invoice.crm.tevel.space/f/s4',
              'code': '771204',
              'emailed': false,
              'prefilled': true,
            },
            {
              'employeeId': 'e5',
              'employeeName': 'רונית גל',
              'phone': null,
              'email': 'ronit@example.com',
              'channel': 'EMAIL',
              'url': 'https://invoice.crm.tevel.space/f/s5',
              'code': '390125',
              'emailed': true,
              'prefilled': true,
            },
          ],
          'skipped': [],
        }),
      );
    await pumpAs(tester, backend, Preset.owner, const EmployeesScreen());
    await pumpMs(1500);
    await shot('01-employees-owner');

    await tapKey('employees-season-send');
    await shot('02-season-queue');
    navigatorKey.currentState!.maybePop();
    await pumpMs(900);

    await tapKey('employee-row-e4');
    await shot('03-employee-actions');
    await tapKey('employee-action-send');
    await shot('04-send-channels');
    await tapKey('form101-channel-whatsapp');
    await shot('05-code-sheet');
    navigatorKey.currentState!.maybePop();
    await pumpMs(900);

    loadForm101 = (id) async =>
        Form101Detail.fromJson(detail(id == 'f1' ? 'COMPLETED' : 'VIEWED'));
    await tapKey('employee-row-e1');
    await shot('06-form-signed');
    await t.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await pumpMs(800);
    await shot('07-form-signed-trail');
    navigatorKey.currentState!.maybePop();
    await pumpMs(900);
    await tapKey('employee-row-e2');
    await shot('08-form-open');
    navigatorKey.currentState!.popUntil((r) => r.isFirst);
    await pumpMs(900);

    await tapKey('employees-bottom');
    await shot('09-new-employee');
    navigatorKey.currentState!.maybePop();
    await pumpMs(900);

    // The accountant: read only.
    await pumpAs(
      tester,
      backend,
      Preset.accountantFull,
      const EmployeesScreen(),
    );
    await pumpMs(1500);
    await shot('10-employees-accountant');
  });
}
