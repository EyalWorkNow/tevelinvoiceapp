import 'dart:async';

// Accountant multi-business (spec "רואה חשבון באפליקציית תבל", features 1-8;
// API: tevel-accountant-contract.md). HTTP mocked by the FakeBackend.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/accountant_api.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/api/models/models.dart' show PeriodKey;
import 'package:invoice/api/push_preferences_api.dart';
import 'package:invoice/app_shell.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/auth/access_request_screen.dart';
import 'package:invoice/screens/auth/auth_flow.dart';
import 'package:invoice/screens/business/account_page.dart';
import 'package:invoice/screens/business/accountant_clients_screen.dart';
import 'package:invoice/screens/business/business_screen.dart';
import 'package:invoice/screens/business/notification_preferences_screen.dart';
import 'package:invoice/screens/business/sheets/accountant_sheets.dart';
import 'package:invoice/screens/business/sheets/readiness_board.dart';
import 'package:invoice/screens/business/sheets/s14_switch.dart';
import 'package:invoice/screens/reports/reports_screen.dart';
import 'package:invoice/state/accountant_store.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/session.dart';
import 'package:invoice/state/system_notices.dart';
import 'package:invoice/util/labels/labels.dart';

import '../business/e_harness.dart';
import '../fakes/fake_api.dart';

const accessToken = 'access_token_abcdefghijklmnopqrstuvwxyz01';

Map<String, dynamic> client(
  String id, {
  int? readiness = 95,
  int expenses = 0,
  int payments = 0,
  int taxInvoices = 0,
  String? reviewed,
  String? phone,
}) => {
  'businessId': id,
  'legalName': 'עסק ${id.substring(1)}',
  'role': 'READ_ONLY',
  'readiness': readiness,
  'tasks': {
    'expensesToApprove': expenses,
    'paymentsWithoutReceipt': payments,
    'taxInvoicesDue': taxInvoices,
    'numberingGaps': 0,
    'correctionsAnswered': 0,
  },
  'openTasks': expenses + payments + taxInvoices,
  'lastReviewedPeriod': reviewed,
  'ownerPhone': phone,
};

Map<String, dynamic> clientsJson({
  bool isAccountant = true,
  String? office = 'משרד כהן',
  List<Map<String, dynamic>>? clients,
  List<Map<String, dynamic>> requests = const [],
}) => {
  'profile': {'isAccountant': isAccountant, 'officeName': office},
  'clients':
      clients ??
      [
        client('b1'),
        client(
          'b2',
          readiness: 60,
          payments: 2,
          taxInvoices: 1,
          phone: '0501234567',
        ),
        client('b3', readiness: 80),
      ],
  'requests': requests,
};

Map<String, dynamic> request(String id, String status) => {
  'id': id,
  'contact': 'owner$id@example.test',
  'role': 'ACCOUNTANT_REP',
  'status': status,
  'createdAt': '2026-11-20T10:00:00Z',
  'expiresAt': '2026-11-27T10:00:00Z',
};

/// R's period-review routes go before eSetUp's GET /reports/:kind → 404.
void servePeriodReview(FakeBackend b, List<Map<String, dynamic>> reviews) {
  b
    ..off('GET', '/reports/:kind')
    ..json('GET', '/reports/period-review', {'reviews': reviews})
    ..on(
      'POST',
      '/reports/period-review',
      (r) => FakeResponse(200, {
        'period': r.body['period'],
        'reviewedAt': '2026-11-22T09:00:00Z',
        'reviewedBy': 'u-me',
      }),
    )
    ..json('DELETE', '/reports/period-review', {'status': 'ok'})
    ..error('GET', '/reports/:kind', 404, 'NOT_FOUND');
}

void main() {
  late FakeBackend backend;
  late FakeLauncher launcher;

  setUp(() async {
    backend = await eSetUp();
    accountantStore.reset();
    accountantFocusTodo.value = false;
    ReadinessBoard.resetCache();
    resetSignInRouting();
    launcher = FakeLauncher()..install();
    addTearDown(FakeLauncher.uninstall);
  });

  group('model', () {
    test('parses the overview; needs attention = a task or readiness < 90', () {
      final o = AccountantOverview.fromJson(
        clientsJson(
          requests: [request('r1', 'PENDING'), request('r2', 'DECLINED')],
        ),
      );
      expect(o.isAccountant, isTrue);
      expect(o.officeName, 'משרד כהן');
      expect(o.clients, hasLength(3));
      expect(o.clientOf('b2')!.openTasks, 3);
      expect(o.clientOf('b1')!.needsAttention, isFalse);
      expect(o.clientOf('b2')!.needsAttention, isTrue);
      expect(o.clientOf('b3')!.needsAttention, isTrue); // 80 < 90
      expect(o.needingAttention, 2);
      expect(o.pending.map((r) => r.id), ['r1']);
      expect(o.requests.last.status, AccessRequestStatus.declined);
    });

    test('summary text: count, needs attention, all clear', () {
      expect(clientsSummaryText(12, 3), '12 לקוחות · 3 דורשים טיפול');
      expect(clientsSummaryText(12, 0), '12 לקוחות · הכול מסודר');
      expect(clientsSummaryText(12, null), '12 לקוחות');
    });

    test('previous period reviewed (bi-monthly start or later)', () {
      final now = DateTime(2026, 11, 22); // current 11-12, previous 9-10
      expect(previousPeriodReviewed('2026-09', now: now), isTrue);
      expect(previousPeriodReviewed('2026-10', now: now), isTrue);
      expect(previousPeriodReviewed('2026-08', now: now), isFalse);
      expect(previousPeriodReviewed(null, now: now), isFalse);
      // January: the previous period started in November of last year.
      expect(
        previousPeriodReviewed('2025-11', now: DateTime(2026, 1, 5)),
        isTrue,
      );
    });

    test('contact: e-mail or Israeli mobile', () {
      expect(isValidAccessContact('a@b.co'), isTrue);
      expect(isValidAccessContact('050-1234567'), isTrue);
      expect(isValidAccessContact('+972501234567'), isTrue);
      expect(isValidAccessContact('03-1234567'), isFalse);
      expect(isValidAccessContact('hello'), isFalse);
    });

    test('reminder text from the task counts (feature 8)', () {
      final c = AccountantClient.fromJson(
        client('b2', payments: 2, taxInvoices: 1, phone: '0501234567'),
      );
      expect(canRemindOwner(c), isTrue);
      expect(reminderParts(c.tasks), [
        '2 תשלומים בלי קבלה',
        'חשבונית מס אחת ממתינה',
      ]);
      expect(
        canRemindOwner(AccountantClient.fromJson(client('b1', phone: '050'))),
        isFalse,
      );
    });

    test('access links: /m/access/:token and tevel://access/:token', () {
      expect(
        accessTokenOf('https://app.tevel.space/m/access/$accessToken'),
        accessToken,
      );
      expect(accessTokenOf('/m/access/$accessToken'), accessToken);
      expect(accessTokenOf('tevel://access/$accessToken'), accessToken);
      expect(accessTokenOf('/m/invite/$accessToken'), isNull);
      expect(inviteTokenOf('/m/access/$accessToken'), isNull);
      expect(accessTokenOf('/m/access/short'), isNull);
    });

    test('push presentations exist for the four accountant kinds', () {
      for (final k in accountantPushKinds) {
        expect(systemNoticePresentation(k), isNotNull, reason: k);
      }
    });

    test('disabledKinds is sent only to a server that knows it', () {
      final old = PushPreferences.fromJson({
        'disabledCategories': <String>[],
        'enabledKinds': <String>[],
        'quietHours': true,
      });
      expect(old.toJson().containsKey('disabledKinds'), isFalse);
      final muted = old.withKind('ACCOUNTANT_EXPENSES_DIGEST', false);
      expect(muted.toJson()['disabledKinds'], ['ACCOUNTANT_EXPENSES_DIGEST']);
      expect(muted.kindOn('ACCOUNTANT_EXPENSES_DIGEST'), isFalse);
    });
  });

  group('feature 1: "הלקוחות שלי" row on the accountant home', () {
    testWidgets('count · needs attention; tap opens the clients list', (
      tester,
    ) async {
      backend.json('GET', '/mobile/accountant/clients', clientsJson());
      await pumpAs(
        tester,
        backend,
        Preset.accountantRep,
        const ReportsScreen(embedded: true),
        businesses: 3,
      );
      expect(find.text('3 לקוחות · 2 דורשים טיפול'), findsOneWidget);
      await tester.tap(find.byKey(const Key('clients-summary-row')));
      await settle(tester);
      expect(find.byType(SwitchBusinessSheet), findsOneWidget);
    });

    testWidgets('all clear → "· הכול מסודר"', (tester) async {
      backend.json(
        'GET',
        '/mobile/accountant/clients',
        clientsJson(clients: [client('b1'), client('b2')]),
      );
      await pumpAs(
        tester,
        backend,
        Preset.accountantRep,
        const ReportsScreen(embedded: true),
        businesses: 2,
      );
      expect(find.text('2 לקוחות · הכול מסודר'), findsOneWidget);
    });

    testWidgets('error → the count only (from the session)', (tester) async {
      backend.error('GET', '/mobile/accountant/clients', 500, 'INTERNAL');
      await pumpAs(
        tester,
        backend,
        Preset.accountantRep,
        const ReportsScreen(embedded: true),
        businesses: 3,
      );
      expect(find.byKey(const Key('clients-summary-text')), findsOneWidget);
      expect(find.text('3 לקוחות'), findsOneWidget);
      expect(find.textContaining('דורשים טיפול'), findsNothing);
    });

    testWidgets('loading → the count only', (tester) async {
      final answer = Completer<FakeResponse>();
      backend.on('GET', '/mobile/accountant/clients', (_) => answer.future);
      phone(tester);
      await tester.runAsync(
        () => signInAs(backend, Preset.accountantRep, businesses: 3),
      );
      await tester.pumpWidget(eApp(const ReportsScreen(embedded: true)));
      await tester.pump();
      expect(find.text('3 לקוחות'), findsOneWidget);
      answer.complete(FakeResponse(200, clientsJson()));
      await settle(tester);
      expect(find.text('3 לקוחות · 2 דורשים טיפול'), findsOneWidget);
    });

    testWidgets('owner: no row, no clients call', (tester) async {
      await pumpAs(
        tester,
        backend,
        Preset.owner,
        const ReportsScreen(),
        businesses: 3,
      );
      expect(find.byKey(const Key('clients-summary-row')), findsNothing);
      expect(backend.calls('GET', '/mobile/accountant/clients'), isEmpty);
    });
  });

  group('feature 3: badges in S14 from one call', () {
    testWidgets(
      'task bubbles, sort tasks desc then readiness asc, no readiness calls',
      (tester) async {
        backend.json(
          'GET',
          '/mobile/accountant/clients',
          clientsJson(
            clients: [
              client('b1', readiness: 50, reviewed: '2099-01'),
              client('b2', readiness: 95, payments: 2, phone: '0501234567'),
              client('b3', readiness: 70, expenses: 5),
            ],
          ),
        );
        await pumpAs(
          tester,
          backend,
          Preset.accountantRep,
          const Scaffold(body: SwitchBusinessSheet()),
          businesses: 3,
        );
        expect(find.byKey(const Key('s14-clients-summary')), findsOneWidget);
        expect(find.byKey(const Key('s14-tasks-b3')), findsOneWidget);
        expect(find.byKey(const Key('s14-tasks-b2')), findsOneWidget);
        expect(find.byKey(const Key('s14-tasks-b1')), findsNothing);
        expect(find.byKey(const Key('s14-score-b1')), findsOneWidget);
        expect(find.byKey(const Key('s14-reviewed-b1')), findsOneWidget);
        final y = {
          for (final id in ['b1', 'b2', 'b3'])
            id: tester.getTopLeft(find.byKey(Key('s14-$id'))).dy,
        };
        expect(y['b3']! < y['b2']!, isTrue); // 5 tasks before 2
        expect(y['b2']! < y['b1']!, isTrue); // tasks before none
        expect(backend.calls('GET', '/reports/readiness'), isEmpty);
      },
    );

    testWidgets('404 → the per-business readiness board as before', (
      tester,
    ) async {
      backend
        ..off('GET', '/reports/:kind')
        ..json('GET', '/reports/readiness', {
          'score': 70,
          'ready': false,
          'items': <Object>[],
        })
        ..error('GET', '/reports/:kind', 404, 'NOT_FOUND');
      await pumpAs(
        tester,
        backend,
        Preset.accountantRep,
        const Scaffold(body: SwitchBusinessSheet()),
        businesses: 3,
      );
      expect(backend.calls('GET', '/mobile/accountant/clients'), hasLength(1));
      expect(find.byKey(const Key('s14-board')), findsOneWidget);
      expect(backend.calls('GET', '/reports/readiness'), hasLength(3));
      expect(find.byKey(const Key('s14-add-client')), findsNothing);
    });

    testWidgets('a client row switches business and asks R for "לטיפול"', (
      tester,
    ) async {
      backend.json('GET', '/mobile/accountant/clients', clientsJson());
      await pumpAs(
        tester,
        backend,
        Preset.accountantRep,
        const AppShell(),
        businesses: 3,
      );
      await tester.tap(find.byKey(const Key('clients-summary-row')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('s14-b2')));
      await settle(tester);
      expect(session.business!.businessId, 'b2');
      // R consumed the request once loaded.
      expect(accountantFocusTodo.value, isFalse);
      expect(find.byType(ReportsScreen), findsOneWidget);
    });
  });

  group('feature 2: add a client + pending requests', () {
    testWidgets('contact + role → POST → share: WhatsApp with the server text', (
      tester,
    ) async {
      backend
        ..json('GET', '/mobile/accountant/clients', clientsJson())
        ..json('POST', '/mobile/accountant/access-requests', {
          'id': 'r9',
          'link': 'https://app.tevel.space/m/access/$accessToken',
          'whatsappText':
              'משרד כהן מבקש גישה: https://app.tevel.space/m/access/$accessToken',
          'emailed': false,
        }, status: 201);
      await pumpAs(
        tester,
        backend,
        Preset.accountantRep,
        const Scaffold(body: SwitchBusinessSheet()),
        businesses: 3,
      );
      final add = find.byKey(const Key('s14-add-client'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await settle(tester);
      expect(find.byKey(const Key('add-client-form')), findsOneWidget);
      // Invalid contact: nothing sent.
      await tester.enterText(
        find.byKey(const Key('add-client-contact')),
        'hello',
      );
      await tester.tap(find.byKey(const Key('add-client-send')));
      await settle(tester);
      expect(find.text(AccountantHe.contactInvalid), findsOneWidget);
      expect(
        backend.calls('POST', '/mobile/accountant/access-requests'),
        isEmpty,
      );
      await tester.enterText(
        find.byKey(const Key('add-client-contact')),
        '050-1234567',
      );
      await tester.tap(find.text(AccountantHe.roleFull));
      await settle(tester);
      await tester.tap(find.byKey(const Key('add-client-send')));
      await settle(tester);
      expect(backend.last('POST', '/mobile/accountant/access-requests')!.body, {
        'contact': '050-1234567',
        'role': 'ACCOUNTANT',
      });
      expect(find.byKey(const Key('add-client-share')), findsOneWidget);
      expect(find.byKey(const Key('add-client-emailed')), findsNothing);
      await tester.tap(find.byKey(const Key('add-client-whatsapp')));
      await settle(tester);
      final uri = launcher.last!;
      expect(uri.host, 'wa.me');
      expect(uri.path, '/972501234567');
      expect(uri.queryParameters['text'], contains('משרד כהן מבקש גישה'));
    });

    testWidgets('e-mail contact → "נשלח מייל"; 429 → the limit sentence', (
      tester,
    ) async {
      var calls = 0;
      backend
        ..json('GET', '/mobile/accountant/clients', clientsJson())
        ..on('POST', '/mobile/accountant/access-requests', (_) {
          calls++;
          return calls == 1
              ? const FakeResponse(201, {
                  'id': 'r9',
                  'link': 'https://x/m/access/t',
                  'whatsappText': 'טקסט',
                  'emailed': true,
                })
              : FakeResponse.error(429, 'RATE_LIMITED');
        });
      await pumpAs(
        tester,
        backend,
        Preset.accountantRep,
        const Scaffold(body: AddClientSheet()),
        businesses: 2,
      );
      await tester.enterText(
        find.byKey(const Key('add-client-contact')),
        'owner@example.test',
      );
      await tester.tap(find.byKey(const Key('add-client-send')));
      await settle(tester);
      expect(find.byKey(const Key('add-client-emailed')), findsOneWidget);

      await tester.pumpWidget(
        eApp(const Scaffold(body: AddClientSheet(key: ValueKey('again')))),
      );
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('add-client-contact')),
        'owner@example.test',
      );
      await tester.tap(find.byKey(const Key('add-client-send')));
      await settle(tester);
      expect(find.text(AccountantHe.rateLimited), findsOneWidget);
    });

    testWidgets('pending: grey row with resend / cancel; declined shown', (
      tester,
    ) async {
      backend
        ..json(
          'GET',
          '/mobile/accountant/clients',
          clientsJson(
            requests: [request('r1', 'PENDING'), request('r2', 'DECLINED')],
          ),
        )
        ..json('DELETE', '/mobile/accountant/access-requests/:id', {
          'status': 'ok',
        })
        ..json('POST', '/mobile/accountant/access-requests/:id/resend', {
          'id': 'r1',
          'link': 'https://x/m/access/new',
          'whatsappText': 'שוב',
          'emailed': true,
        });
      await pumpAs(
        tester,
        backend,
        Preset.accountantRep,
        const Scaffold(body: SwitchBusinessSheet()),
        businesses: 3,
      );
      expect(find.byKey(const Key('s14-pending-summary')), findsOneWidget);
      expect(
        find.text('${AccountantHe.pending} · ${AccountantHe.roleRep}'),
        findsOneWidget,
      );
      expect(
        find.text('${AccountantHe.declined} · ${AccountantHe.roleRep}'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('s14-request-cancel-r2')), findsNothing);
      // Pending requests sort after every business.
      expect(
        tester.getTopLeft(find.byKey(const Key('s14-request-r1'))).dy >
            tester.getTopLeft(find.byKey(const Key('s14-b1'))).dy,
        isTrue,
      );
      final cancel = find.byKey(const Key('s14-request-cancel-r1'));
      await tester.ensureVisible(cancel);
      await tester.tap(cancel);
      await settle(tester);
      expect(
        backend
            .last('DELETE', '/mobile/accountant/access-requests/:id')!
            .params['id'],
        'r1',
      );
      final resend = find.byKey(const Key('s14-request-resend-r1'));
      await tester.ensureVisible(resend);
      await tester.tap(resend);
      await settle(tester);
      expect(
        backend.calls('POST', '/mobile/accountant/access-requests/:id/resend'),
        hasLength(1),
      );
      expect(find.byKey(const Key('add-client-share')), findsOneWidget);
    });
  });

  group('feature 2: the owner approves (/m/access/:token)', () {
    Map<String, dynamic> preview({int businesses = 2}) => {
      'id': 'r1',
      'accountant': {
        'name': 'יוסי כהן',
        'email': 'yossi@cohen.test',
        'officeName': 'משרד כהן',
      },
      'role': 'ACCOUNTANT_REP',
      'expiresAt': '2026-11-29T00:00:00Z',
      'businesses': [
        for (var i = 1; i <= businesses; i++)
          {'businessId': 'b$i', 'legalName': 'עסק $i'},
      ],
    };

    testWidgets('who asks, three bullets, pick business, role, approve', (
      tester,
    ) async {
      backend
        ..json('GET', '/mobile/access-requests/:token', preview())
        ..json('POST', '/mobile/access-requests/:token/decide', {
          'status': 'APPROVED',
          'businessId': 'b2',
        });
      await pumpAs(
        tester,
        backend,
        Preset.owner,
        const AccessRequestScreen(token: accessToken),
        businesses: 2,
      );
      expect(find.text(AccountantHe.asks('יוסי כהן')), findsOneWidget);
      expect(find.text('משרד כהן'), findsOneWidget);
      for (final b in AccountantHe.canRep) {
        expect(find.text(b), findsOneWidget);
      }
      // Approve without a business: asks to pick one.
      await tester.tap(find.byKey(const Key('access-approve')));
      await settle(tester);
      expect(find.byKey(const Key('access-error')), findsOneWidget);
      expect(
        backend.calls('POST', '/mobile/access-requests/:token/decide'),
        isEmpty,
      );
      await tester.tap(find.text(AccountantHe.roleFull));
      await settle(tester);
      expect(find.text(AccountantHe.canFull[1]), findsOneWidget);
      final pick = find.byKey(const Key('access-business-b2'));
      await tester.ensureVisible(pick);
      await tester.tap(pick);
      await settle(tester);
      expect(
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        'b2',
      );
      await tester.tap(find.byKey(const Key('access-approve')));
      await settle(tester);
      final decide = backend.last(
        'POST',
        '/mobile/access-requests/:token/decide',
      )!;
      expect(decide.params['token'], accessToken);
      expect(decide.body, {
        'decision': 'APPROVE',
        'businessId': 'b2',
        'role': 'ACCOUNTANT',
      });
    });

    testWidgets('decline sends only the decision', (tester) async {
      backend
        ..json('GET', '/mobile/access-requests/:token', preview(businesses: 1))
        ..json('POST', '/mobile/access-requests/:token/decide', {
          'status': 'DECLINED',
        });
      await pumpAs(
        tester,
        backend,
        Preset.owner,
        const AccessRequestScreen(token: accessToken),
      );
      await tester.tap(find.byKey(const Key('access-decline')));
      await settle(tester);
      expect(
        backend.last('POST', '/mobile/access-requests/:token/decide')!.body,
        {'decision': 'DECLINE'},
      );
    });

    testWidgets('unknown / used / expired → one "no longer valid" answer', (
      tester,
    ) async {
      backend.error(
        'GET',
        '/mobile/access-requests/:token',
        404,
        'ACCESS_REQUEST_NOT_FOUND',
      );
      await pumpAs(
        tester,
        backend,
        Preset.owner,
        const AccessRequestScreen(token: accessToken),
      );
      expect(find.byKey(const Key('access-not-found')), findsOneWidget);
      expect(find.byKey(const Key('access-approve')), findsNothing);
    });

    testWidgets('the link opens the screen when signed in, waits otherwise', (
      tester,
    ) async {
      backend.json('GET', '/mobile/access-requests/:token', preview());
      openAccessRequest(accessToken); // signed out
      expect(debugPendingAccess, accessToken);
      await pumpAs(
        tester,
        backend,
        Preset.owner,
        const Scaffold(body: SizedBox()),
      );
      resetToHome();
      await settle(tester);
      expect(debugPendingAccess, isNull);
      expect(find.byType(AccessRequestScreen), findsOneWidget);
    });
  });

  group('feature 4: push + mute toggles', () {
    testWidgets('one business → switch to it; none → the clients list', (
      tester,
    ) async {
      backend.json('GET', '/mobile/accountant/clients', clientsJson());
      await pumpAs(
        tester,
        backend,
        Preset.accountantRep,
        const AppShell(),
        businesses: 3,
      );
      await tester.runAsync(
        () => openAccountantPush('ACCOUNTANT_ACCESS_APPROVED', 'b3'),
      );
      await settle(tester);
      expect(session.business!.businessId, 'b3');
      expect(backend.calls('GET', '/mobile/session'), isNotEmpty);

      await tester.runAsync(
        () => openAccountantPush('ACCOUNTANT_EXPENSES_DIGEST', ''),
      );
      await settle(tester);
      expect(find.byType(SwitchBusinessSheet), findsOneWidget);
    });

    testWidgets('accountant mutes a kind; owner sees no accountant toggles', (
      tester,
    ) async {
      backend
        ..json('GET', '/mobile/push/catalogue', {
          'categories': [
            {'id': 'MONEY', 'label': 'כסף', 'description': 'תשלומים'},
          ],
        })
        ..json('GET', '/mobile/push/preferences', {
          'disabledCategories': <String>[],
          'enabledKinds': <String>[],
          'quietHours': true,
          'disabledKinds': <String>[],
        })
        ..on(
          'PUT',
          '/mobile/push/preferences',
          (r) => FakeResponse(200, r.body),
        );
      await pumpAs(
        tester,
        backend,
        Preset.accountantRep,
        const NotificationPreferencesScreen(),
        businesses: 2,
      );
      final digest = find.byKey(
        const Key('notification-kind-ACCOUNTANT_EXPENSES_DIGEST'),
      );
      await tester.ensureVisible(digest);
      await tester.tap(digest);
      await settle(tester);
      expect(backend.last('PUT', '/mobile/push/preferences')!.body, {
        'disabledCategories': <String>[],
        'enabledKinds': <String>[],
        'quietHours': true,
        'disabledKinds': ['ACCOUNTANT_EXPENSES_DIGEST'],
      });

      accountantStore.reset();
      await pumpAs(
        tester,
        backend,
        Preset.owner,
        const NotificationPreferencesScreen(),
      );
      expect(find.text(AccountantHe.prefsTitle), findsNothing);
    });
  });

  group('feature 5: an accountant without businesses', () {
    Future<void> signedInWithoutBusiness(WidgetTester tester) async {
      phone(tester);
      backend.json('GET', '/mobile/session', accountJson(count: 0));
      await tester.runAsync(() async {
        ApiClient.instance.deviceToken = 'inv_${'a' * 48}';
        await session.refreshAccount();
      });
      session.status = SessionStatus.signedIn;
    }

    Widget go() => Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => routeSignedIn(context),
          child: const Text('go'),
        ),
      ),
    );

    testWidgets('routing: an accountant lands on the empty clients screen', (
      tester,
    ) async {
      backend.json(
        'GET',
        '/mobile/accountant/clients',
        clientsJson(clients: const []),
      );
      await signedInWithoutBusiness(tester);
      expect(session.business, isNull);
      await tester.pumpWidget(eApp(go()));
      await tester.tap(find.text('go'));
      await settle(tester);
      expect(find.byType(AccountantClientsScreen), findsOneWidget);
      expect(find.text(AccountantHe.addFirstClient), findsOneWidget);
      // Settings open without a business.
      await tester.tap(find.byKey(const Key('accountant-settings')));
      await settle(tester);
      expect(find.byType(AccountPage), findsOneWidget);
      expect(find.byKey(const Key('account-office')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('not an accountant (404) → the "no business" gate as before', (
      tester,
    ) async {
      await signedInWithoutBusiness(tester);
      await tester.pumpWidget(eApp(go()));
      await tester.tap(find.text('go'));
      await settle(tester);
      expect(find.byType(NoBusinessScreen), findsOneWidget);
    });

    testWidgets('"אני רו״ח" → office name → PUT → empty clients screen', (
      tester,
    ) async {
      backend
        ..json('PUT', '/mobile/accountant/profile', {
          'isAccountant': true,
          'officeName': 'משרד לוי',
        })
        ..json(
          'GET',
          '/mobile/accountant/clients',
          clientsJson(office: 'משרד לוי', clients: const []),
        );
      await signedInWithoutBusiness(tester);
      await tester.pumpWidget(eApp(const NoBusinessScreen()));
      await settle(tester);
      await tester.tap(find.byKey(const Key('no-business-accountant')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('office-save')));
      await settle(tester);
      expect(find.text(AccountantHe.officeRequired), findsOneWidget);
      await tester.enterText(find.byKey(const Key('office-name')), 'משרד לוי');
      await tester.tap(find.byKey(const Key('office-save')));
      await settle(tester);
      expect(backend.last('PUT', '/mobile/accountant/profile')!.body, {
        'officeName': 'משרד לוי',
      });
      expect(find.byType(AccountantClientsScreen), findsOneWidget);
      expect(find.byKey(const Key('accountant-office')), findsOneWidget);
      // "＋ הוספת לקוח ראשון" opens the add sheet straight away.
      await tester.tap(find.text(AccountantHe.addFirstClient));
      await settle(tester);
      expect(find.byKey(const Key('add-client-form')), findsOneWidget);
    });

    testWidgets('office name editable in the profile settings', (tester) async {
      backend
        ..json('GET', '/mobile/accountant/clients', clientsJson())
        ..json('PUT', '/mobile/accountant/profile', {
          'isAccountant': true,
          'officeName': 'משרד חדש',
        });
      await pumpAs(
        tester,
        backend,
        Preset.accountantRep,
        const AccountPage(),
        businesses: 2,
      );
      expect(find.text('משרד כהן'), findsOneWidget);
      await tester.tap(find.byKey(const Key('account-office')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('office-name')), 'משרד חדש');
      await tester.tap(find.byKey(const Key('office-save')));
      await settle(tester);
      expect(find.text('משרד חדש'), findsOneWidget);
    });

    testWidgets('owner profile: no office row, no clients call', (
      tester,
    ) async {
      await pumpAs(tester, backend, Preset.owner, const AccountPage());
      expect(find.byKey(const Key('account-office')), findsNothing);
      expect(backend.calls('GET', '/mobile/accountant/clients'), isEmpty);
    });
  });

  group('feature 6: "סימון כנבדק"', () {
    testWidgets('mark → POST the period; then undo → DELETE ?period=', (
      tester,
    ) async {
      servePeriodReview(backend, const []);
      await pumpAs(
        tester,
        backend,
        Preset.accountantRep,
        const ReportsScreen(embedded: true),
        businesses: 2,
      );
      final key = periodKeyOf(periodFor(PeriodKey.current).from);
      await tester.ensureVisible(find.byKey(const Key('period-review')));
      await tester.tap(find.byKey(const Key('period-review')));
      await settle(tester);
      expect(backend.last('POST', '/reports/period-review')!.body, {
        'period': key,
      });
      expect(find.byKey(const Key('period-reviewed')), findsOneWidget);
      await tester.tap(find.byKey(const Key('period-unreview')));
      await settle(tester);
      expect(
        backend.last('DELETE', '/reports/period-review')!.query['period'],
        key,
      );
      expect(find.byKey(const Key('period-review')), findsOneWidget);
    });

    testWidgets('owner R: no review button, no review call', (tester) async {
      servePeriodReview(backend, const []);
      await pumpAs(tester, backend, Preset.owner, const ReportsScreen());
      expect(find.byKey(const Key('period-review')), findsNothing);
      expect(backend.calls('GET', '/reports/period-review'), isEmpty);
    });

    testWidgets('a server without the endpoint → no button', (tester) async {
      await pumpAs(
        tester,
        backend,
        Preset.accountantRep,
        const ReportsScreen(embedded: true),
        businesses: 2,
      );
      expect(find.byKey(const Key('period-review')), findsNothing);
    });
  });

  group('feature 7: "הפסקת ליווי"', () {
    testWidgets('confirm → POST leave → the businesses reload', (tester) async {
      backend.json('POST', '/mobile/accountant/clients/:businessId/leave', {
        'status': 'ok',
      });
      await pumpAs(
        tester,
        backend,
        Preset.accountantRep,
        const BusinessScreen(),
        businesses: 2,
      );
      final leave = find.byKey(const Key('brow-leave'));
      await tester.scrollUntilVisible(
        leave,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(leave);
      await settle(tester);
      expect(find.byKey(const Key('leave-confirm')), findsOneWidget);
      // Only b2 is left on the server.
      backend.json('GET', '/mobile/session', {
        'userId': 'u-me',
        'email': 'me@tevel.test',
        'displayName': 'דנה',
        'businesses': [
          {'businessId': 'b2', 'legalName': 'עסק 2', 'role': 'READ_ONLY'},
        ],
      });
      await tester.tap(find.byKey(const Key('leave-yes')));
      await settle(tester);
      expect(
        backend
            .last('POST', '/mobile/accountant/clients/:businessId/leave')!
            .params['businessId'],
        'b1',
      );
      expect(session.businesses.map((b) => b.businessId), ['b2']);
      expect(session.business!.businessId, 'b2');
    });

    testWidgets('cancel sends nothing; the owner has no such row', (
      tester,
    ) async {
      await pumpAs(
        tester,
        backend,
        Preset.accountantRep,
        const BusinessScreen(),
        businesses: 2,
      );
      final leave = find.byKey(const Key('brow-leave'));
      await tester.scrollUntilVisible(
        leave,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(leave);
      await settle(tester);
      await tester.tap(find.text(AccountantHe.leaveCancel));
      await settle(tester);
      expect(
        backend.calls('POST', '/mobile/accountant/clients/:businessId/leave'),
        isEmpty,
      );

      await pumpAs(tester, backend, Preset.owner, const BusinessScreen());
      expect(find.byKey(const Key('brow-leave')), findsNothing);
    });
  });

  group('feature 8: "תזכורת לבעלים"', () {
    testWidgets('wa.me to the owner with the counts; none without tasks', (
      tester,
    ) async {
      backend.json('GET', '/mobile/accountant/clients', clientsJson());
      await pumpAs(
        tester,
        backend,
        Preset.accountantRep,
        const Scaffold(body: SwitchBusinessSheet()),
        businesses: 3,
      );
      expect(find.byKey(const Key('s14-remind-b1')), findsNothing);
      expect(find.byKey(const Key('s14-remind-b3')), findsNothing); // no phone
      await tester.tap(find.byKey(const Key('s14-remind-b2')));
      await settle(tester);
      final uri = launcher.last!;
      expect(uri.host, 'wa.me');
      expect(uri.path, '/972501234567');
      final text = uri.queryParameters['text']!;
      expect(text, contains('עסק 2'));
      expect(text, contains('2 תשלומים בלי קבלה'));
      expect(text, contains('חשבונית מס אחת ממתינה'));
      // No business switch from the reminder.
      expect(session.business!.businessId, 'b1');
    });
  });
}
