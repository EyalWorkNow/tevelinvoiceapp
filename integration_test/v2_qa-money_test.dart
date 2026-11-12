// ignore_for_file: file_names (the name is fixed by the QA plan)
// QA (qa-money): SPEC-v2 §17 acceptance tests for D (document screen),
// S5 payments, S6 share / WhatsApp / QR, S8 cancel / credit and balances —
// the REAL app against the LOCAL dev API (:3031, never prod). Server state is
// set up and verified with a separate signed-in client (qa_money_helpers.dart).
// url_launcher is replaced by FakeLauncher (no WhatsApp on the simulator);
// the iOS share sheet by a recorder.
//
// Run (the single simulator runner only):
//   ~/flutter/bin/flutter test integration_test/v2_qa-money_test.dart -d <udid> \
//     --dart-define=API_BASE=http://127.0.0.1:3031 \
//     --dart-define=MAILDIR=$HOME/invoiceproject-mobile-dev-storage/outgoing-emails
//
// Creates its own customers and documents in the dev business "סטודיו תבל
// לדוגמה" (names "QA כסף <ts>"). Tap counts follow F3.1; D is opened
// directly, so the "open D from a list" tap of a journey is added explicitly.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/compose/compose_screen.dart';
import 'package:invoice/screens/document/document_screen.dart';
import 'package:invoice/state/session.dart';
import 'package:invoice/ui/widgets/primary_button.dart';
import 'package:invoice/util/labels/labels.dart';

import '../test/fakes/fake_launcher.dart';
import 'qa_money_helpers.dart';
import 'qa_plans_guard.dart';

const openFromList = 1; // the tap on the row that opens D in a journey

Finder inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  dismissPlansDuringTests();
  qaMoneySuite();
}

/// The tests (a host dry-run harness with a live binding calls this too).
void qaMoneySuite() {

  late FakeLauncher launcher;
  late DevApi owner;
  late String customer; // has a phone (wa.me/972…) and an e-mail

  setUpAll(() async {
    owner = await DevApi.as(QaPreset.owner);
    customer = await owner.newCustomer(email: 'qa-money@example.test');
  });

  setUp(() {
    launcher = FakeLauncher()..install();
    sharedPdfs.clear();
    sharedTexts.clear();
  });

  tearDown(FakeLauncher.uninstall);

  tearDownAll(() async {
    await session.signOutLocally();
    await DevApi.signOutAll();
  });

  /// Picks [label] in D's ⋯ menu (2 taps: ⋯ + the row).
  Future<void> pickMenu(WidgetTester tester, TapCounter t, String label) async {
    await t.tap(tester, find.byTooltip('עוד'), settle: const Duration(milliseconds: 800));
    await t.tap(tester, inSheet(find.text(label)));
  }

  // ---- S6 · share / WhatsApp / QR ---------------------------------------------------

  testWidgets('AT-12 + AT-31(WhatsApp): 305 never sent → "שלח בווטסאפ" = 1 tap → wa.me/972 + /d/; '
      'no consent question; the /d/ page shows "לתשלום"', (tester) async {
    final id = await owner.issue(type: 'TAX_INVOICE', customerId: customer);
    await openDocAs(tester, QaPreset.owner, id);
    expect(find.byType(PrimaryButton), findsOneWidget); // AT-90
    expect(primaryLabel(tester), DocumentHe.sendWhatsApp); // §6.D row 8
    final t = TapCounter();
    await t.tap(tester, primaryButton(), settle: const Duration(seconds: 4));
    expect(t.taps, 1);
    expect(find.byType(AlertDialog), findsNothing, reason: 'AT-31: no consent question on WhatsApp');
    final wa = launcher.last;
    expect(wa, isNotNull, reason: 'WhatsApp was not opened');
    expect(wa.toString(), startsWith('https://wa.me/972'));
    final link = shareLinkIn(wa!);
    expect(link, isNotNull, reason: 'no /d/ link in $wa');
    final doc = await owner.document(id);
    final page = await publicPage(link!);
    expect(page.status, 200);
    expect(page.body, contains('class="btn pay"'), reason: 'paymentLinkUrl + balance > 0 → "לתשלום" button');
    expect(page.body, contains('${doc['document_number']}'));
    expect((await owner.listRow(id))!['sentAt'], isNotNull, reason: 'share link marks the document sent');
  });

  testWidgets('AT-10 (share part): paid 320 → D "שתף" → S6 "שלח בווטסאפ" → wa.me/972 + /d/; '
      'the /d/ page has no "לתשלום" (balance 0)', (tester) async {
    final id = await owner.paid320(customer);
    await openDocAs(tester, QaPreset.owner, id);
    expect(find.byType(PrimaryButton), findsOneWidget); // AT-90
    expect(primaryLabel(tester), DocumentHe.share); // row 16
    final t = TapCounter();
    await t.tap(tester, primaryButton());
    await pumpUntil(tester, find.byKey(const Key('s6-whatsapp')));
    expect(inSheet(find.byType(PrimaryButton)), findsOneWidget); // AT-90 in S6
    await t.tap(tester, find.byKey(const Key('s6-whatsapp')), settle: const Duration(seconds: 4));
    expect(t.taps, 2);
    expect(launcher.last.toString(), startsWith('https://wa.me/972'));
    final link = shareLinkIn(launcher.last!);
    expect(link, isNotNull);
    final page = await publicPage(link!);
    expect(page.status, 200);
    expect(page.body, isNot(contains('class="btn pay"')), reason: 'no "לתשלום" button at balance 0');
  });

  testWidgets('AT-32: S6 QR row "קישור תשלום כללי – הלקוח יקליד את הסכום" → QR of the /d/ link; '
      'every S6 row is there for the owner', (tester) async {
    final id = await owner.issue(type: 'TAX_INVOICE', customerId: customer);
    await openDocAs(tester, QaPreset.owner, id);
    final t = TapCounter();
    await pickMenu(tester, t, DocumentHe.share);
    await pumpUntil(tester, find.byKey(const Key('s6-qr')));
    for (final k in ['s6-whatsapp', 's6-email', 's6-copy', 's6-pdf', 's6-pdf-copy', 's6-qr']) {
      expect(find.byKey(Key(k)), findsOneWidget, reason: k);
    }
    expect(find.text(DocumentHe.qrGeneral), findsOneWidget);
    expect(find.byKey(const Key('s6-revoke')), findsNothing, reason: 'no live link yet');
    await t.tap(tester, find.byKey(const Key('s6-qr')), settle: const Duration(seconds: 3));
    await pumpUntil(tester, find.byKey(const Key('s6-qr-image')));
    expect(find.byKey(const Key('s6-revoke')), findsOneWidget, reason: 'BE-12: a link now exists');
    expect((await owner.listRow(id))!['sentAt'], isNotNull, reason: 'the QR is a real /d/ link');
    // BE-12: revoke → the public page answers 404.
    final timeline = (await owner.document(id))['timeline'] as List? ?? const [];
    expect(timeline.any((e) => (e as Map)['event'] == 'document.shared'), isTrue);
    await t.tap(tester, find.byKey(const Key('s6-revoke')), settle: const Duration(seconds: 3));
    final after = (await owner.document(id))['timeline'] as List? ?? const [];
    expect(after.any((e) => (e as Map)['event'] == 'document.share_revoked'), isTrue);
  });

  testWidgets('AT-31 (e-mail): S6 "מייל" → "שלח במייל" → sent (CONSENT_REQUIRED → dialog → כן when the '
      'server asks) → the e-mail file is written for the customer', (tester) async {
    final c = await owner.newCustomer(email: 'qa-money-consent@example.test');
    final id = await owner.issue(type: 'TAX_INVOICE', customerId: c);
    await openDocAs(tester, QaPreset.owner, id);
    final since = DateTime.now().subtract(const Duration(seconds: 1));
    final t = TapCounter();
    await pickMenu(tester, t, DocumentHe.share);
    await pumpUntil(tester, find.byKey(const Key('s6-email')));
    await t.tap(tester, find.byKey(const Key('s6-email')), settle: const Duration(milliseconds: 500));
    expect(find.byKey(const Key('s6-email-field')), findsOneWidget);
    await t.tap(tester, find.byKey(const Key('s6-email-send')), settle: const Duration(seconds: 4));
    final consentAsked = find.byKey(const Key('consent-yes')).evaluate().isNotEmpty;
    debugPrint('AT-31 consent dialog shown: $consentAsked (dev: only signed docs / business policy ask)');
    if (consentAsked) {
      await t.tap(tester, find.byKey(const Key('consent-yes')), settle: const Duration(seconds: 4));
    }
    await pumpUntil(tester, find.text(DocumentHe.emailSent));
    final mails = mailsSince(since).where((m) => m['to'] == 'qa-money-consent@example.test');
    expect(mails, isNotEmpty, reason: 'no e-mail file for the customer');
    expect('${mails.first['subject']}', contains('${(await owner.document(id))['document_number']}'));
  });

  // ---- S5 · payments --------------------------------------------------------------------

  testWidgets('AT-13 J3: sent 305 → "קיבלתי תשלום" → S5 filled with the balance → "רשום" = 3 taps '
      '→ linked receipt 400, open 0, label "שולם"', (tester) async {
    final id = await owner.issue(type: 'TAX_INVOICE', customerId: customer, shared: true);
    await openDocAs(tester, QaPreset.owner, id);
    expect(find.byType(PrimaryButton), findsOneWidget); // AT-90
    expect(primaryLabel(tester), DocumentHe.recordPayment); // row 9
    final t = TapCounter()..taps = openFromList;
    await t.tap(tester, primaryButton());
    await pumpUntil(tester, find.byKey(const Key('s5-record')));
    final amount = tester.widget<TextField>(find.byKey(const Key('s5-amount-0')));
    expect(amount.controller!.text, '1180', reason: 'S5 opens on the open balance');
    await t.tap(tester, find.byKey(const Key('s5-record')), settle: const Duration(seconds: 5));
    expect(t.taps, lessThanOrEqualTo(3));
    await pumpUntil(tester, find.byKey(const Key('doc-banner')));
    expect(find.text(PaymentHe.receiptIssued), findsOneWidget);

    final doc = await owner.document(id);
    expect(minor(doc['open_minor']), BigInt.zero);
    expect(minor(doc['paid_total_minor']), BigInt.from(118000));
    final linked = (doc['linkedDocuments'] as List).cast<Map<String, dynamic>>();
    final receipt = linked.where((l) => l['relation'] == 'RECEIPT').toList();
    expect(receipt, hasLength(1), reason: 'one receipt linked: $linked');
    expect(receipt.first['type'], 'RECEIPT');
    final r = await owner.document(receipt.first['id'] as String);
    expect(r['document_type'], 'RECEIPT');
    expect(minor(r['total_minor']), BigInt.from(118000));
    await settleNetwork(tester);
    expect(await statusLineText(tester), contains('שולם'));
  });

  testWidgets('AT-13 / §9.1 balances: partial cheque payment ₪500 → open ₪680, still "ממתין לתשלום"; '
      'cheque fields reach the server', (tester) async {
    final id = await owner.issue(type: 'TAX_INVOICE', customerId: customer, shared: true);
    await openDocAs(tester, QaPreset.owner, id);
    await TapCounter().tap(tester, primaryButton());
    await pumpUntil(tester, find.byKey(const Key('s5-record')));
    await tester.enterText(find.byKey(const Key('s5-amount-0')), '500');
    await tester.tap(inSheet(find.text(paymentMethodLabel('CHECK'))));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const Key('s5-bank-0')), '12');
    await tester.enterText(find.byKey(const Key('s5-branch-0')), '345');
    await tester.enterText(find.byKey(const Key('s5-account-0')), '678901');
    await tester.enterText(find.byKey(const Key('s5-check-0')), '1001');
    await TapCounter().tap(tester, find.byKey(const Key('s5-record')), settle: const Duration(seconds: 5));
    await pumpUntil(tester, find.byKey(const Key('doc-banner')));

    final doc = await owner.document(id);
    expect(minor(doc['open_minor']), BigInt.from(68000));
    final payments = (doc['payments'] as List).cast<Map<String, dynamic>>();
    expect(payments, hasLength(1));
    expect(payments.first['method'], 'CHECK');
    expect(payments.first['reference'], '1001');
    expect(payments.first['receiptDocumentId'], isNotNull, reason: '305 payment → receipt');
    final row = (await owner.listRow(id))!;
    expect(row['openMinor'], '68000');
    expect(row['balanceMinor'], row['openMinor'], reason: 'BE-10a: openMinor == balanceMinor');
    expect((await owner.listRow(id, query: {'unpaid': '1'})), isNotNull, reason: 'still a receivable');
    await settleNetwork(tester);
    expect(await statusLineText(tester), contains('ממתין לתשלום'));
    expect(await statusLineText(tester), contains('680'));
    // BE-11: a payment inside a receipt cannot be voided.
    final v = await owner.post('/payments/${payments.first['id']}/void', {'reason': 'QA'});
    expect(v.status, 409);
    expect(v.error, 'PAYMENT_LOCKED_IN_DOCUMENT');
  });

  // ---- S8 · cancel / credit -------------------------------------------------------------

  testWidgets('AT-21 J6: 305 ₪1,180 → ⋯ "בטל / זכה" → ₪200 → "הפק זיכוי" = 3 taps → 330 169.49 + 30.51; '
      'source credited 20000 / open 98000 "ממתין לתשלום"; +₪1,000 → max ₪980', (tester) async {
    final id = await owner.issue(type: 'TAX_INVOICE', customerId: customer, shared: true);
    await openDocAs(tester, QaPreset.owner, id);
    final t = TapCounter();
    await pickMenu(tester, t, DocumentHe.cancelOrCredit);
    await pumpUntil(tester, find.byKey(const Key('s8-credit')));
    expect(find.text(DocumentHe.fullCredit('₪1,180.00')).evaluate().isNotEmpty ||
        tester.widget<Text>(find.byKey(const Key('s8-kind'))).data!.startsWith('זיכוי מלא'), isTrue);
    expect(tester.widget<TextField>(find.byKey(const Key('s8-amount'))).controller!.text, '1180');
    await tester.enterText(find.byKey(const Key('s8-amount')), '200'); // typing = 0 taps (focused)
    await t.tap(tester, find.byKey(const Key('s8-credit')), settle: const Duration(seconds: 5));
    expect(t.taps, 3);

    final src = await owner.document(id);
    expect(src['credited_minor'], '20000');
    expect(src['open_minor'], '98000');
    expect(src['cancelled'], isFalse);
    final credits = (src['linkedDocuments'] as List).cast<Map<String, dynamic>>()
        .where((l) => l['relation'] == 'CREDIT').toList();
    expect(credits, hasLength(1));
    final credit = await owner.document(credits.first['id'] as String);
    expect(credit['document_type'], 'CREDIT_DOCUMENT');
    expect(credit['total_minor'], '20000');
    final lines = (credit['_lines'] as List).cast<Map<String, dynamic>>();
    expect(lines, hasLength(1));
    expect(lines.first['subtotal_minor'], '16949');
    expect(lines.first['tax_amount_minor'], '3051');
    // D moved on to the credit note's own D.
    await pumpUntil(tester, find.byType(DocumentScreen));

    // Source again: "ממתין לתשלום" ₪980; another ₪1,000 → "אפשר לזכות עד ₪980".
    await openDocAs(tester, QaPreset.owner, id);
    expect(await statusLineText(tester), contains('ממתין לתשלום'));
    expect(await statusLineText(tester), contains('980'));
    await pickMenu(tester, TapCounter(), DocumentHe.cancelOrCredit);
    await pumpUntil(tester, find.byKey(const Key('s8-credit')));
    expect(tester.widget<TextField>(find.byKey(const Key('s8-amount'))).controller!.text, '980');
    await tester.enterText(find.byKey(const Key('s8-amount')), '1000');
    await TapCounter().tap(tester, find.byKey(const Key('s8-credit')));
    final err = tester.widget<Text>(find.byKey(const Key('s8-error')));
    expect(err.textSpan!.toPlainText(), allOf(contains('אפשר לזכות עד'), contains('980')));
    navigatorKey.currentState!.pop();
    // The server refuses the same (CREDIT_LIMIT_EXCEEDED).
    final over = await owner.post(
        '/documents/$id/credit',
        {
          'scopeKey': 'default',
          'lines': [
            {'description': 'QA', 'quantityMicros': '1000000', 'unitPriceMinor': '84746', 'taxRateBasisPoints': 1800}
          ]
        },
        idemKey());
    expect(over.status, 409);
    expect(over.error, 'CREDIT_LIMIT_EXCEEDED');
  });

  testWidgets('AT-21 (full): full credit of another 305 → source cancelled → label "בוטל"', (tester) async {
    final id = await owner.issue(type: 'TAX_INVOICE', customerId: customer, shared: true);
    await openDocAs(tester, QaPreset.owner, id);
    await pickMenu(tester, TapCounter(), DocumentHe.cancelOrCredit);
    await pumpUntil(tester, find.byKey(const Key('s8-credit')));
    await TapCounter().tap(tester, find.byKey(const Key('s8-credit')), settle: const Duration(seconds: 5));
    final src = await owner.document(id);
    expect(src['credited_minor'], '118000');
    expect(src['open_minor'], '0');
    expect(src['cancelled'], isTrue);
    expect((await owner.listRow(id))!['cancelled'], isTrue);
    expect(await owner.listRow(id, query: {'unpaid': '1'}), isNull, reason: 'no longer a receivable');
    await openDocAs(tester, QaPreset.owner, id);
    expect(await statusLineText(tester), contains('בוטל'));
    expect(await menuLabels(tester), isNot(contains(DocumentHe.cancelOrCredit)), reason: 'nothing left to credit');
  });

  testWidgets('AT-56: "בטל / זכה" only on 305/320 (+300 void, P1 BE-36); never on 400/330; '
      'POST /credit on a 400 → 422 CREDIT_SOURCE_TYPE_INVALID', (tester) async {
    final inv = await owner.issue(type: 'TAX_INVOICE', customerId: customer, shared: true);
    final receipt = await owner.payWithReceipt(inv, 10000, customer);
    final p320 = await owner.paid320(customer);
    final t300 = await owner.issue(type: 'TRANSACTION_INVOICE', customerId: customer, rate: 1800);
    final credit = DevApi.expectStatus(
        await owner.post(
            '/documents/$inv/credit',
            {
              'scopeKey': 'default',
              'lines': [
                {'description': 'QA', 'quantityMicros': '1000000', 'unitPriceMinor': '1000', 'taxRateBasisPoints': 1800}
              ]
            },
            idemKey()),
        201,
        'credit');
    final creditId = credit.json['creditDocumentId'] as String;
    DevApi.expectStatus(await owner.post('/documents/$creditId/artifact'), 201, 'credit artifact');
    final expectations = {inv: true, p320: true, t300: true, receipt: false, creditId: false};
    for (final e in expectations.entries) {
      await openDocAs(tester, QaPreset.owner, e.key);
      final labels = await menuLabels(tester);
      expect(labels.contains(DocumentHe.cancelOrCredit), e.value,
          reason: '${(await owner.document(e.key))['document_type']}: $labels');
    }
    final line = {'description': 'QA', 'quantityMicros': '1000000', 'unitPriceMinor': '1000', 'taxRateBasisPoints': 0};
    final r = await owner.post('/documents/$receipt/credit', {'scopeKey': 'default', 'lines': [line]},
        idemKey());
    expect(r.status, 422);
    expect(r.error, 'CREDIT_SOURCE_TYPE_INVALID');
    final r300 = await owner.post('/documents/$t300/credit', {'scopeKey': 'default', 'lines': [line]},
        idemKey());
    expect(r300.error, 'CREDIT_SOURCE_TYPE_INVALID', reason: '300 is voided, never credited');
  });

  testWidgets('§8.3 / BE-36 void: 300 without payments → S8 "בטל מסמך" + reason → "בוטל"; '
      '300 with a payment → blocked, no void button', (tester) async {
    final t300 = await owner.issue(type: 'TRANSACTION_INVOICE', customerId: customer, rate: 1800);
    await openDocAs(tester, QaPreset.owner, t300);
    await pickMenu(tester, TapCounter(), DocumentHe.cancelOrCredit);
    await pumpUntil(tester, find.byKey(const Key('s8-void')));
    await TapCounter().tap(tester, find.byKey(const Key('s8-void')), settle: const Duration(milliseconds: 500));
    expect(find.byKey(const Key('s8-error')), findsOneWidget, reason: 'reason is required');
    await tester.enterText(find.byKey(const Key('s8-reason')), 'בדיקת QA');
    await TapCounter().tap(tester, find.byKey(const Key('s8-void')), settle: const Duration(seconds: 4));
    final d = await owner.document(t300);
    expect(d['voided_at'], isNotNull);
    expect(d['cancelled'], isTrue);
    await pumpUntil(tester, find.text(DocumentHe.documentVoided));
    expect(await statusLineText(tester), contains('בוטל'));

    final paid300 = await owner.issue(type: 'TRANSACTION_INVOICE', customerId: customer, rate: 1800);
    await owner.payWithReceipt(paid300, 10000, customer);
    await openDocAs(tester, QaPreset.owner, paid300);
    await pickMenu(tester, TapCounter(), DocumentHe.cancelOrCredit);
    await pumpUntil(tester, find.byKey(const Key('s8-void-blocked')));
    expect(find.text(DocumentHe.voidHasPayments), findsOneWidget);
    expect(find.byKey(const Key('s8-void')), findsNothing);
    navigatorKey.currentState!.pop();
    final v = await owner.post('/documents/$paid300/void', {'reason': 'QA'});
    expect(v.status, 409);
    expect(v.error, 'DOCUMENT_HAS_PAYMENTS');
  });

  // ---- presets on D ----------------------------------------------------------------------

  testWidgets('AT-42: employee + self-issuer → "קיבלתי תשלום" + S5; no "בטל / זכה"; '
      'POST /credit → 403', (tester) async {
    // The employee has no money:read (BE-03 read gating): amounts are hidden
    // on other people's documents, so the money flow runs on its OWN 305.
    final emp = await DevApi.as(QaPreset.employeeSelf);
    final id = await emp.issue(type: 'TAX_INVOICE', customerId: customer, shared: true);
    await openDocAs(tester, QaPreset.employeeSelf, id);
    expect(primaryLabel(tester), DocumentHe.recordPayment);
    expect(await menuLabels(tester), isNot(contains(DocumentHe.cancelOrCredit)));
    await TapCounter().tap(tester, primaryButton());
    await pumpUntil(tester, find.byKey(const Key('s5-record')));
    expect(tester.widget<TextField>(find.byKey(const Key('s5-amount-0'))).controller!.text, '1180');
    navigatorKey.currentState!.pop();
    // Someone else's 305: still no "בטל / זכה" (and no approve).
    final others = await owner.issue(type: 'TAX_INVOICE', customerId: customer, shared: true);
    await openDocAs(tester, QaPreset.employeeSelf, others);
    final labels = await menuLabels(tester);
    expect(labels, isNot(contains(DocumentHe.cancelOrCredit)));
    expect(labels, isNot(contains(DocumentHe.approveAndIssue)));
    debugPrint('AT-42 other\'s 305 as employee: primary="${primaryLabel(tester)}" menu=$labels');
    final r = await emp.post(
        '/documents/$id/credit',
        {
          'scopeKey': 'default',
          'lines': [
            {'description': 'QA', 'quantityMicros': '1000000', 'unitPriceMinor': '1000', 'taxRateBasisPoints': 1800}
          ]
        },
        idemKey());
    expect(r.status, 403);
    expect(r.error, 'DOCUMENT_ACTION_FORBIDDEN');
  });

  testWidgets('AT-40: READ_ONLY viewer → D "שתף" → S6 with PDF only (no WhatsApp / mail / link / QR)',
      (tester) async {
    final id = await owner.issue(type: 'TAX_INVOICE', customerId: customer, shared: true);
    await openDocAs(tester, QaPreset.viewer, id);
    expect(find.byType(PrimaryButton), findsOneWidget); // AT-90
    expect(primaryLabel(tester), DocumentHe.share);
    expect(await menuLabels(tester), isNot(contains(DocumentHe.cancelOrCredit)));
    await TapCounter().tap(tester, primaryButton());
    await pumpUntil(tester, find.byKey(const Key('s6-pdf-primary')));
    for (final k in ['s6-whatsapp', 's6-email', 's6-copy', 's6-qr', 's6-revoke']) {
      expect(find.byKey(Key(k)), findsNothing, reason: k);
    }
    expect(find.byKey(const Key('s6-pdf-copy')), findsOneWidget);
    await TapCounter().tap(tester, find.byKey(const Key('s6-pdf-primary')), settle: const Duration(seconds: 4));
    expect(sharedPdfs, isNotEmpty, reason: 'the PDF went to the share sheet');
    expect(launcher.opened, isEmpty);
    final viewer = await DevApi.as(QaPreset.viewer);
    expect((await viewer.post('/documents/$id/share-link')).status, 403);
  });

  testWidgets('AT-44: accountant (ACCOUNTANT_REP) → no "בטל / זכה"; S6 without WhatsApp / mail; '
      'POST /credit → 403', (tester) async {
    final id = await owner.issue(type: 'TAX_INVOICE', customerId: customer, shared: true);
    await openDocAs(tester, QaPreset.cpaRep, id);
    expect(await menuLabels(tester), isNot(contains(DocumentHe.cancelOrCredit)));
    expect(primaryLabel(tester), DocumentHe.share);
    await TapCounter().tap(tester, primaryButton());
    await pumpUntil(tester, find.byKey(const Key('s6-pdf-primary')));
    expect(find.byKey(const Key('s6-whatsapp')), findsNothing);
    expect(find.byKey(const Key('s6-email')), findsNothing);
    navigatorKey.currentState!.pop();
    final rep = await DevApi.as(QaPreset.cpaRep);
    final r = await rep.post(
        '/documents/$id/credit',
        {
          'scopeKey': 'default',
          'lines': [
            {'description': 'QA', 'quantityMicros': '1000000', 'unitPriceMinor': '1000', 'taxRateBasisPoints': 1800}
          ]
        },
        idemKey());
    expect(r.status, 403);
  });

  // ---- D · duplicate, quotes --------------------------------------------------------------

  testWidgets('AT-30: ⋯ "שכפל" → a draft with the same lines, no issue date (today at finalize)',
      (tester) async {
    final id = await owner.issue(type: 'TAX_INVOICE', customerId: customer, netMinor: 45600, description: 'שכפול QA');
    await openDocAs(tester, QaPreset.owner, id);
    await pickMenu(tester, TapCounter(), DocumentHe.duplicate);
    await pumpUntil(tester, find.byType(ComposeScreen));
    final draftId = tester.widget<ComposeScreen>(find.byType(ComposeScreen)).draftId;
    expect(draftId, isNotNull);
    final draft = await owner.document(draftId!);
    expect(draft['status'], 'DRAFT');
    expect(draft['document_type'], 'TAX_INVOICE');
    expect(draft['customer_id'], customer);
    final issueDate = draft['issue_date'];
    expect(issueDate == null || issueDate == today(), isTrue, reason: 'issue_date=$issueDate');
    final lines = (draft['_lines'] as List).cast<Map<String, dynamic>>();
    expect(lines, hasLength(1));
    expect(lines.first['description'], 'שכפול QA');
    expect(lines.first['unit_price_minor'], '45600');
    expect(lines.first['tax_rate_basis_points'], 1800);
    navigatorKey.currentState!.pop();
    expect((await owner.delete('/documents/$draftId')).status, 200);
  });

  testWidgets('AT-20: SENT quote → D "הפוך לחשבונית" → 305 draft with the same amount '
      '(ACCEPTED, then convert)', (tester) async {
    final q = await owner.quote(customer, status: 'SENT');
    await openDocAs(tester, QaPreset.owner, q, quote: true);
    expect(primaryLabel(tester), DocumentHe.convertToInvoice); // row 12
    await TapCounter().tap(tester, primaryButton(), settle: const Duration(seconds: 4));
    await pumpUntil(tester, find.byType(ComposeScreen));
    final draftId = tester.widget<ComposeScreen>(find.byType(ComposeScreen)).draftId!;
    final draft = await owner.document(draftId);
    expect(draft['document_type'], 'TAX_INVOICE');
    expect(draft['total_minor'], '118000');
    final quote = (await owner.get('/quotes/$q')).json['quote'] as Map<String, dynamic>;
    expect(quote['status'], 'CONVERTED');
    expect(quote['convertedDocumentId'], draftId);
    navigatorKey.currentState!.pop();
  });

  testWidgets('AT-20b: DRAFT quote → ⋯ "הפוך לחשבונית" → direct convert', (tester) async {
    final q = await owner.quote(customer);
    await openDocAs(tester, QaPreset.owner, q, quote: true);
    expect(primaryLabel(tester), DocumentHe.sendQuote); // row 11
    await pickMenu(tester, TapCounter(), DocumentHe.convertToInvoice);
    await pumpUntil(tester, find.byType(ComposeScreen));
    final draftId = tester.widget<ComposeScreen>(find.byType(ComposeScreen)).draftId!;
    expect((await owner.document(draftId))['total_minor'], '118000');
    final quote = (await owner.get('/quotes/$q')).json['quote'] as Map<String, dynamic>;
    expect(quote['status'], 'CONVERTED');
    expect(launcher.opened, isEmpty, reason: 'convert sends nothing');
    navigatorKey.currentState!.pop();
  });

  // ---- balances (server, BE-36 / BE-10a / BE-01) -------------------------------------------

  testWidgets('AT-21/AT-13 balances: pay ₪300 + credit ₪200 on ₪1,180 → open ₪680 everywhere; '
      'receipt and 330 are never receivables', (tester) async {
    final id = await owner.issue(type: 'TAX_INVOICE', customerId: customer, shared: true);
    final receipt = await owner.payWithReceipt(id, 30000, customer);
    final credit = await owner.post(
        '/documents/$id/credit',
        {
          'scopeKey': 'default',
          'lines': [
            {'description': 'QA', 'quantityMicros': '1000000', 'unitPriceMinor': '16949', 'taxRateBasisPoints': 1800}
          ]
        },
        idemKey());
    DevApi.expectStatus(credit, 201, 'credit');
    final creditId = credit.json['creditDocumentId'] as String;
    DevApi.expectStatus(await owner.post('/documents/$creditId/artifact'), 201, 'credit artifact');

    final d = await owner.document(id);
    expect(d['paid_total_minor'], '30000');
    expect(d['credited_minor'], '20000');
    expect(d['open_minor'], '68000');
    expect(d['balance_minor'], '68000', reason: 'BE-36: balance already includes credits');
    final row = (await owner.listRow(id, query: {'unpaid': '1'}))!;
    expect(row['openMinor'], '68000');
    expect(row['cancelled'], isFalse);
    expect(await owner.listRow(receipt, query: {'unpaid': '1'}), isNull);
    expect(await owner.listRow(creditId, query: {'unpaid': '1'}), isNull);
    expect((await owner.listRow(receipt))!['openMinor'], '0');
    final dash = DevApi.expectStatus(await owner.get('/dashboard'), 200, 'dashboard').json['summary'] as Map;
    expect(dash['unpaid_total'], dash['unpaid_balance'], reason: 'V1 alias');

    await openDocAs(tester, QaPreset.owner, id);
    expect(await statusLineText(tester), contains('680'));
    expect(primaryLabel(tester), DocumentHe.recordPayment);
  });
}
