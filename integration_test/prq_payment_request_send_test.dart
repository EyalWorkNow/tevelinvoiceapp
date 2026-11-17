// PRQ (owner 2026-11-17): "בקשת תשלום" end to end + "שלח" from the documents
// list, on the simulator against a LOCAL dev API (never prod).
//
//   U=<udid>; OUT=<dir>
//   ~/flutter/bin/flutter test integration_test/prq_payment_request_send_test.dart -d $U \
//     --dart-define=API_BASE=http://127.0.0.1:3061 \
//     --dart-define=PRQ_EMAIL=123@123.com --dart-define=PRQ_PASSWORD=123123 \
//     --dart-define=PRQ_BUSINESS=<business id> 2>&1 |
//   while IFS= read -r l; do echo "$l"; if [[ $l == *SHOT:* ]]; then
//     n=${l##*SHOT:}; xcrun simctl io $U screenshot "$OUT/$n.png" >/dev/null 2>&1; fi; done
// ignore_for_file: avoid_print
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:invoice/app_shell.dart' show AppTab, currentTab;
import 'package:invoice/router.dart';
import 'package:invoice/screens/compose/compose_screen.dart';
import 'package:invoice/screens/document/sheets/s6_share.dart'
    show ShareSheet, pdfSharer, textSharer;
import 'package:invoice/screens/document/sheets/send_sheet.dart'
    show QuoteSendSheet;
import 'package:invoice/ui/widgets/keypad.dart';
import 'package:invoice/ui/widgets/more_menu.dart';
import 'package:invoice/util/allowed_urls.dart' show urlOpener;

import 'crash_sweep_test.dart' show t, pumpMs, waitFor;
import 'persona_screens_test.dart' as persona show startPlansGuard;
import 'persona_screens_test.dart' show plansGuardOn;
import 'v2_qa_gate_helpers.dart' show launchSignedInAs, DevSession;

const _base = String.fromEnvironment('API_BASE');
int _n = 0;
Future<void> shot(String name) async {
  await pumpMs(1200);
  _n++;
  print('SHOT:prq-${_n.toString().padLeft(2, '0')}-$name');
  await pumpMs(2200); // the host takes the screenshot meanwhile
}

Future<void> tapKey(String k, {int ms = 1200}) async {
  final f = find.byKey(Key(k));
  expect(await waitFor(f, ms: 15000), isTrue, reason: k);
  await t.ensureVisible(f.first);
  await pumpMs(300);
  await t.tap(f.first);
  await pumpMs(ms);
}

Future<void> typeAmount(String digits) async {
  expect(await waitFor(find.byType(Keypad), ms: 15000), isTrue);
  for (final d in digits.split('')) {
    await t.tap(
      find.descendant(of: find.byType(Keypad), matching: find.text(d)).first,
    );
    await pumpMs(150);
  }
}

Future<String> issueOverHttp(
  DevSession api,
  String type,
  String customerId,
  int unitMinor,
) async {
  final d = await api.post('/documents', {
    'documentType': type,
    'customerId': customerId,
    'currency': 'ILS',
    'lines': [
      {
        'description': 'שירות PRQ',
        'quantityMicros': '1000000',
        'unitPriceMinor': '$unitMinor',
        'taxRateBasisPoints': type == 'RECEIPT' ? 0 : 1800,
      },
    ],
  });
  final fin = await http.post(
    Uri.parse('$_base/documents/${d['id']}/finalize'),
    headers: {
      'Authorization': 'Bearer ${api.token}',
      'X-Business-Id': api.businessId!,
      'Content-Type': 'application/json',
      'Idempotency-Key': 'prq-fin-${d['id']}',
    },
    body: '{"scopeKey":"default"}',
  );
  print('SETUP $type finalize ${fin.statusCode} ${fin.body}');
  return d['id'] as String;
}

Future<Map<String, dynamic>> docOf(DevSession api, String id) async {
  final detail = await api.get('/documents/$id');
  return (detail['document'] ?? detail) as Map<String, dynamic>;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  persona.startPlansGuard();

  testWidgets('PRQ payment request + send from the list', (tester) async {
    t = tester;
    plansGuardOn = true;
    final api = await launchSignedInAs(
      tester,
      const String.fromEnvironment('PRQ_EMAIL'),
      password: const String.fromEnvironment('PRQ_PASSWORD'),
      businessId: const String.fromEnvironment('PRQ_BUSINESS'),
    );
    final home = await waitFor(find.byKey(const Key('tab-home')), ms: 40000);
    if (!home) await shot('start-not-home');
    expect(home, isTrue);
    await pumpMs(2000);
    final opened = <Uri>[];
    urlOpener = (uri, {inApp = false}) async {
      opened.add(uri);
      print('OPEN $uri');
      return true;
    };
    final shared = <String>[];
    textSharer = (text) async {
      shared.add(text);
      print('SHARE-TEXT $text');
    };
    pdfSharer = (bytes, name, {text}) async {
      shared.add('PDF $name ${bytes.length}');
      print('SHARE-PDF $name ${bytes.length} bytes');
    };
    final tag = DateTime.now().millisecondsSinceEpoch % 100000;
    final customer = await api.post('/customers', {
      'name': 'רונית לוי $tag',
      'phone': '0501234567',
      'email': 'ronit-$tag@example.test',
      'customerType': 'INDIVIDUAL',
    });
    final cid = customer['id'] as String;
    await api.post('/customers/$cid/consent', {'method': 'APP_TOGGLE'});

    // ---- 1. the "בקשת תשלום" quick action (ניהול) -----------------------
    currentTab.value = AppTab.business;
    await pumpMs(2000);
    final quick = find.byKey(const Key('management-action-payment-request'));
    expect(await waitFor(quick, ms: 15000), isTrue);
    await shot('manage-quick-action-payment-request');

    // ---- 2. compose the request for the customer → issue + WhatsApp -----
    unawaited(
      openCompose(
        navigatorKey.currentContext!,
        intent: 'REQUEST',
        customerId: cid,
      ),
    );
    await pumpMs(3000);
    final resumeNew = find.byKey(const Key('resume-draft-new')).hitTestable();
    if (resumeNew.evaluate().isNotEmpty) {
      await tester.tap(resumeNew.first);
      await pumpMs(1500);
    }
    await typeAmount('590');
    await pumpMs(800);
    await shot('request-composed-590');
    final label = tester.widget<Text>(
      find.byKey(const Key('compose-kind-label')),
    );
    print('CHECK kind="${label.data}"');
    expect(label.data, 'יופק: חשבון עסקה / פרופורמה');
    await tapKey('compose-primary', ms: 9000);
    await shot('request-issued-document');
    final wa = opened.lastWhere((u) => u.host == 'wa.me');
    final waText = wa.queryParameters['text'] ?? '';
    print('CHECK whatsapp="$waText"');
    expect(waText, contains('לתשלום: '));
    final list = await api.get('/documents?customerId=$cid&limit=5');
    final request = (list['documents'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((d) => d['documentType'] == 'TRANSACTION_INVOICE');
    final requestId = request['id'] as String;
    print('CHECK request $requestId status=${request['status']}');
    while (find.byType(ComposeScreen).evaluate().isNotEmpty) {
      navigatorKey.currentState!.pop();
      await pumpMs(800);
    }
    await go('/');
    await pumpMs(1000);

    // ---- 3. D of the request → "קיבלתי תשלום" → linked 320 -------------
    unawaited(openDocument(navigatorKey.currentContext!, requestId));
    await pumpMs(4000);
    await shot('request-document-screen');
    var paid = find.text('קיבלתי תשלום').hitTestable();
    if (paid.evaluate().isEmpty) {
      await tester.tap(find.byType(MoreMenu).first);
      await pumpMs(1500);
      await shot('request-more-menu');
      paid = find.text('קיבלתי תשלום').hitTestable();
    }
    expect(paid, findsWidgets);
    await tester.tap(paid.first);
    await pumpMs(4000);
    await shot('paid-composer-320');
    print(
      'CHECK paid kind="${tester.widget<Text>(find.byKey(const Key('compose-kind-label'))).data}"',
    );
    // A first payment of this customer: the method is chosen once.
    if (find.byKey(const Key('compose-primary')).evaluate().isEmpty) {
      final hide = find.byKey(const Key('keypad-done'));
      if (hide.evaluate().isNotEmpty) {
        await tester.tap(hide.first);
        await pumpMs(1000);
      }
      final cash = find.text('מזומן');
      expect(await waitFor(cash, ms: 8000), isTrue);
      await tester.ensureVisible(cash.first);
      await pumpMs(400);
      await tester.tap(cash.first);
      await pumpMs(1200);
      await shot('paid-composer-320-cash');
    }
    final primary = find.byKey(const Key('compose-primary'));
    expect(await waitFor(primary, ms: 8000), isTrue);
    await tester.ensureVisible(primary);
    await pumpMs(500);
    await tester.tap(primary);
    await pumpMs(10000);
    await shot('paid-320-issued');
    final source = await docOf(api, requestId);
    print(
      'CHECK 300 after payment: balance=${source['balance_minor']} linked=${source['linkedDocuments']}',
    );
    expect('${source['balance_minor']}', '0');
    while (find.byType(ComposeScreen).evaluate().isNotEmpty) {
      navigatorKey.currentState!.pop();
      await pumpMs(800);
    }
    await go('/');
    await pumpMs(1000);

    // ---- 4. send three other types from the documents list --------------
    final invoice = await issueOverHttp(api, 'TAX_INVOICE', cid, 20000);
    final receipt = await issueOverHttp(api, 'RECEIPT', cid, 15000);
    final order = await issueOverHttp(api, 'SALES_ORDER', cid, 30000);
    final quote = await api.post('/quotes', {
      'customerId': cid,
      'currency': 'ILS',
      'validUntil': DateTime.now()
          .add(const Duration(days: 14))
          .toIso8601String()
          .substring(0, 10),
      'lines': [
        {
          'description': 'הצעת PRQ',
          'quantityMicros': '1000000',
          'unitPriceMinor': '40000',
          'taxRateBasisPoints': 1800,
        },
      ],
    });
    unawaited(openActivity(navigatorKey.currentContext!));
    await pumpMs(4000);
    await shot('documents-list');

    Future<void> sendRow(String id, String name) async {
      final row = find.byKey(Key('doc-$id'));
      // Back to the top of the lazy list (the row may be scrolled away).
      final list = find.byKey(const Key('activity-list'));
      if (list.evaluate().isNotEmpty) {
        await tester.fling(list, const Offset(0, 3000), 3000);
        await pumpMs(1200);
      }
      expect(await waitFor(row, ms: 15000), isTrue, reason: name);
      await tester.ensureVisible(row);
      await pumpMs(500);
      await tester.longPress(row);
      await pumpMs(3500);
      expect(find.byType(ShareSheet), findsOneWidget);
      await shot('send-sheet-$name');
    }

    // 305 → WhatsApp (link + payment page).
    await sendRow(invoice, 'tax-invoice');
    final before = opened.length;
    await tapKey('s6-whatsapp', ms: 5000);
    expect(opened.length, greaterThan(before));
    print('CHECK 305 whatsapp=${opened.last}');
    await pumpMs(1500);

    // 400 → e-mail with the PDF (server send + process).
    await sendRow(receipt, 'receipt');
    await tapKey('s6-more', ms: 800);
    await tapKey('s6-email', ms: 800);
    await shot('receipt-email-form');
    await tapKey('s6-email-send', ms: 7000);
    await shot('receipt-emailed');
    final rdoc = await docOf(api, receipt);
    print('CHECK 400 status=${rdoc['status']}');

    // 100 → PDF through the share sheet.
    await sendRow(order, 'sales-order');
    await tapKey('s6-pdf', ms: 5000);
    print('CHECK 100 shared=${shared.last}');
    expect(shared.last, startsWith('PDF '));
    await pumpMs(1500);

    // A quote from the "הצעות" list → WhatsApp with its page.
    navigatorKey.currentState!.pop();
    await pumpMs(1000);
    unawaited(openActivity(navigatorKey.currentContext!, chip: 'quotes'));
    await pumpMs(4000);
    final qrow = find.byKey(Key('quote-${quote['id']}'));
    expect(await waitFor(qrow, ms: 15000), isTrue);
    await tester.longPress(qrow);
    await pumpMs(3500);
    expect(find.byType(QuoteSendSheet), findsOneWidget);
    await shot('send-sheet-quote');
    await tapKey('send-quote-whatsapp', ms: 5000);
    print('CHECK quote whatsapp=${opened.last}');
    await shot('after-quote-sent-list');
    print('PRQ WALKTHROUGH DONE');
  });
}
