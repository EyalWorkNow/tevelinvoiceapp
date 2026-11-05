// Squad A logic: §6.H.1 card composition (per preset / business type),
// BE-05 vs P0 fallback, reminders (§9.3), L search / grouping (§6.L).

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/inbox_api.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/util/labels/inbox_he.dart';

import 'fakes/fake_api.dart';

Caps capsOf(Preset p, {Map<String, dynamic>? approvalPolicy}) =>
    Caps.fromMe(Me.fromJson(meJson(p, approvalPolicy: approvalPolicy)));

DocumentSummary doc(String id, {String type = 'TAX_INVOICE', String status = 'ARCHIVED', int? open, String? number,
        String? customerName = 'דנה כהן', int total = 118000, String? issueDate = '2026-10-20',
        String? createdBy = 'u-me', String? submittedBy, Map<String, dynamic>? rejection, String? customerId = 'c1'}) =>
    DocumentSummary.fromJson(docJson(id,
        type: type,
        status: status,
        open: open,
        number: number,
        customerName: customerName,
        total: total,
        issueDate: issueDate,
        createdBy: createdBy,
        submittedBy: submittedBy,
        rejection: rejection,
        customerId: customerId));

final today = DateTime(2026, 10, 30);

InboxContext ctxFor(Preset p,
        {String businessType = 'OSEK_MURSHE',
        Map<String, dynamic>? approvalPolicy,
        String? paymentLinkUrl = 'https://pay',
        int? memberCount = 3,
        bool? hasLogo = true,
        ShaamState? shaam,
        LocalUnfinished? local,
        Set<SetupStep> dismissed = const {}}) =>
    InboxContext(
      caps: capsOf(p, approvalPolicy: approvalPolicy),
      userId: 'u-me',
      businessType: businessType,
      today: today,
      paymentLinkUrl: paymentLinkUrl,
      memberCount: memberCount,
      hasLogo: hasLogo,
      shaam: shaam,
      localUnfinished: local,
      dismissedSetup: dismissed,
    );

DashboardSummary dash({int unpaid = 0, int overdue = 0, int overdueCount = 0}) => DashboardSummary.fromJson(
    dashboardJson(unpaid: unpaid, overdue: overdue, overdueCount: overdueCount));

/// Everything that can make a card, for the matrix tests.
InboxSources everything() => InboxSources(
      dashboard: dash(unpaid: 1240000, overdue: 320000, overdueCount: 3),
      documents: [
        doc('rej', status: 'DRAFT', submittedBy: 'u-me', rejection: {'reason': 'חסר פירוט'}),
        doc('t300', type: 'TRANSACTION_INVOICE', open: 0, number: '7', customerId: 'c9', customerName: 'רון'),
        doc('dr', status: 'DRAFT', customerName: 'נועה', total: 60000),
        doc('dr-other', status: 'DRAFT', createdBy: 'u-other'),
      ],
      waitingAllocation: [doc('wa', status: 'WAITING_FOR_ALLOCATION', number: '1043')],
      artifactPending: [doc('ap', status: 'ARTIFACT_PENDING'), doc('ap2', status: 'ARTIFACT_PENDING')],
      approvals: [
        ApprovalRow(id: 'p1', documentType: 'TAX_INVOICE', totalMinor: BigInt.from(500000), submittedBy: 'u-emp'),
        ApprovalRow(id: 'p2', documentType: 'TAX_INVOICE', totalMinor: BigInt.from(240000), submittedBy: 'u-emp'),
      ],
      expenseStatuses: const ['NEEDS_REVIEW', 'READY_TO_APPROVE', 'APPROVED'],
    );

List<InboxKind> kinds(HomeData h) => [for (final c in h.cards) c.kind];

void main() {
  group('composeHome (§6.H.1)', () {
    test('owner: every P0 kind, in priority order; money from BE-01', () {
      final h = composeHome(everything(),
          ctx: ctxFor(Preset.owner,
              shaam: ShaamState.fromJson({'status': 'CONNECTED', 'refreshTokenExpiresAt': '2026-11-04T00:00:00Z'}),
              paymentLinkUrl: null));
      expect(kinds(h), [
        InboxKind.approvalNeeded,
        InboxKind.myRejected,
        InboxKind.taxInvoiceDue,
        InboxKind.allocationProblem,
        InboxKind.signingLocked,
        InboxKind.unfinished,
        InboxKind.overdue,
        InboxKind.expenseReview,
        InboxKind.shaamRenew,
        InboxKind.setup,
      ]);
      expect(h.openMinor, BigInt.from(1240000));
      expect(h.overdueMinor, BigInt.from(320000));
      final approval = h.cards.first;
      expect(approval.count, 2);
      expect(approval.amountMinor, BigInt.from(740000));
      expect(InboxHe.approvalNeeded(approval.count), '2 ממתינים לאישורך');
      expect(h.cards.firstWhere((c) => c.kind == InboxKind.myRejected).reason, 'חסר פירוט');
      expect(h.cards.firstWhere((c) => c.kind == InboxKind.unfinished).count, 2); // owner sees all drafts
      expect(h.cards.firstWhere((c) => c.kind == InboxKind.overdue).count, 3);
      expect(h.cards.firstWhere((c) => c.kind == InboxKind.expenseReview).count, 2);
      expect(h.cards.firstWhere((c) => c.kind == InboxKind.shaamRenew).daysLeft, 5);
      expect(h.cards.last.setupStep, SetupStep.paymentLink);
      expect(h.recent, hasLength(4));
    });

    test('employee: no money, own drafts + own rejection only', () {
      final h = composeHome(everything(), ctx: ctxFor(Preset.employee));
      expect(h.openMinor, isNull);
      expect(kinds(h), [InboxKind.myRejected, InboxKind.unfinished]);
      expect(h.cards[1].count, 1);
      expect(h.cards[1].customerName, 'נועה');
      expect(h.cards[1].amountMinor, BigInt.from(60000));
    });

    test('employee + מפיק בעצמו: + signing / allocation, still no approvals or money', () {
      final h = composeHome(everything(), ctx: ctxFor(Preset.employeeIssuer));
      expect(kinds(h), [
        InboxKind.myRejected,
        InboxKind.taxInvoiceDue,
        InboxKind.allocationProblem,
        InboxKind.signingLocked,
        InboxKind.unfinished,
      ]);
      expect(h.openMinor, isNull);
    });

    test('viewer: money card, no cards', () {
      final h = composeHome(everything(), ctx: ctxFor(Preset.viewer));
      expect(h.cards, isEmpty);
      expect(h.openMinor, BigInt.from(1240000));
    });

    test('P0 accountant: expenses only', () {
      expect(kinds(composeHome(everything(), ctx: ctxFor(Preset.accountantRep))), [InboxKind.expenseReview]);
    });

    test('TAX_INVOICE_DUE only at VAT businesses, and not once a 305 exists', () {
      final s = everything();
      for (final type in ['OSEK_PATUR', 'NONPROFIT']) {
        expect(kinds(composeHome(s, ctx: ctxFor(Preset.owner, businessType: type))),
            isNot(contains(InboxKind.taxInvoiceDue)));
      }
      final withTax = InboxSources(documents: [
        ...s.documents,
        doc('t305', type: 'TAX_INVOICE', open: 0, customerId: 'c9', issueDate: '2026-10-25'),
      ]);
      expect(kinds(composeHome(withTax, ctx: ctxFor(Preset.owner))), isNot(contains(InboxKind.taxInvoiceDue)));
      final h = composeHome(InboxSources(documents: [s.documents[1]]), ctx: ctxFor(Preset.owner));
      expect(inboxTitleFor(h.cards.single), 'רון שילם על חשבון עסקה – הפק חשבונית מס');
    });

    test('APPROVAL_NEEDED leaves out my own submissions while another approver exists', () {
      final s = InboxSources(approvals: [
        ApprovalRow(id: 'mine', documentType: 'TAX_INVOICE', totalMinor: BigInt.one, submittedBy: 'u-me'),
      ]);
      final withOther = ctxFor(Preset.owner,
          approvalPolicy: {'mode': 'THRESHOLD', 'thresholdMinor': '500000', 'otherApproverExists': true});
      expect(composeHome(s, ctx: withOther).cards.where((c) => c.kind == InboxKind.approvalNeeded), isEmpty);
      final alone = ctxFor(Preset.owner,
          approvalPolicy: {'mode': 'THRESHOLD', 'thresholdMinor': '500000', 'otherApproverExists': false});
      expect(composeHome(s, ctx: alone).cards.first.kind, InboxKind.approvalNeeded);
    });

    test('UNFINISHED adds the local issue journal (AT-18) without double counting', () {
      final local = LocalUnfinished(draftId: 'x9', totalMinor: BigInt.from(60000), customerName: 'נועה');
      final h = composeHome(InboxSources(), ctx: ctxFor(Preset.owner, local: local));
      expect(h.cards.single.kind, InboxKind.unfinished);
      expect(h.cards.single.documentIds, ['x9']);
      final same = composeHome(InboxSources(documents: [doc('x9', status: 'DRAFT')]),
          ctx: ctxFor(Preset.owner, local: local));
      expect(same.cards.single.count, 1);
    });

    test('SETUP: one at a time, fixed order, ✕ skips to the next', () {
      final s = InboxSources();
      SetupStep? step(InboxContext c) => composeHome(s, ctx: c).cards.singleOrNull?.setupStep;
      expect(step(ctxFor(Preset.owner, hasLogo: false, paymentLinkUrl: null, memberCount: 1)), SetupStep.logo);
      expect(step(ctxFor(Preset.owner, hasLogo: false, paymentLinkUrl: null, dismissed: {SetupStep.logo})),
          SetupStep.paymentLink);
      expect(step(ctxFor(Preset.owner, memberCount: 1)), SetupStep.team);
      expect(step(ctxFor(Preset.owner)), isNull);
      expect(step(ctxFor(Preset.employee, hasLogo: false, paymentLinkUrl: null, memberCount: 1)), isNull);
    });

    test('SHAAM_RENEW only within 14 days of expiry', () {
      HomeData at(String iso) => composeHome(InboxSources(),
          ctx: ctxFor(Preset.owner, shaam: ShaamState.fromJson({'status': 'CONNECTED', 'refreshTokenExpiresAt': iso})));
      expect(at('2027-01-10T00:00:00Z').cards, isEmpty);
      expect(at('2026-11-10T00:00:00Z').cards.single.daysLeft, 11);
    });

    test('a brand-new business has no documents', () {
      final h = composeHome(InboxSources(dashboard: dash()), ctx: ctxFor(Preset.owner));
      expect(h.hasDocuments, isFalse);
      expect(h.openMinor, BigInt.zero);
    });
  });

  group('filterHome (BE-05 cards are re-checked against caps)', () {
    test('hides kinds the caps do not allow and dismissed SETUP; drops money without money.view', () {
      final server = HomeData.fromJson({
        'money': {'openMinor': '1240000', 'overdueMinor': '320000'},
        'cards': [
          {'kind': 'SETUP', 'step': 'LOGO'},
          {'kind': 'OVERDUE', 'priority': 50, 'count': 3, 'amountMinor': '820000', 'documentIds': ['a'], 'action': 'SEND_REMINDERS'},
          {'kind': 'APPROVAL_NEEDED', 'count': 1, 'documentIds': ['b']},
          {'kind': 'SOMETHING_NEW'},
        ],
        'recent': [docJson('r1')],
      });
      expect(kinds(filterHome(server, caps: capsOf(Preset.owner))),
          [InboxKind.approvalNeeded, InboxKind.overdue, InboxKind.setup]);
      expect(kinds(filterHome(server, caps: capsOf(Preset.owner), dismissedSetup: {SetupStep.logo})),
          [InboxKind.approvalNeeded, InboxKind.overdue]);
      final emp = filterHome(server, caps: capsOf(Preset.employee));
      expect(emp.cards, isEmpty);
      expect(emp.openMinor, isNull);
      expect(server.recent.single.id, 'r1');
    });

    test('HomeData round-trips through the cache JSON', () {
      final h = composeHome(everything(), ctx: ctxFor(Preset.owner));
      final back = HomeData.fromJson(h.toJson());
      expect(kinds(back), kinds(h));
      expect(back.openMinor, h.openMinor);
      expect(back.recent.map((d) => d.id), h.recent.map((d) => d.id));
      expect(back.cards.first.amountMinor, h.cards.first.amountMinor);
    });
  });

  group('fetchHome', () {
    late Directory tmp;
    late FakeBackend backend;

    setUpAll(() async {
      tmp = await Directory.systemTemp.createTemp('inbox_api_test');
      AppCache.directoryProvider = () async => tmp;
    });

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      resetSession();
      mobileInboxAvailable = null;
      localUnfinishedProbe = () async => null;
      backend = FakeBackend()..install();
      await AppCache.clearAll();
    });

    test('P0: no /mobile/inbox → composes from the P0 endpoints, only those the caps need', () async {
      installInboxFakes(backend,
          documents: [docJson('d1', number: '12')],
          dashboard: dashboardJson(unpaid: 50000, overdue: 20000, overdueCount: 1));
      await signInAs(backend, Preset.employee);
      final h = await fetchHome(caps: capsOf(Preset.employee), now: today);
      expect(mobileInboxAvailable, isFalse);
      expect(h.openMinor, isNull);
      expect(h.recent.single.documentNumber, '12');
      expect(backend.last('GET', '/documents')!.query['limit'], '100');
      expect(backend.calls('GET', '/approvals'), isEmpty);
      expect(backend.calls('GET', '/expenses/inbox'), isEmpty);
      expect(backend.calls('GET', '/settings/branding'), isEmpty);
      // second load skips the 404
      await fetchHome(caps: capsOf(Preset.employee), now: today);
      expect(backend.calls('GET', '/mobile/inbox'), hasLength(1));
      expect((await readCachedHome())!.recent.single.id, 'd1');
    });

    test('owner P0 asks approvals, expenses, allocation, signing and branding', () async {
      installInboxFakes(backend, logoDataUri: null);
      await signInAs(backend, Preset.owner);
      final h = await fetchHome(caps: capsOf(Preset.owner), now: today);
      expect(backend.calls('GET', '/approvals'), hasLength(1));
      expect(backend.calls('GET', '/expenses/inbox'), hasLength(1));
      expect(backend.calls('GET', '/settings/branding'), hasLength(1));
      final statuses = [for (final r in backend.calls('GET', '/documents')) r.query['status']];
      expect(statuses, containsAll(['WAITING_FOR_ALLOCATION', 'ARTIFACT_PENDING']));
      expect(h.cards.single.setupStep, SetupStep.logo);
    });

    test('BE-05: /mobile/inbox is used as is (no P0 calls)', () async {
      installInboxFakes(backend, mobileInbox: {
        'generatedAt': '2026-10-30T08:00:00Z',
        'money': {'openMinor': '1240000', 'overdueMinor': '320000'},
        'cards': [
          {'kind': 'OVERDUE', 'priority': 50, 'count': 3, 'amountMinor': '820000', 'documentIds': ['a'], 'action': 'SEND_REMINDERS'},
        ],
        'recent': [docJson('r1', number: '5')],
      });
      await signInAs(backend, Preset.owner);
      final h = await fetchHome(caps: capsOf(Preset.owner), now: today);
      expect(mobileInboxAvailable, isTrue);
      expect(h.openMinor, BigInt.from(1240000));
      expect(h.cards.single.kind, InboxKind.overdue);
      expect(backend.calls('GET', '/dashboard'), isEmpty);
      expect(backend.last('GET', '/mobile/inbox')!.query['limit'], '10');
    });

    test('a non-404 error is not mistaken for "no BE-05"', () async {
      installInboxFakes(backend);
      backend.error('GET', '/mobile/inbox', 500, 'INTERNAL');
      await signInAs(backend, Preset.owner);
      await expectLater(fetchHome(caps: capsOf(Preset.owner)), throwsA(isA<Object>()));
      expect(mobileInboxAvailable, isNull);
    });
  });

  group('reminders (§9.3, J10)', () {
    late FakeBackend backend;

    setUp(() async {
      resetSession();
      backend = FakeBackend()..install();
      installInboxFakes(backend, documents: [
        docJson('late-mail', open: 118000, number: '1', customerId: 'c1', issueDate: '2026-09-01'),
        docJson('late-noconsent', open: 50000, number: '2', customerId: 'c2', issueDate: '2026-09-01'),
        docJson('late-nomail', open: 30000, number: '3', customerId: 'c3', customerName: 'רון', issueDate: '2026-09-01'),
        docJson('fresh', open: 10000, number: '4', customerId: 'c1', issueDate: '2026-10-25'),
        docJson('due-later', open: 10000, number: '5', customerId: 'c1', issueDate: '2026-09-01', dueDate: '2026-11-15'),
      ]);
      backend
        ..json('GET', '/customers', {
          'customers': [
            {'id': 'c1', 'name': 'דנה כהן', 'email': 'dana@example.test', 'phone': '0501234567'},
            {'id': 'c2', 'name': 'יוסי', 'email': 'yossi@example.test', 'phone': '0521111111'},
            {'id': 'c3', 'name': 'רון', 'email': null, 'phone': '0532222222'},
          ]
        })
        ..on('POST', '/documents/:id/send', (r) => r.params['id'] == 'late-noconsent'
            ? FakeResponse.error(409, 'CONSENT_REQUIRED')
            : FakeResponse(202, {'deliveryId': 'dl-${r.params['id']}'}));
    });

    test('mails the overdue invoices with e-mail + consent; the rest go to WhatsApp', () async {
      final r = await sendReminders(now: today, paymentUrl: 'https://pay.example/x');
      expect(r.sent, 1);
      expect([for (final t in r.whatsapp) t.documentId], ['late-noconsent', 'late-nomail']);
      final send = backend.calls('POST', '/documents/:id/send');
      expect(send.first.body, {'recipient': 'dana@example.test', 'paymentUrl': 'https://pay.example/x'});
      expect(backend.calls('POST', '/deliveries/:id/process').single.path, '/deliveries/dl-late-mail/process');
      expect(InboxHe.remindersDone(r.sent, r.whatsapp.length),
          'נשלחה תזכורת אחת במייל · 2 בלי מייל – שלח בווטסאפ');
      expect(InboxHe.remindersDone(3, 1), 'נשלחו 3 תזכורות במייל · 1 בלי מייל – שלח בווטסאפ');
    });

    test('WhatsApp reminder: share link → wa.me/972… with /d/ (AT-95)', () async {
      final l = FakeLauncher()..install();
      addTearDown(FakeLauncher.uninstall);
      backend.error('POST', '/documents/:id/share-link', 409, 'ARTIFACT_REQUIRED');
      var first = true;
      backend.on('POST', '/documents/:id/share-link', (r) {
        if (first) {
          first = false;
          return FakeResponse.error(409, 'ARTIFACT_REQUIRED');
        }
        return FakeResponse(201, {'url': 'https://invoice.test/d/tok'});
      });
      await remindOnWhatsApp(
        ReminderTarget(documentId: 'late-nomail', customerName: 'רון', phone: '053-2222222', documentNumber: '3', openMinor: BigInt.from(30000)),
        businessName: 'סטודיו תבל',
      );
      expect(backend.calls('POST', '/documents/:id/artifact'), hasLength(1));
      final url = l.last.toString();
      expect(url, startsWith('https://wa.me/972532222222?text='));
      expect(Uri.decodeComponent(url), contains('/d/tok'));
      expect(Uri.decodeComponent(url), contains('₪300'));
    });

    test('allocation retry posts the document scope', () async {
      await retryAllocation(['wa1']);
      expect(backend.last('POST', '/documents/:id/allocation')!.body, {'scopeKey': 'default'});
    });
  });

  group('L search + grouping (§6.L)', () {
    final docs = [
      doc('a', number: '1200', customerName: 'אבי', total: 5000),
      doc('b', number: '77', customerName: 'בתיה', total: 120000),
      doc('c', number: '12001', customerName: 'גיל', total: 9900),
      doc('d', number: '5', customerName: 'Dana Ltd', total: 120050, issueDate: '2026-09-02'),
    ];

    test('amount parsing normalises ₪, commas and the decimal point', () {
      expect(parseAmountQuery('1,200'), BigInt.from(120000));
      expect(parseAmountQuery('₪1,200.5'), BigInt.from(120050));
      expect(parseAmountQuery(' 1200.50 '), BigInt.from(120050));
      expect(parseAmountQuery('דנה'), isNull);
      expect(parseAmountQuery('1.234.5'), isNull);
    });

    test('digits only: document number first, then amount, then prefix numbers', () {
      expect(searchDocuments(docs, '1200').map((d) => d.id), ['a', 'c', 'b']);
      expect(searchDocuments(docs, '1,200').map((d) => d.id), ['b']);
      expect(searchDocuments(docs, '1,200.50').map((d) => d.id), ['d']);
      expect(searchDocuments(docs, 'dana').map((d) => d.id), ['d']);
      expect(searchDocuments(docs, 'בתי').map((d) => d.id), ['b']);
      expect(searchDocuments(docs, '  ').length, 4);
    });

    test('quotes: name, title, amount', () {
      final qs = [
        QuoteRow(id: 'q1', status: 'SENT', totalMinor: BigInt.from(120000), customerName: 'רון'),
        QuoteRow(id: 'q2', status: 'DRAFT', totalMinor: BigInt.from(5000), title: 'עיצוב לוגו'),
      ];
      expect(searchQuotes(qs, '1,200').single.id, 'q1');
      expect(searchQuotes(qs, 'לוגו').single.id, 'q2');
    });

    test('groups by month, newest first; drafts without a date go to this month', () {
      final groups = groupByMonth([...docs, doc('x', status: 'DRAFT', issueDate: null)], (d) => d.issueDate,
          today: today);
      expect(groups.map((g) => g.title), ['אוקטובר 2026', 'ספטמבר 2026']);
      expect(groups.first.rows.map((d) => d.id), ['a', 'b', 'c', 'x']);
    });

    test('fetchDocumentRows: BE-10 is detected from the echoed offset', () async {
      resetSession();
      final backend = FakeBackend()..install();
      installInboxFakes(backend, documents: [docJson('a')]);
      expect((await fetchDocumentRows(limit: 500)).serverSearch, isFalse);
      installInboxFakes(backend, documents: [docJson('a')], be10: true);
      final page = await fetchDocumentRows(q: 'דנה', offset: 0, limit: 50);
      expect(page.serverSearch, isTrue);
      expect(backend.last('GET', '/documents')!.query, {'limit': '50', 'q': 'דנה', 'offset': '0'});
    });
  });

  group('P1: BE-05 real shape, local journal, signing, BE-10 search', () {
    late Directory tmp;
    late FakeBackend backend;

    setUpAll(() async {
      tmp = await Directory.systemTemp.createTemp('inbox_api_p1_test');
      AppCache.directoryProvider = () async => tmp;
    });

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      resetSession();
      mobileInboxAvailable = null;
      localUnfinishedProbe = () async => null;
      backend = FakeBackend()..install();
      await AppCache.clearAll();
    });

    test('BE-05 `detail` fills the card words; TEAM_MEMBER, shaam expiry, expenseIds, cancelled rows', () {
      final h = HomeData.fromJson(
        mobileInboxJson(open: 50000, cards: [
          inboxCardJson('MY_REJECTED', amount: '60000', documentIds: ['rej'], action: 'FIX', detail: {
            'documentId': 'rej', 'documentType': 'TAX_INVOICE', 'status': 'DRAFT', 'customerName': 'נועה',
            'totalMinor': '60000',
            'rejection': {'reason': 'חסר פירוט', 'by': 'u-owner', 'byEmail': null, 'at': '2026-10-29T10:00:00Z'},
          }),
          inboxCardJson('TAX_INVOICE_DUE', amount: '118000', documentIds: ['t300'], action: 'ISSUE_TAX_INVOICE',
              detail: {'documentType': 'TRANSACTION_INVOICE', 'customerName': 'רון', 'dueBy': '2026-11-13'}),
          inboxCardJson('EXPENSE_REVIEW', count: 1, amount: '9000', expenseIds: ['e1'], action: 'REVIEW'),
          inboxCardJson('SHAAM_RENEW', action: 'RENEW_SHAAM',
              detail: {'shaamStatus': 'CONNECTED', 'refreshTokenExpiresAt': '2026-11-04T12:00:00Z'}),
          inboxCardJson('SETUP', action: 'SETUP', detail: {'step': 'TEAM_MEMBER'}),
          inboxCardJson('QUOTE_ACCEPTED_V9', action: 'OPEN'), // unknown kind → ignored
        ], recent: [
          recentJson('v1', type: 'TRANSACTION_INVOICE', total: 30000, open: 0, cancelled: true),
        ]),
        now: today,
      );
      expect(kinds(h), [
        InboxKind.myRejected, InboxKind.taxInvoiceDue, InboxKind.expenseReview, InboxKind.shaamRenew, InboxKind.setup,
      ]);
      expect(h.cards[0].reason, 'חסר פירוט');
      expect(h.cards[0].customerName, 'נועה');
      expect(h.cards[1].dueDate, '2026-11-13');
      expect(h.cards[1].documentType, 'TRANSACTION_INVOICE');
      expect(h.cards[2].expenseIds, ['e1']);
      expect(h.cards[3].daysLeft, 5);
      expect(h.cards[4].setupStep, SetupStep.team);
      expect(h.recent.single.voidedAt, isNotNull); // "בוטל" in the row
      // the cache keeps the flat shape and reads it back
      final again = HomeData.fromJson(h.toJson(), now: today);
      expect(again.cards[1].dueDate, '2026-11-13');
      expect(again.cards[2].expenseIds, ['e1']);
      expect(again.cards[4].setupStep, SetupStep.team);
      // an expired connection → 0 days
      final expired = InboxItem.fromJson(
          inboxCardJson('SHAAM_RENEW', detail: {'shaamStatus': 'EXPIRED', 'refreshTokenExpiresAt': null}),
          now: today);
      expect(expired.daysLeft, 0);
    });

    test('BE-05 + the local issue journal: joins UNFINISHED, adds a card, never double counts', () {
      final caps = capsOf(Preset.owner);
      const local = LocalUnfinished(draftId: 'loc', customerName: 'טל');
      final none = HomeData.fromJson(mobileInboxJson(open: 0), now: today);
      final added = mergeLocalUnfinished(none, local, caps: caps);
      expect(added.cards.single.kind, InboxKind.unfinished);
      expect(added.cards.single.customerName, 'טל');

      final withDrafts = HomeData.fromJson(
          mobileInboxJson(open: 0, cards: [
            inboxCardJson('OVERDUE', count: 2, documentIds: ['o1', 'o2'], action: 'SEND_REMINDERS'),
            inboxCardJson('UNFINISHED', count: 2, documentIds: ['d1', 'd2'], action: 'CONTINUE'),
          ]),
          now: today);
      final joined = mergeLocalUnfinished(withDrafts, local, caps: caps);
      expect(kinds(joined), [InboxKind.unfinished, InboxKind.overdue]);
      expect(joined.cards.first.count, 3);
      expect(joined.cards.first.documentIds, ['d1', 'd2', 'loc']);

      final same = mergeLocalUnfinished(withDrafts, const LocalUnfinished(draftId: 'd2'), caps: caps);
      expect(same.cards.firstWhere((c) => c.kind == InboxKind.unfinished).count, 2);
      expect(mergeLocalUnfinished(none, local, caps: capsOf(Preset.viewer)).cards, isEmpty);
    });

    test('fetchHome with BE-05 merges the journal and drops dismissed SETUP', () async {
      installInboxFakes(backend,
          mobileInbox: mobileInboxJson(open: 1000, cards: [
            inboxCardJson('SETUP', action: 'SETUP', detail: {'step': 'LOGO'}),
          ]));
      localUnfinishedProbe = () async => LocalUnfinished(draftId: null, totalMinor: BigInt.from(60000), customerName: 'טל');
      await signInAs(backend, Preset.owner);
      await dismissSetup(SetupStep.logo);
      final h = await fetchHome(caps: capsOf(Preset.owner), now: today);
      expect(kinds(h), [InboxKind.unfinished]);
      expect(h.cards.single.amountMinor, BigInt.from(60000));
    });

    test('SIGNING_LOCKED: one release, then every waiting original is signed', () async {
      var unlocked = false;
      backend
        ..on('POST', '/settings/signing/unlock', (r) {
          unlocked = true;
          return const FakeResponse(200, {'unlocked': true});
        })
        ..on('POST', '/documents/:id/sign',
            (r) => unlocked ? const FakeResponse(200, {'signed': true}) : FakeResponse.error(409, 'SIGNING_LOCKED'));
      await signInAs(backend, Preset.owner);
      var asked = 0;
      final n = await signPendingDocuments(['ap1', 'ap2'], askPassphrase: () async {
        asked++;
        return (passphrase: 'pass', remember: false);
      });
      expect(n, 2);
      expect(asked, 1);
      expect([for (final r in backend.calls('POST', '/documents/:id/sign')) r.path],
          ['/documents/ap1/sign', '/documents/ap1/sign', '/documents/ap2/sign']);
      expect(backend.calls('POST', '/documents/:id/artifact'), isEmpty); // already sealed

      unlocked = false;
      final cancelled = await signPendingDocuments(['ap3'], askPassphrase: () async => null);
      expect(cancelled, 0);
    });

    test('BE-10 search: text → q; amount → minTotal=maxTotal; paging', () async {
      installInboxFakes(backend, be10: true, documents: [
        for (var i = 0; i < 60; i++) docJson('n$i', customerName: 'דנה $i', total: 10000 + i),
        docJson('amt', customerName: 'רון', total: 120000),
      ]);
      await signInAs(backend, Preset.owner);
      final page = await serverSearchDocuments('דנה');
      expect(page.documents, hasLength(50));
      expect(page.hasMore, isTrue);
      expect(backend.last('GET', '/documents')!.query, {'limit': '50', 'q': 'דנה', 'offset': '0'});
      final next = await serverSearchDocuments('דנה', offset: 50);
      expect(next.documents, hasLength(10));
      final amount = await serverSearchDocuments('₪1,200', unpaid: true);
      expect(backend.last('GET', '/documents')!.query,
          {'limit': '50', 'unpaid': '1', 'offset': '0', 'minTotal': '120000', 'maxTotal': '120000'});
      expect(amount.pageable, isTrue);
    });

    test('BE-10 digits: number first, then amount, then the tax-ID customer\'s documents', () async {
      installInboxFakes(backend, be10: true, documents: [
        docJson('byAmount', number: '9', customerId: 'c1', total: 51234567800),
        docJson('byNumber', number: '512345678', customerId: 'c1'),
        docJson('byTax', number: '3', customerId: 'c7', customerName: 'חברה בע"מ'),
      ]);
      backend.json('GET', '/customers', {
        'total': 2,
        'customers': [
          {'id': 'c7', 'name': 'חברה בע"מ', 'tax_id': '512345678'},
          {'id': 'c8', 'name': 'דומה', 'tax_id': '5123456789'},
        ],
      });
      await signInAs(backend, Preset.owner);
      final page = await serverSearchDocuments('512345678');
      expect(page.documents.map((d) => d.id), ['byNumber', 'byAmount', 'byTax']);
      expect(page.hasMore, isFalse);
      expect(backend.last('GET', '/customers')!.query, {'q': '512345678', 'limit': '5'});
      expect(backend.calls('GET', '/documents').where((r) => r.query['customerId'] == 'c8'), isEmpty);
    });
  });
}

String inboxTitleFor(InboxItem c) => InboxHe.taxInvoiceDue(c.customerName, null);
