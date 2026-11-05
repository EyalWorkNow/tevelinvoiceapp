// ignore_for_file: file_names
// QA (qa-business) · SPEC-v2 §17 acceptance tests for: home money card
// (BE-01), "לטיפול" inbox cards (§6.H.1), business tab B (§6.B), team (§12),
// reports R (§6.R, §11), settings (§13), business switch (S14).
//
// Real app on the simulator against the LOCAL dev API (never prod). Set-up and
// verification go straight over HTTP with the dev preset accounts
// (docs/API-MOBILE.md "Role presets"). The e-mail MFA codes are read from the
// dev mail folder on the host (simulator apps can read host paths).
//
//   ~/flutter/bin/flutter test integration_test/v2_qa-business_test.dart -d <udid> \
//     --dart-define=API_BASE=http://127.0.0.1:3031
//
// Creates (idempotently) two password members in the studio business:
// qa-biz-role@tevel.test (READ_ONLY, AT-46) and qa-biz-switch@tevel.test
// (EMPLOYEE here + OWNER of its own עוסק פטור "QA עסק שני", AT-29/43b/54),
// one QA customer per run, a few small documents (credited back) and
// invitations (revoked). Totals are compared with the server aggregates, so a
// parallel writer on the same dev business can make a BE-01 delta flaky.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/app_shell.dart';
import 'package:invoice/router.dart' show navigatorKey;
import 'package:invoice/screens/business/business_screen.dart';
import 'package:invoice/screens/business/sheets/s13_editor.dart' show EditorSheet;
import 'package:invoice/screens/home/home_screen.dart';
import 'package:invoice/screens/reports/reports_screen.dart';
import 'package:invoice/state/business_context.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/session.dart';
import 'package:invoice/ui/widgets/money_card.dart';
import 'package:invoice/util/biometric.dart';
import 'package:invoice/util/labels/labels.dart';

import 'v2_qa_business_helpers.dart';

const ownerEmail = 'mobile-owner@tevel.test';
const staffEmail = 'mobile-staff@tevel.test';
const viewerEmail = 'mobile-viewer@tevel.test';
const accountantEmail = 'mobile-accountant@tevel.test'; // P0 preset: READ_ONLY + expense grants
const cpaRepEmail = 'mobile-cpa-rep@tevel.test'; // ACCOUNTANT_REP (BE-04)
const roleEmail = 'qa-biz-role@tevel.test';
const switchEmail = 'qa-biz-switch@tevel.test';
const qaBizName = 'QA עסק שני';

/// The 10 rows of §6.B (+ "מספור ואישורים" for the representing accountant).
const allBusinessRows = {
  'reports', 'expenses', 'team', 'profile', 'branding', 'approvals', 'reminders', 'shaam', 'account', //
  'desktop', 'numbering',
};

late QaUser owner, staff, viewer, accountant, cpaRep, roleUser, switchUser;
late String roleUserId, staffUserId, qaBizId, qaCustomerId;
final runTag = DateTime.now().millisecondsSinceEpoch;
final lines = [
  {'description': 'QA business $runTag', 'quantityMicros': '1000000', 'unitPriceMinor': '1000', 'taxRateBasisPoints': 1800},
];
const lineTotal = 1180; // 10.00 + 18% VAT, in agorot

/// BE-01 fixture shared by the money tests (created in test 2, credited in test 4).
String? overdueDocId;
bool overdueCredited = false;

Future<Map<String, dynamic>> summary(QaUser u) async => (await u.ok('/dashboard'))['summary'] as Map<String, dynamic>;

String today() => isoDay(DateTime.now());

/// Open documents per BE-01: finalized 300/305 rows of `/documents?unpaid=1`.
Future<({BigInt open, int count, BigInt overdue, int overdueCount, int total})> unpaidFromList(QaUser u) async {
  final body = await u.ok('/documents?unpaid=1&limit=500');
  final docs = (body['documents'] as List).cast<Map<String, dynamic>>();
  var open = BigInt.zero, overdue = BigInt.zero;
  var overdueCount = 0;
  final now = DateTime.now();
  final todayDate = DateTime(now.year, now.month, now.day);
  for (final d in docs) {
    expect(['TRANSACTION_INVOICE', 'TAX_INVOICE'], contains(d['documentType']),
        reason: 'BE-01: only 300/305 are unpaid (${d['documentType']})');
    final o = minor(d['openMinor'] ?? d['balanceMinor']);
    open += o;
    final due = d['dueDate'] != null
        ? DateTime.parse(d['dueDate'] as String)
        : DateTime.parse(d['issueDate'] as String).add(const Duration(days: 30));
    if (due.isBefore(todayDate)) {
      overdue += o;
      overdueCount++;
    }
  }
  return (open: open, count: docs.length, overdue: overdue, overdueCount: overdueCount, total: body['total'] as int);
}

Future<void> openBusinessTab(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('tab-business')));
  await waitFor(tester, find.byKey(const Key('brow-account')));
  await pumpFor(tester, const Duration(seconds: 1));
}

Set<String> businessRowKeys() => {
      for (final k in byKeyPrefix('brow-').evaluate().map((e) => (e.widget.key! as ValueKey<String>).value))
        k.substring('brow-'.length),
    };

/// The studio member list of the owner (API).
Future<Map<String, dynamic>> team() => owner.ok('/business/members');

Map<String, dynamic>? invitationFor(Map<String, dynamic> t, String email) {
  for (final i in (t['invitations'] as List? ?? const []).cast<Map<String, dynamic>>()) {
    if ('${i['email']}'.toLowerCase() == email) return i;
  }
  return null;
}

/// R's period line ('report-period'), without the LTR isolate marks.
String? periodLabel(WidgetTester tester) {
  final f = find.byKey(const Key('report-period'));
  if (f.evaluate().isEmpty) return null;
  return tester.widget<Text>(f).data?.replaceAll(RegExp('[\u2066-\u2069\u200e\u200f]'), '');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Biometric.instance.auth = AlwaysUnlock();

  setUpAll(() async {
    owner = await signIn(ownerEmail);
    staff = await signIn(staffEmail);
    viewer = await signIn(viewerEmail);
    accountant = await signIn(accountantEmail);
    cpaRep = await signIn(cpaRepEmail);

    roleUserId = await ensureMember(owner, roleEmail, 'QA תפקיד', 'READ_ONLY');
    roleUser = await signIn(roleEmail);
    await ensureMember(owner, switchEmail, 'QA החלפת עסק', 'EMPLOYEE');
    switchUser = await signIn(switchEmail);

    // The switch user's own business (BE-40): a solo עוסק פטור.
    Future<String?> findQaBiz() async {
      final list = await switchUser.ok('/mobile/businesses');
      for (final b in (list['businesses'] as List).cast<Map<String, dynamic>>()) {
        if (b['legalName'] == qaBizName && b['role'] == 'OWNER') return b['businessId'] as String;
      }
      return null;
    }

    var biz = await findQaBiz();
    if (biz == null) {
      final r = await switchUser.post('/businesses', {'businessType': 'OSEK_PATUR', 'legalName': qaBizName});
      expect(r.status, 201, reason: 'BE-40 POST /businesses → $r');
      await switchUser.logout();
      switchUser = await signIn(switchEmail); // OWNER now → the token must carry MFA
      biz = await findQaBiz();
    }
    qaBizId = biz!;
    // Same order as the app's setup: the profile first (onboarding refuses one
    // without a legal name and a valid tax id).
    final profile = await switchUser.call('PUT', '/business/profile',
        body: {'legalName': qaBizName, 'businessType': 'OSEK_PATUR', 'taxId': '123456782'}, business: qaBizId);
    expect(profile.status, 200, reason: 'profile $profile');
    final onboarding = await switchUser.call('PUT', '/business/onboarding', body: {'completed': true}, business: qaBizId);
    expect(onboarding.status, 200, reason: 'onboarding $onboarding');

    final members = (await team())['members'] as List;
    staffUserId = members.cast<Map<String, dynamic>>().firstWhere((m) => m['email'] == staffEmail)['userId'] as String;

    final c = await owner.post('/customers',
        {'name': 'QA עסק $runTag', 'customerType': 'INDIVIDUAL', 'email': 'qa-business-$runTag@example.test'});
    expect(c.status, 201, reason: 'customer $c');
    qaCustomerId = c.map['id'] as String;
    final consent = await owner.post('/customers/$qaCustomerId/consent', {'method': 'VERBAL_IN_APP'});
    expect(consent.status, anyOf(200, 201), reason: 'consent $consent');
  });

  tearDownAll(() async {
    if (overdueDocId != null && !overdueCredited) {
      // test 4 did not run: still credit the fixture so the dev business has no stray overdue invoice
      await owner.post('/documents/$overdueDocId/credit', {'scopeKey': 'default', 'lines': lines},
          {'Idempotency-Key': idemKey()});
    }
    await owner.put('/business/members/$roleUserId/role', {'role': 'READ_ONLY'});
    for (final u in [owner, staff, viewer, accountant, cpaRep, roleUser, switchUser]) {
      await u.logout();
    }
    await keychain.deleteAll();
  });

  // ------------------------------------------------------------- BE-01 money

  testWidgets('BE-01 /dashboard unpaid_* and overdue_* = Σ open 300/305 (server aggregate), '
      'inbox money identical; AT-51 employee gets counts without amounts', (tester) async {
    // A parallel writer can move totals between the two reads: up to 3 tries.
    for (var attempt = 1;; attempt++) {
      final s = await summary(owner);
      final list = await unpaidFromList(owner);
      final inbox = await owner.ok('/mobile/inbox?limit=10');
      final money = inbox['money'] as Map<String, dynamic>;
      final same = minor(s['unpaid_total']) == list.open &&
          s['unpaid_count'] == list.total &&
          minor(s['overdue_total']) == list.overdue &&
          s['overdue_count'] == list.overdueCount &&
          minor(money['openMinor']) == minor(s['unpaid_total']) &&
          minor(money['overdueMinor']) == minor(s['overdue_total']);
      if (same || attempt == 3) {
        expect(list.total, lessThanOrEqualTo(500), reason: 'more than 500 open documents: list cannot verify');
        expect(minor(s['unpaid_total']), list.open, reason: 'unpaid_total vs Σ openMinor');
        expect(s['unpaid_count'], list.total, reason: 'unpaid_count');
        expect(s['unpaid_balance'], s['unpaid_total'], reason: 'V1 alias');
        expect(minor(s['overdue_total']), list.overdue, reason: 'overdue_total (due, else issue+30 < today)');
        expect(s['overdue_count'], list.overdueCount, reason: 'overdue_count');
        expect(minor(money['openMinor']), minor(s['unpaid_total']), reason: 'BE-05 money = BE-01');
        expect(minor(money['overdueMinor']), minor(s['overdue_total']), reason: 'BE-05 overdue = BE-01');
        break;
      }
    }
    final st = await summary(staff);
    expect(st['unpaid_total'], isNull, reason: 'AT-51: EMPLOYEE /dashboard without amounts');
    expect(st['overdue_total'], isNull);
    expect(st['month_income'], isNull);
    expect(st['unpaid_count'], isA<int>(), reason: 'counts stay');
    expect((await staff.ok('/mobile/inbox?limit=10'))['money'], isNull, reason: 'AT-51: inbox money null');
  });

  testWidgets('BE-01 deltas: finalized 305 past due → unpaid +₪11.80, overdue +1, month_income +₪11.80',
      (tester) async {
    final before = await summary(owner);
    final yesterday = isoDay(DateTime.now().subtract(const Duration(days: 1)));
    final created = await owner.post('/documents', {
      'documentType': 'TAX_INVOICE',
      'customerId': qaCustomerId,
      'currency': 'ILS',
      'dueDate': yesterday,
      'lines': lines,
    });
    expect(created.status, 201, reason: '$created');
    final id = created.map['id'] as String;
    final fin = await owner.post('/documents/$id/finalize', {'scopeKey': 'default'}, {'Idempotency-Key': idemKey()});
    expect(fin.status, 200, reason: '$fin');
    expect(fin.map['status'], 'FINALIZED');
    overdueDocId = id;
    final art = await owner.post('/documents/$id/artifact');
    expect(art.status, anyOf(200, 201), reason: 'artifact $art');

    final after = await summary(owner);
    final add = BigInt.from(lineTotal);
    expect(minor(after['unpaid_total']) - minor(before['unpaid_total']), add, reason: 'unpaid_total delta');
    expect((after['unpaid_count'] as int) - (before['unpaid_count'] as int), 1);
    expect(minor(after['overdue_total']) - minor(before['overdue_total']), add, reason: 'due yesterday = overdue');
    expect((after['overdue_count'] as int) - (before['overdue_count'] as int), 1);
    expect(minor(after['month_income']) - minor(before['month_income']), add, reason: 'month income Σ305');
  });

  testWidgets('BE-01 §6.H owner home: money card = /dashboard, ≤3 "לטיפול" cards in priority order; '
      'AT-27 OVERDUE card → "שלח תזכורות" e-mails the reminder (1 tap)', (tester) async {
    expect(overdueDocId, isNotNull, reason: 'depends on the BE-01 delta test');
    await launchAs(tester, owner);
    expect(find.byType(HomeScreen), findsOneWidget);
    await waitFor(tester, find.byKey(const Key('home-money')));

    // The card settles on the server aggregate (cache first, then network).
    final s = await summary(owner);
    await waitUntil(tester, () {
      final card = tester.widget<MoneyCard>(find.byKey(const Key('home-money')));
      return card.amountMinor == minor(s['unpaid_total']);
    }, 'money card = /dashboard unpaid_total ${s['unpaid_total']}', seconds: 20);
    final card = tester.widget<MoneyCard>(find.byKey(const Key('home-money')));
    expect(card.label, InboxHe.moneyLabel);
    final overdue = minor(s['overdue_total']);
    expect(overdue, greaterThan(BigInt.zero), reason: 'fixture is overdue');
    expect(card.secondaryMinor, overdue, reason: '"מתוכם באיחור" = overdue_total');
    expect(card.secondaryLabel, InboxHe.moneyOverdue);

    // "לטיפול": at most 3 cards, in the server's priority order.
    final inbox = await owner.ok('/mobile/inbox?limit=10');
    final apiKinds = [for (final c in (inbox['cards'] as List).cast<Map<String, dynamic>>()) c['kind'] as String];
    final shown = keysTopDown(tester, 'inbox-').map((k) => k.substring('inbox-'.length)).toList();
    expect(shown.length, lessThanOrEqualTo(3), reason: '≤3 cards on H');
    expect(shown, isNotEmpty);
    var last = -1;
    for (final k in shown) {
      final at = apiKinds.indexOf(k);
      expect(at, greaterThan(last), reason: 'card $k out of priority order (server: $apiKinds, shown: $shown)');
      last = at;
    }
    if (apiKinds.length > 3) {
      expect(await scrollToFind(tester, find.byKey(const Key('home-more-cards'))), isTrue,
          reason: '"עוד N" under the 3 cards (server: $apiKinds)');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000), warnIfMissed: false);
      await pumpFor(tester, const Duration(milliseconds: 500));
    }
    expectScreenRules('H owner');

    // AT-27 (J10): one tap on the OVERDUE card's action sends the e-mail reminder.
    expect(apiKinds, contains('OVERDUE'));
    final overdueCard = find.byKey(const Key('inbox-OVERDUE'));
    if (overdueCard.evaluate().isEmpty) {
      markTestSkipped('AT-27 UI part: OVERDUE is not among the first 3 cards (${apiKinds.take(3)})');
      return;
    }
    final since = DateTime.now().millisecondsSinceEpoch - 1000;
    final taps = TapCounter();
    await taps.tap(tester, find.descendant(of: overdueCard, matching: find.text(InboxHe.actSendReminders)));
    Map<String, dynamic>? mail;
    await waitUntil(tester, () {
      // §9.3 P0: the reminder IS the document e-mail (POST /documents/:id/send
      // → /deliveries/:id/process), so its subject is the document's, not "תזכורת".
      mail = newestMail('qa-business-$runTag@example.test', since, (s) => s.contains('סטודיו תבל לדוגמה'));
      return mail != null;
    }, 'reminder e-mail to the QA customer', seconds: 20);
    expect(taps.taps, 1, reason: 'J10 ≤1 tap');
    expect('${mail!['subject']}', contains('סטודיו תבל לדוגמה'));
  });

  testWidgets('BE-36 + BE-01: full credit closes the overdue 305 → unpaid/overdue back, month_income −₪11.80',
      (tester) async {
    expect(overdueDocId, isNotNull, reason: 'depends on the BE-01 delta test');
    final before = await summary(owner);
    final r = await owner.post('/documents/$overdueDocId/credit', {'scopeKey': 'default', 'lines': lines},
        {'Idempotency-Key': idemKey()});
    expect(r.status, 201, reason: '$r');
    overdueCredited = true;
    final creditId = r.map['creditDocumentId'] as String;
    await owner.post('/documents/$creditId/artifact');
    final after = await summary(owner);
    final sub = BigInt.from(lineTotal);
    expect(minor(before['unpaid_total']) - minor(after['unpaid_total']), sub);
    expect((before['unpaid_count'] as int) - (after['unpaid_count'] as int), 1);
    expect(minor(before['overdue_total']) - minor(after['overdue_total']), sub);
    expect(minor(before['month_income']) - minor(after['month_income']), sub, reason: 'Σ305 − Σ330');
    final row = (await owner.ok('/documents/$overdueDocId'))['document'] as Map<String, dynamic>;
    expect(row['credited_minor'], '$lineTotal');
    expect(row['open_minor'], '0');
  });

  // ------------------------------------------------- presets: H, B, ＋ tabs

  testWidgets('AT-41 EMPLOYEE: no money card, no צוות/מיתוג/דוחות, "בקש תשלום" only (§19 q7)', (tester) async {
    await launchAs(tester, staff);
    await waitFor(tester, find.byKey(const Key('intent-request')));
    await waitUntil(tester, () => find.byKey(const Key('home-money')).evaluate().isEmpty,
        'no money card for EMPLOYEE', seconds: 15);
    expect(find.byKey(const Key('intent-paid')), findsNothing, reason: 'no payment.record');
    expect(find.byKey(const Key('home-role-tag')), findsOneWidget, reason: 'role tag for a non-owner');
    expect(find.byKey(const Key('tab-create')), findsOneWidget);
    expectScreenRules('H employee');

    await openBusinessTab(tester);
    final rows = businessRowKeys();
    for (final hidden in ['team', 'branding', 'reports', 'profile', 'approvals', 'reminders', 'numbering']) {
      expect(rows, isNot(contains(hidden)), reason: 'AT-41: "$hidden" row for EMPLOYEE');
    }
    expect(rows, containsAll(['expenses', 'account']));
    expectScreenRules('B employee');
  });

  testWidgets('AT-40 READ_ONLY (צפייה): no ＋, no intent buttons, no "לטיפול"; money card; B = החשבון שלי',
      (tester) async {
    await launchAs(tester, viewer);
    await waitFor(tester, find.byKey(const Key('home-money')), seconds: 20);
    expect(find.byKey(const Key('tab-create')), findsNothing);
    expect(find.byKey(const Key('intent-request')), findsNothing);
    expect(find.byKey(const Key('intent-paid')), findsNothing);
    expect(find.text(InboxHe.todo), findsNothing, reason: '§4.4: צפייה has no "לטיפול"');
    expectScreenRules('H viewer');
    await openBusinessTab(tester);
    expect(businessRowKeys(), {'account'});
  });

  for (final who in const [accountantEmail, cpaRepEmail]) {
    testWidgets('AT-44 + AT-26 accountant ($who): tabs בית(R)·לקוחות·עסק, no ＋, R period by vatReporting',
        (tester) async {
      final u = who == accountantEmail ? accountant : cpaRep;
      final me = await u.ok('/me');
      await launchAs(tester, u);
      expect(businessContext.caps.homeIsReports, isTrue);
      expect(find.byType(ReportsScreen), findsOneWidget, reason: 'AT-26: home tab = R');
      expect(find.byType(HomeScreen), findsNothing);
      expect(find.byKey(const Key('tab-create')), findsNothing, reason: 'AT-44: no ＋');
      expect(find.byKey(const Key('tab-home')), findsOneWidget);
      expect(find.byKey(const Key('tab-people')), findsOneWidget);
      expect(find.byKey(const Key('tab-business')), findsOneWidget);

      // §6.R: default period = the current VAT period (bimonthly unless MONTHLY; NONE/exempt = year).
      final vat = me['vatReporting'] as String?;
      final n = DateTime.now();
      final months = vat == 'MONTHLY' ? 1 : 2;
      final start = ((n.month - 1) ~/ months) * months + 1;
      final end = start + months - 1;
      final label = vat == 'NONE'
          ? '${n.year}'
          : months == 1
              ? '${n.month}.${n.year}'
              : '$start–$end.${n.year}';
      final reportRead = ((me['permissions'] as List?) ?? const []).contains('report:read');
      if (reportRead) {
        await waitFor(tester, find.byKey(const Key('report-card-income')), seconds: 20);
        expect(periodLabel(tester), label, reason: 'AT-26 period label $label (vatReporting=$vat)');
        expect(find.byKey(const Key('report-card-expenses')), findsOneWidget, reason: '§11 accountant cards');
      }
      expectScreenRules('R accountant');

      await openBusinessTab(tester);
      final rows = businessRowKeys();
      expect(rows, isNot(contains('team')));
      expect(rows, isNot(contains('reports')), reason: 'R is the home tab');
      expect(rows, isNot(contains('branding')));
      if (who == cpaRepEmail) expect(rows, contains('numbering'), reason: '§6.B: מספור ואישורים for מייצג');
    });
  }

  testWidgets('§6.B owner: ≤10 rows from the closed list, AT-90 on B · B·צוות · R', (tester) async {
    await launchAs(tester, owner);
    await openBusinessTab(tester);
    expect(find.byType(BusinessScreen), findsOneWidget);
    await pumpFor(tester, const Duration(seconds: 2)); // reminders switch (BE-19)
    final rows = businessRowKeys();
    expect(rows.length, lessThanOrEqualTo(10), reason: 'owner sees at most 10 rows: $rows');
    expect(allBusinessRows.containsAll(rows), isTrue, reason: 'unknown row in $rows');
    expect(rows, containsAll(['reports', 'expenses', 'team', 'profile', 'branding', 'approvals', 'shaam', 'account']),
        reason: 'studio has >1 member → אישורים shown (§13.6)');
    expect(rows, isNot(contains('numbering')), reason: 'owner: numbering only in setup');
    expectScreenRules('B owner');

    await tester.tap(find.byKey(const Key('brow-team')));
    await waitFor(tester, find.byKey(const Key('team-invite')), seconds: 20);
    await waitFor(tester, find.byKey(Key('member-$staffUserId')));
    expectScreenRules('B·צוות');
    expect(find.text(TeamHe.invite), findsOneWidget);
    navigatorKey.currentState!.pop();
    await pumpFor(tester, const Duration(seconds: 1));

    await tester.tap(find.byKey(const Key('brow-reports')));
    await waitFor(tester, find.byType(ReportsScreen), seconds: 20);
    await waitFor(tester, find.byKey(const Key('report-card-income')), seconds: 20);
    expect(find.byKey(const Key('report-card-vat')), findsOneWidget, reason: '§11 owner: income · VAT · debts');
    expect(find.byKey(const Key('report-card-receivables')), findsOneWidget);
    expect(find.byKey(const Key('send-to-accountant')), findsOneWidget, reason: 'primary "שלח לרו״ח"');
    expectScreenRules('R owner');
  });

  // ------------------------------------------------------------- team (§12)

  testWidgets('AT-24 J8: invite an employee in ≤4 taps → invitation role EMPLOYEE', (tester) async {
    final email = 'qa-invite-emp-$runTag@tevel.test';
    await launchAs(tester, owner);
    final taps = TapCounter();
    await taps.tap(tester, find.byKey(const Key('tab-business')));
    await waitFor(tester, find.byKey(const Key('brow-team')));
    await taps.tap(tester, find.byKey(const Key('brow-team')));
    await waitFor(tester, find.byKey(const Key('team-invite')), seconds: 20);
    await taps.tap(tester, find.byKey(const Key('team-invite')));
    await waitFor(tester, find.byKey(const Key('text-email')));
    // E-mail has auto focus (typing is not counted, §1 F3.1); preset "עובד" is the default.
    expect(find.byKey(const Key('choice-preset-employee')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('text-email')), email);
    await tester.pump();
    expectScreenRules('S13 הזמנה', scope: find.byType(EditorSheet));
    await taps.tap(tester, find.byKey(const Key('editor-save')));
    await waitUntil(tester, () => find.byKey(const Key('editor-save')).evaluate().isEmpty, 'invite sheet closed');
    expect(taps.taps, lessThanOrEqualTo(4), reason: 'J8 ≤4 taps');

    final inv = invitationFor(await team(), email);
    expect(inv, isNotNull, reason: 'invitation for $email');
    expect(inv!['role'], 'EMPLOYEE');
    expect((inv['permissions'] as List?) ?? const [], isEmpty, reason: 'employee default = no grants');
    await pumpFor(tester, const Duration(seconds: 2)); // B·צוות reloads after the invite
    expect(await scrollToFind(tester, find.byKey(Key('invitation-${inv['id']}')), steps: 15), isTrue,
        reason: 'pending invitation row in B·צוות (lazy list)');
    final revoke = await owner.post('/business/invitations/${inv['id']}/revoke');
    expect(revoke.status, 200, reason: 'cleanup revoke $revoke');
  });

  testWidgets('AT-25 J8b (P2): "הזמן רואה חשבון" → invitation role ACCOUNTANT_REP', (tester) async {
    final email = 'qa-invite-cpa-$runTag@tevel.test';
    await launchAs(tester, owner);
    await openBusinessTab(tester);
    await tester.tap(find.byKey(const Key('brow-team')));
    await waitFor(tester, find.byKey(const Key('team-invite-accountant')), seconds: 20);
    await tester.tap(find.byKey(const Key('team-invite-accountant')));
    await waitFor(tester, find.byKey(const Key('text-email')));
    await tester.enterText(find.byKey(const Key('text-email')), email);
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('editor-save')));
    await tester.tap(find.byKey(const Key('editor-save')));
    await waitUntil(tester, () => find.byKey(const Key('editor-save')).evaluate().isEmpty, 'invite sheet closed');

    final inv = invitationFor(await team(), email);
    expect(inv, isNotNull, reason: 'invitation for $email');
    expect(inv!['role'], 'ACCOUNTANT_REP', reason: 'BE-04 live: no READ_ONLY+grants fallback');
    final revoke = await owner.post('/business/invitations/${inv['id']}/revoke');
    expect(revoke.status, 200, reason: 'cleanup revoke $revoke');
  });

  testWidgets('AT-50 S13 "חבר צוות" (employee): only the "מפיק בעצמו" switch, no settings/team switches',
      (tester) async {
    await launchAs(tester, owner);
    await openBusinessTab(tester);
    await tester.tap(find.byKey(const Key('brow-team')));
    final row = find.byKey(Key('member-$staffUserId'));
    await waitFor(tester, row, seconds: 20);
    await tester.ensureVisible(row);
    await tester.tap(row);
    await waitFor(tester, find.byKey(const Key('switch-issuer')));
    // Scoped to the sheet: B underneath has its own "תזכורות אוטומטיות" switch (BE-19).
    expect(find.descendant(of: find.byType(EditorSheet), matching: find.byType(Switch)), findsOneWidget,
        reason: 'one switch only: מפיק בעצמו');
    expect(find.text(TeamHe.issuer), findsOneWidget);
    for (final p in ['employee', 'partner', 'accountantRep']) {
      expect(find.byKey(Key('choice-preset-$p')), findsOneWidget, reason: 'preset $p');
    }
    for (final banned in ['business:configure', 'membership:manage', 'document:cancel', 'approval:decide']) {
      expect(find.textContaining(banned), findsNothing);
    }
    expectScreenRules('S13 חבר צוות', scope: find.byType(EditorSheet));
    navigatorKey.currentState!.pop(); // close without saving
    await pumpFor(tester, const Duration(seconds: 1));
  });

  testWidgets('AT-51 (P2, BE-03): EMPLOYEE/READ_ONLY write & export gates', (tester) async {
    final excel = await staff.post('/exports/excel', {'fromDate': '${DateTime.now().year}-01-01', 'toDate': today()});
    expect(excel.status, 403, reason: 'EMPLOYEE /exports/excel $excel');
    final patch = await staff.call('PATCH', '/customers/$qaCustomerId', body: {'notes': 'QA'});
    expect(patch.status, 403, reason: 'EMPLOYEE PATCH /customers notes $patch');
    final docs = await owner.ok('/documents?limit=20');
    final others = (docs['documents'] as List)
        .cast<Map<String, dynamic>>()
        .where((d) => d['status'] != 'DRAFT' && d['createdBy'] != null)
        .toList();
    if (others.isNotEmpty) {
      final pdf = await staff.get('/documents/${others.first['id']}/pdf');
      expect(pdf.status, 403, reason: 'EMPLOYEE pdf of another member\'s document');
    }
    final acc = await viewer.post('/exports/accountant', {'fromDate': '${DateTime.now().year}-01-01', 'toDate': today()});
    expect(acc.status, 403, reason: 'READ_ONLY /exports/accountant $acc');
    final members = await staff.get('/business/members');
    expect(members.status, 403, reason: 'EMPLOYEE /business/members');
  });

  // ---------------------------------------------- settings (§13) · R · S14

  testWidgets('AT-43b + AT-54 solo עוסק פטור: no "אישורים" row, THRESHOLD w/o approver → 422; '
      'R: exempt ceiling, no VAT card', (tester) async {
    final me = await switchUser.call('GET', '/me', business: qaBizId);
    expect(me.status, 200, reason: '$me');
    expect(me.map['memberCount'], 1);
    expect(me.map['businessType'], 'OSEK_PATUR');
    final put = await switchUser.call('PUT', '/settings/approval',
        body: {'mode': 'THRESHOLD', 'thresholdMinor': '500000', 'selfApprovalAllowed': false}, business: qaBizId);
    expect(put.status, 422, reason: 'AT-43b $put');
    expect(put.error, 'APPROVAL_NO_OTHER_APPROVER');

    await launchAs(tester, switchUser, businessId: qaBizId);
    expect(businessContext.caps.preset, Preset.owner);
    await openBusinessTab(tester);
    final rows = businessRowKeys();
    expect(rows, isNot(contains('approvals')), reason: '§13.6 only with another member');
    expect(rows, containsAll(['reports', 'team', 'profile']));
    expectScreenRules('B solo');

    await tester.tap(find.byKey(const Key('brow-reports')));
    await waitFor(tester, find.byType(ReportsScreen), seconds: 20);
    final ceiling = (me.map['rules'] as Map?)?['exemptCeilingMinor'];
    if (ceiling != null) {
      await waitFor(tester, find.byKey(const Key('exempt-ceiling')), seconds: 20);
    } else {
      expect(find.byKey(const Key('exempt-ceiling')), findsNothing);
    }
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.byKey(const Key('report-card-vat')), findsNothing, reason: '§4.7: no VAT report for פטור');
    if (find.byKey(const Key('report-card-income')).evaluate().isNotEmpty) {
      expect(periodLabel(tester), '${DateTime.now().year}', reason: 'פטור: period = calendar year');
    }
    expectScreenRules('R פטור');
  });

  testWidgets('AT-29 J12: switch business in 2 taps; caps and cache follow the new business', (tester) async {
    await launchAs(tester, switchUser, businessId: studioId);
    expect(businessContext.caps.preset, Preset.employee);
    await waitUntil(tester, () => find.byKey(const Key('home-money')).evaluate().isEmpty, 'employee: no money');
    final taps = TapCounter();
    await taps.tap(tester, find.byKey(const Key('home-switch-business')));
    await waitFor(tester, find.byKey(Key('s14-$qaBizId')));
    expectScreenRules('S14');
    await taps.tap(tester, find.byKey(Key('s14-$qaBizId')));
    await waitUntil(tester, () => session.business?.businessId == qaBizId, 'switched to $qaBizName', seconds: 20);
    await waitUntil(tester, () => businessContext.caps.preset == Preset.owner, 'caps of the new business', seconds: 20);
    expect(taps.taps, 2, reason: 'J12 = 2 taps');
    await waitFor(tester, find.byType(AppShell));
    await waitFor(tester, find.byKey(const Key('home-money')), seconds: 20);
    expect(find.text(qaBizName), findsWidgets, reason: 'header shows the new business');
    expect(find.byKey(const Key('home-role-tag')), findsNothing, reason: 'owner: no role tag');
    expect(find.text('סטודיו תבל לדוגמה'), findsNothing, reason: 'no stale data of the old business');
  });

  testWidgets('AT-46 role changed elsewhere → foreground (>60 s) → UI follows', (tester) async {
    await launchAs(tester, roleUser);
    expect(businessContext.caps.preset, Preset.viewer);
    expect(find.byKey(const Key('intent-request')), findsNothing);
    try {
      final r = await owner.put('/business/members/$roleUserId/role', {'role': 'EMPLOYEE'});
      expect(r.status, 200, reason: '$r');
      session.meFetchedAt = DateTime.now().subtract(const Duration(minutes: 2));
      // Legal order only (AppLifecycleListener asserts it), and no pump while
      // hidden/paused: the device binding disables frames, a pump never returns.
      for (final s in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await waitFor(tester, find.byKey(const Key('intent-request')), seconds: 20);
      expect(businessContext.caps.preset, Preset.employee);
      expect(find.byKey(const Key('tab-create')), findsOneWidget);
      // H re-renders after the caps change; give its reload a moment before judging.
      for (var i = 0; i < 20 && find.byKey(const Key('home-money')).evaluate().isNotEmpty; i++) {
        await pumpFor(tester, const Duration(milliseconds: 500));
      }
      expect(find.byKey(const Key('home-money')), findsNothing, reason: 'EMPLOYEE: no money card');
    } finally {
      await owner.put('/business/members/$roleUserId/role', {'role': 'READ_ONLY'});
    }
  });

  // ------------------------------------------------- inbox cards (§6.H.1)

  String? rejectedDraftId;

  testWidgets('AT-23 rejection: reason required; submitter sees MY_REJECTED with the reason', (tester) async {
    final created = await staff.post('/documents', {
      'documentType': 'TAX_INVOICE',
      'customerId': qaCustomerId,
      'currency': 'ILS',
      'lines': lines,
    });
    expect(created.status, 201, reason: '$created');
    final id = created.map['id'] as String;
    rejectedDraftId = id;
    final sub = await staff.post('/documents/$id/submit');
    expect(sub.status, 200, reason: '$sub');
    expect(sub.map['status'], 'PENDING_APPROVAL');
    final empty = await owner.post('/documents/$id/reject', {'reason': ''});
    expect(empty.status, anyOf(400, 422), reason: 'reason is required $empty');
    final reason = 'QA חסר פירוט $runTag';
    final rej = await owner.post('/documents/$id/reject', {'reason': reason});
    expect(rej.status, 200, reason: '$rej');

    final inbox = await staff.ok('/mobile/inbox?limit=10');
    final card = (inbox['cards'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((c) => c['kind'] == 'MY_REJECTED', orElse: () => const {});
    expect(card, isNotEmpty, reason: 'MY_REJECTED for the submitter');
    expect(card['documentIds'], contains(id));
    final detail = card['detail'] as Map<String, dynamic>;
    expect(detail['documentId'], id, reason: 'newest rejection first');
    expect((detail['rejection'] as Map)['reason'], reason);

    await launchAs(tester, staff);
    final ui = find.byKey(const Key('inbox-MY_REJECTED'));
    await waitFor(tester, ui, seconds: 20);
    expect(keysTopDown(tester, 'inbox-').first, 'inbox-MY_REJECTED', reason: 'priority 90 = first for staff');
    expect(find.descendant(of: ui, matching: find.text(InboxHe.actFix)), findsOneWidget);
    if (card['count'] == 1) {
      expect(find.descendant(of: ui, matching: find.textContaining(reason)), findsOneWidget);
    } else {
      expect(find.descendant(of: ui, matching: find.text(InboxHe.myRejectedMany(card['count'] as int))),
          findsOneWidget);
    }
  });

  testWidgets('AT-22 J7: employee re-submits → owner card "פתח" → D "אשר והפק" = 2 taps → finalized',
      (tester) async {
    final id = rejectedDraftId;
    expect(id, isNotNull, reason: 'depends on AT-23');
    final sub = await staff.post('/documents/$id/submit');
    expect(sub.status, 200, reason: 'resubmit $sub');
    final inbox = await owner.ok('/mobile/inbox?limit=10');
    final card = (inbox['cards'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((c) => c['kind'] == 'APPROVAL_NEEDED', orElse: () => const {});
    expect(card, isNotEmpty, reason: 'APPROVAL_NEEDED for the approver');
    expect(card['documentIds'], contains(id));
    final staffCards = ((await staff.ok('/mobile/inbox?limit=10'))['cards'] as List).cast<Map<String, dynamic>>();
    expect(staffCards.where((c) => c['kind'] == 'APPROVAL_NEEDED'), isEmpty, reason: 'EMPLOYEE has no approval.decide');

    await launchAs(tester, owner);
    final ui = find.byKey(const Key('inbox-APPROVAL_NEEDED'));
    await waitFor(tester, ui, seconds: 20);
    expect(keysTopDown(tester, 'inbox-').first, 'inbox-APPROVAL_NEEDED', reason: 'priority 100 = first');
    if (card['count'] != 1) {
      // Someone else's submission is also pending: the card opens L, not D.
      final ok = await owner.post('/documents/$id/approve', const {}, {'Idempotency-Key': idemKey()});
      expect(ok.status, 200, reason: '$ok');
      markTestSkipped('AT-22 tap count: ${card['count']} documents pending (card opens L); approved over API');
      return;
    }
    final taps = TapCounter();
    await taps.tap(tester, find.descendant(of: ui, matching: find.text(InboxHe.actOpen)));
    final approve = find.text(DocumentHe.approveAndIssue);
    await waitFor(tester, approve, seconds: 20);
    await taps.tap(tester, approve);
    String? status;
    for (var i = 0; i < 40; i++) {
      await pumpFor(tester, const Duration(milliseconds: 500));
      status = ((await owner.ok('/documents/$id'))['document'] as Map)['status'] as String?;
      if (status != 'PENDING_APPROVAL' && status != 'DRAFT') break;
    }
    expect(status, isNot(anyOf('PENDING_APPROVAL', 'DRAFT')), reason: 'approved and issued');
    expect(taps.taps, 2, reason: 'J7 = 2 taps');
  });

  testWidgets('AT-23 follow-up: a rejected draft can still be deleted (DELETE /documents/:id)', (tester) async {
    final created = await staff.post('/documents', {
      'documentType': 'TAX_INVOICE',
      'customerId': qaCustomerId,
      'currency': 'ILS',
      'lines': lines,
    });
    expect(created.status, 201, reason: '$created');
    final id = created.map['id'] as String;
    expect((await staff.post('/documents/$id/submit')).status, 200);
    expect((await owner.post('/documents/$id/reject', {'reason': 'QA למחיקה $runTag'})).status, 200);
    final del = await staff.delete('/documents/$id');
    expect(del.status, 200, reason: 'submitter deletes the rejected draft: $del');
  });
}
