// 0134 "עובדים וטופס 101" (spec §10): the employees list with the form state
// per tax year, add + send (WhatsApp, the code by SMS), the January one-tap
// re-send queue, the detail (signed PDF, send to the accountant, resend,
// cancel) and the owner-vs-accountant split.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/form101_api.dart';
import 'package:invoice/screens/business/employees_screen.dart';
import 'package:invoice/screens/business/form101_screen.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/util/allowed_urls.dart';
import 'package:invoice/util/labels/labels.dart';
import 'package:invoice/util/phone.dart';

import '../fakes/fake_api.dart';
import 'e_harness.dart';

Map<String, dynamic> _form(
  String id,
  String status, {
  String employeeId = 'e1',
  String name = 'דנה לוי',
  String kind = 'ANNUAL',
}) => {
  'id': id,
  'employeeId': employeeId,
  'employeeName': name,
  'taxYear': 2026,
  'kind': kind,
  'status': status,
  'sentAt': '2026-11-20T08:00:00.000Z',
  'viewedAt': null,
  'completedAt': status == 'COMPLETED' ? '2026-11-21T09:00:00.000Z' : null,
  'expiresOn': '2026-12-04',
  'currentStep': 3,
};

Map<String, dynamic> _employee(
  String id,
  String name, {
  Map<String, dynamic>? form,
  int? lastYear,
  String? email,
}) => {
  'id': id,
  'fullName': name,
  'phone': '050-1234567',
  'email': email,
  'archived': false,
  'form101': form,
  'lastCompletedYear': lastYear,
};

Map<String, dynamic> _detail(String status, {String? code}) => {
  ..._form('f1', status),
  'employeePhone': '050-1234567',
  'employeeEmail': null,
  'verifiedTo': status == 'COMPLETED' ? 'טלפון 050-1234567' : null,
  'completedSignerName': status == 'COMPLETED' ? 'דנה לוי' : null,
  'retainUntil': status == 'COMPLETED' ? '2033-11-21' : null,
  'prefilledFrom': null,
  'codePending': code != null,
  'code': code,
  'events': [
    {
      'type': 'SENT',
      'occurredAt': '2026-11-20T08:00:00.000Z',
      'channel': 'WHATSAPP',
    },
    {
      'type': 'VERIFIED',
      'occurredAt': '2026-11-21T08:50:00.000Z',
      'detail': 'טלפון 050-1234567',
      'ip': '1.2.3.4',
    },
    if (status == 'COMPLETED')
      {
        'type': 'COMPLETED',
        'occurredAt': '2026-11-21T09:00:00.000Z',
        'detail': 'דנה לוי',
      },
  ],
  'attachments': [
    if (status == 'COMPLETED')
      {'id': 'a1', 'kind': 'ID', 'contentType': 'image/jpeg', 'byteSize': 1000},
  ],
};

void main() {
  late FakeBackend backend;
  late FakeLauncher launcher;
  late List<Map<String, dynamic>> employees;
  late int renewable;

  setUp(() async {
    backend = await eSetUp();
    launcher = FakeLauncher()..install();
    addTearDown(FakeLauncher.uninstall);
    form101Today = () => DateTime(2026, 11, 25);
    employees = [
      _employee('e1', 'דנה לוי', form: _form('f1', 'COMPLETED')),
      _employee(
        'e2',
        'יוסי כהן',
        form: _form('f2', 'VIEWED', employeeId: 'e2', name: 'יוסי כהן'),
      ),
      _employee('e3', 'מיכל ברק', lastYear: 2025),
    ];
    renewable = 1;
    backend.on(
      'GET',
      '/employees',
      (_) => FakeResponse(200, {
        'taxYear': 2026,
        'items': employees,
        'renewable': renewable,
      }),
    );
  });

  testWidgets('list: one row per employee with the form state at the row end', (
    tester,
  ) async {
    await pumpAs(tester, backend, Preset.owner, const EmployeesScreen());
    await settle(tester);
    expect(
      find.text(Form101He.status(Form101Status.completed)),
      findsOneWidget,
    );
    expect(find.text(Form101He.status(Form101Status.viewed)), findsOneWidget);
    expect(find.text(Form101He.notSent), findsOneWidget);
    expect(
      find.textContaining(Form101He.lastYear(2025)),
      findsOneWidget,
      reason: 'phone · filled last year',
    );
    expect(find.byKey(const Key('employees-season')), findsOneWidget);
    expect(find.byKey(const Key('employees-bottom')), findsOneWidget);
    expect(
      backend.last('GET', '/employees')!.raw.url.queryParameters['taxYear'],
      '2026',
    );
    // The pill sits at the end of the row (RTL: the left edge).
    final row = tester.getRect(find.byKey(const Key('employee-row-e1')));
    final pill = tester.getRect(
      find.text(Form101He.status(Form101Status.completed)),
    );
    expect(pill.left - row.left, lessThan(40));
    await tester.scrollUntilVisible(
      find.byKey(const Key('employees-blank')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('employees-blank')), findsOneWidget);
  });

  testWidgets('the accountant reads only: no add, no season, no send', (
    tester,
  ) async {
    await pumpAs(
      tester,
      backend,
      Preset.accountantFull,
      const EmployeesScreen(),
    );
    await settle(tester);
    expect(find.text(Form101He.viewOnly), findsOneWidget);
    expect(find.byKey(const Key('employees-bottom')), findsNothing);
    expect(find.byKey(const Key('employees-season')), findsNothing);
    await tester.tap(find.byKey(const Key('employee-row-e3')));
    await settle(tester);
    expect(find.byKey(const Key('employee-action-send')), findsNothing);
  });

  testWidgets('add an employee → send by WhatsApp → the code goes by SMS', (
    tester,
  ) async {
    backend
      ..on('POST', '/employees', (r) {
        final e = _employee('e9', r.body['fullName'] as String);
        employees = [...employees, e];
        return FakeResponse(201, {'employee': e});
      })
      ..on(
        'POST',
        '/form101',
        (_) => FakeResponse(201, {
          'url': 'https://invoice.test/f/tok',
          'code': '482913',
          'emailed': false,
          'form101': _detail('SENT', code: '482913'),
        }),
      );
    await pumpAs(tester, backend, Preset.owner, const EmployeesScreen());
    await settle(tester);
    await tester.tap(find.byKey(const Key('employees-bottom')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('employee-save')));
    await settle(tester);
    expect(find.text(Form101He.nameRequired), findsOneWidget);
    await tester.enterText(find.byKey(const Key('employee-name')), 'רון אבן');
    await tester.enterText(
      find.byKey(const Key('employee-phone')),
      '052-7654321',
    );
    await tester.tap(find.byKey(const Key('employee-save')));
    await settle(tester);
    expect(backend.last('POST', '/employees')!.body['phone'], '052-7654321');
    await tester.tap(find.byKey(const Key('form101-channel-whatsapp')));
    await settle(tester);
    final send = backend.last('POST', '/form101')!.body;
    expect(send, {
      'employeeId': 'e9',
      'taxYear': 2026,
      'kind': 'ANNUAL',
      'channel': 'WHATSAPP',
    });
    final wa = launcher.opened.single;
    expect(wa.host, 'wa.me');
    expect(wa.queryParameters['text'], contains('https://invoice.test/f/tok'));
    expect(wa.queryParameters['text'], isNot(contains('482913')));
    expect(find.text('4 8 2 9 1 3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('form101-code-sms')));
    await settle(tester);
    expect(launcher.last!.scheme, 'sms');
    expect(launcher.last.toString(), contains('482913'));
  });

  testWidgets(
    'January: one tap creates every form; the queue opens WhatsApp per employee',
    (tester) async {
      backend.on(
        'POST',
        '/form101/season',
        (_) => FakeResponse(200, {
          'taxYear': 2026,
          'items': [
            {
              'employeeId': 'e3',
              'employeeName': 'מיכל ברק',
              'phone': '050-1234567',
              'email': null,
              'channel': 'WHATSAPP',
              'url': 'https://invoice.test/f/s3',
              'code': '111222',
              'emailed': false,
              'prefilled': true,
            },
            {
              'employeeId': 'e4',
              'employeeName': 'אבי לוי',
              'phone': null,
              'email': 'a@example.test',
              'channel': 'EMAIL',
              'url': 'https://invoice.test/f/s4',
              'code': '333444',
              'emailed': true,
              'prefilled': true,
            },
          ],
          'skipped': [],
        }),
      );
      await pumpAs(tester, backend, Preset.owner, const EmployeesScreen());
      await settle(tester);
      await tester.tap(find.byKey(const Key('employees-season-send')));
      await settle(tester);
      expect(backend.last('POST', '/form101/season')!.body['taxYear'], 2026);
      expect(find.text(Form101He.seasonEmailed), findsOneWidget);
      await tester.tap(find.byKey(const Key('season-send-e3')));
      await settle(tester);
      expect(launcher.opened.single.queryParameters['text'], contains('/f/s3'));
      expect(find.text('1 1 1 2 2 2'), findsOneWidget);
    },
  );

  testWidgets(
    'signed form: view, send to the accountant in one tap, the trail',
    (tester) async {
      loadForm101 = (_) async => Form101Detail.fromJson(_detail('COMPLETED'));
      addTearDown(() => loadForm101 = fetchForm101);
      backend.json('POST', '/form101/:id/send-to-accountant', {
        'sentTo': 'cpa@example.test',
      });
      await pumpAs(
        tester,
        backend,
        Preset.owner,
        const Form101Screen(id: 'f1'),
      );
      await settle(tester);
      expect(find.byKey(const Key('form101-view')), findsOneWidget);
      expect(find.byKey(const Key('form101-update')), findsOneWidget);
      expect(find.byKey(const Key('form101-resend')), findsNothing);
      expect(find.byKey(const Key('form101-event-VERIFIED')), findsOneWidget);
      expect(find.textContaining('IP 1.2.3.4'), findsOneWidget);
      await tester.tap(find.byKey(const Key('form101-accountant')));
      await settle(tester);
      expect(
        backend.last('POST', '/form101/:id/send-to-accountant')!.params['id'],
        'f1',
      );
      expect(
        find.text(Form101He.sentToAccountant('cpa@example.test')),
        findsOneWidget,
      );
    },
  );

  testWidgets('open form: resend (new link + code) and cancel', (tester) async {
    loadForm101 = (_) async => Form101Detail.fromJson(_detail('VIEWED'));
    addTearDown(() => loadForm101 = fetchForm101);
    backend
      ..on(
        'POST',
        '/form101/:id/resend',
        (_) => FakeResponse(200, {
          'url': 'https://invoice.test/f/new',
          'code': '555666',
          'emailed': false,
          'form101': _detail('SENT', code: '555666'),
        }),
      )
      ..json('POST', '/form101/:id/cancel', {'form101': _detail('CANCELLED')});
    await pumpAs(tester, backend, Preset.owner, const Form101Screen(id: 'f1'));
    await settle(tester);
    expect(find.byKey(const Key('form101-view')), findsNothing);
    await tester.tap(find.byKey(const Key('form101-resend')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('form101-resend-whatsapp')));
    await settle(tester);
    expect(
      backend.last('POST', '/form101/:id/resend')!.body['channel'],
      'WHATSAPP',
    );
    expect(launcher.opened.single.queryParameters['text'], contains('/f/new'));
    expect(find.text('5 5 5 6 6 6'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10)); // close the code sheet
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('form101-cancel')));
    await tester.tap(find.byKey(const Key('form101-cancel')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('form101-cancel-yes')));
    await settle(tester);
    expect(backend.last('POST', '/form101/:id/cancel'), isNotNull);
  });

  testWidgets('accountant on a signed form: view and share, nothing to send', (
    tester,
  ) async {
    loadForm101 = (_) async => Form101Detail.fromJson(_detail('COMPLETED'));
    addTearDown(() => loadForm101 = fetchForm101);
    await pumpAs(
      tester,
      backend,
      Preset.accountantRep,
      const Form101Screen(id: 'f1'),
    );
    await settle(tester);
    expect(find.byKey(const Key('form101-view')), findsOneWidget);
    expect(find.byKey(const Key('form101-share')), findsOneWidget);
    expect(find.byKey(const Key('form101-accountant')), findsNothing);
    expect(find.byKey(const Key('form101-update')), findsNothing);
  });

  group('logic', () {
    test('states and resend rules', () {
      Form101Summary s(String st) => Form101Summary.fromJson(_form('x', st));
      expect(s('SENT').canResend, isTrue);
      expect(s('EXPIRED').canResend, isTrue);
      expect(s('EXPIRED').open, isFalse);
      expect(s('COMPLETED').canResend, isFalse);
      expect(s('CANCELLED').status, Form101Status.cancelled);
      expect(form101StatusOf('nonsense'), Form101Status.sent);
      expect(Form101He.status(Form101Status.completed), 'הוחזר חתום');
      expect(Form101He.status(Form101Status.expired), 'פג תוקף');
    });

    test('the code SMS is an allowed launch with the body', () {
      final uri = smsUri(phone: waPhone('050-1234567')!, text: 'קוד 123');
      expect(isAllowedLaunch(uri), isTrue);
      expect(uri.toString(), startsWith('sms:+972501234567&body='));
    });
  });
}
