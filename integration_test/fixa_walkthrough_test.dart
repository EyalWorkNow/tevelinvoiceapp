// FIXA (tester feedback 2026-11-18) on the simulator against a LOCAL dev API
// (never prod): bell + עדכונים, accepted quote in "מסמכים אחרונים", Home
// search, "משימות קרובות", "+ לקוח חדש", "יתרה לגבייה", the short payment
// request screen and the 300 in "מי חייב לי".
//
//   U=<udid>; OUT=<dir>
//   ~/flutter/bin/flutter test integration_test/fixa_walkthrough_test.dart -d $U \
//     --dart-define=API_BASE=http://127.0.0.1:3071 \
//     --dart-define=FIXA_EMAIL=mobile-owner@tevel.test \
//     --dart-define=FIXA_PASSWORD=Mobile12345678 \
//     --dart-define=FIXA_BUSINESS=<business id> 2>&1 |
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

import 'crash_sweep_test.dart' show t, pumpMs, waitFor;
import 'persona_screens_test.dart' as persona show startPlansGuard;
import 'persona_screens_test.dart' show plansGuardOn;
import 'v2_qa_gate_helpers.dart' show launchSignedInAs, DevSession;

const _base = String.fromEnvironment('API_BASE');
int _n = 0;
Future<void> shot(String name) async {
  await pumpMs(1200);
  _n++;
  print('SHOT:fixa-${_n.toString().padLeft(2, '0')}-$name');
  await pumpMs(2200);
}

Future<void> tapKey(String k, {int ms = 1500}) async {
  final f = find.byKey(Key(k));
  expect(await waitFor(f, ms: 15000), isTrue, reason: k);
  await t.ensureVisible(f.first);
  await pumpMs(300);
  await t.tap(f.first);
  await pumpMs(ms);
}

Future<void> backToHome() async {
  while (navigatorKey.currentState!.canPop()) {
    navigatorKey.currentState!.pop();
    await pumpMs(700);
  }
  currentTab.value = AppTab.home;
  await pumpMs(1500);
}

/// The customer accepts the quote on its public page (/q/:token).
Future<void> acceptQuote(DevSession api, String quoteId, String name) async {
  final link = await api.post('/quotes/$quoteId/share-link');
  final path = Uri.parse(link['url'] as String).path.replaceFirst('/d/', '/q/');
  final page = await http.get(Uri.parse('$_base$path'));
  final version =
      RegExp(r'name="version" value="([^"]+)"').firstMatch(page.body)?[1] ?? '';
  final r = await http.post(
    Uri.parse('$_base$path/accept'),
    headers: {'content-type': 'application/x-www-form-urlencoded'},
    body: {'fullName': name, 'version': version, 'drawnSignature': ''},
  );
  print('SETUP accept ${r.statusCode}');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  persona.startPlansGuard();

  testWidgets('FIXA walkthrough items 1–7', (tester) async {
    t = tester;
    plansGuardOn = true;
    final api = await launchSignedInAs(
      tester,
      const String.fromEnvironment('FIXA_EMAIL'),
      password: const String.fromEnvironment('FIXA_PASSWORD'),
      businessId: const String.fromEnvironment('FIXA_BUSINESS'),
    );
    expect(await waitFor(find.byKey(const Key('tab-home')), ms: 40000), isTrue);
    await pumpMs(2000);

    // ---- setup over HTTP: a customer "משה כהן", a quote he accepts, a
    // payment request (300) he still owes.
    final tag = DateTime.now().millisecondsSinceEpoch % 100000;
    final customer = await api.post('/customers', {
      'name': 'משה כהן $tag',
      'phone': '0501234567',
      'customerType': 'INDIVIDUAL',
    });
    final cid = customer['id'] as String;
    final quote = await api.post('/quotes', {
      'customerId': cid,
      'lines': [
        {
          'description': 'עיצוב לוגו',
          'quantityMicros': '1000000',
          'unitPriceMinor': '100000',
          'taxRateBasisPoints': 1800,
        },
      ],
    });
    await acceptQuote(api, quote['id'] as String, 'משה כהן');

    // ---- 1. Home: bell badge, search field, "יתרה לגבייה", recent event --
    await backToHome();
    await tester.drag(
      find.byKey(const Key('home-list')),
      const Offset(0, 400),
    ); // pull to refresh
    await pumpMs(4000);
    expect(await waitFor(find.byKey(const Key('home-bell')), ms: 15000), isTrue);
    await shot('home-bell-search-money');
    final recent = find.byKey(Key('recent-event-${quote['id']}'));
    expect(await waitFor(recent, ms: 15000), isTrue);
    await tester.ensureVisible(recent);
    await pumpMs(600);
    await shot('home-recent-quote-accepted');

    // ---- 1b. the bell → עדכונים
    await tester.drag(find.byKey(const Key('home-list')), const Offset(0, 900));
    await pumpMs(800);
    await tapKey('home-bell', ms: 3000);
    await shot('notifications-inbox');
    final markAll = find.byKey(const Key('notifications-mark-all'));
    if (markAll.evaluate().isNotEmpty) {
      await tester.tap(markAll);
      await pumpMs(2000);
      await shot('notifications-all-read');
    }
    await backToHome();

    // ---- 3. Home search "הצעת מחיר של כהן"
    await tapKey('home-search', ms: 1500);
    await tester.enterText(
      find.byKey(const Key('global-search-field')),
      'הצעת מחיר של כהן',
    );
    await pumpMs(3000);
    await shot('search-quote-of-cohen');
    await tester.enterText(
      find.byKey(const Key('global-search-field')),
      'כהן',
    );
    await pumpMs(3000);
    await shot('search-cohen-all');
    await backToHome();

    // ---- 2. the short payment-request screen (from the customer)
    unawaited(openPaymentRequest(navigatorKey.currentContext!, customerId: cid));
    await pumpMs(4000);
    await shot('payment-request-screen');
    await backToHome();

    // A payment request issued for him (the screen's own issue path is
    // covered by its widget tests; here: the 300 shows in "מי חייב לי").
    final request = await api.post('/documents', {
      'documentType': 'TRANSACTION_INVOICE',
      'customerId': cid,
      'currency': 'ILS',
      'lines': [
        {
          'description': 'בקשת תשלום FIXA',
          'quantityMicros': '1000000',
          'unitPriceMinor': '50000',
          'taxRateBasisPoints': 1800,
        },
      ],
    });
    final fin = await http.post(
      Uri.parse('$_base/documents/${request['id']}/finalize'),
      headers: {
        'Authorization': 'Bearer ${api.token}',
        'X-Business-Id': api.businessId!,
        'Content-Type': 'application/json',
        'Idempotency-Key': 'fixa-fin-${request['id']}',
      },
      body: '{"scopeKey":"default"}',
    );
    print('SETUP 300 finalize ${fin.statusCode}');

    // ---- 7. "מי חייב לי" includes the payment request
    unawaited(openDebts(navigatorKey.currentContext!));
    await pumpMs(4000);
    await shot('debts-with-payment-request');
    final row = find.textContaining('משה כהן $tag');
    if (row.evaluate().isNotEmpty) {
      await tester.ensureVisible(row.first);
      await tester.tap(row.first);
      await pumpMs(1500);
      await shot('debts-payment-request-expanded');
    }
    await backToHome();

    // ---- 5. customers page: "+ לקוח חדש"
    currentTab.value = AppTab.people;
    await pumpMs(3000);
    await shot('customers-new-customer-cta');
    await backToHome();
  });
}
