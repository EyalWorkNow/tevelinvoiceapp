// FX1 (walkthrough 2026-11-17, compose / money bugs #1–#7) on the simulator,
// real app against the FX1 local staging API (never prod).
//
//   U=<FX1 udid>; OUT=$PWD/docs/qa-2026-11-17/fx1
//   ~/flutter/bin/flutter test integration_test/fx1_walkthrough_fixes_test.dart -d $U \
//     --dart-define=API_BASE=http://127.0.0.1:3071 \
//     --dart-define=MAILDIR=$HOME/invoiceproject-staging-fx1/mail 2>&1 |
//   while IFS= read -r l; do echo "$l"; if [[ $l == *SHOT:* ]]; then
//     n=${l##*SHOT:}; xcrun simctl io $U screenshot "$OUT/$n.png" >/dev/null 2>&1; fi; done
//
// Writes on staging: one customer, two documents set up over HTTP, the
// documents the steps issue, one accepted quote (converted) and one draft
// (deleted by the test itself — bug #4).
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/compose/compose_screen.dart';
import 'package:invoice/ui/widgets/keypad.dart';
import 'package:invoice/util/allowed_urls.dart' show urlOpener;

import 'crash_sweep_test.dart' show t, pumpMs, waitFor;
import 'persona_screens_test.dart' as persona show startPlansGuard;
import 'persona_screens_test.dart' show plansGuardOn;
import 'v2_qa_gate_helpers.dart' show launchSignedInAs, DevSession;

int _n = 0;
Future<void> shot(String name) async {
  await pumpMs(1200);
  _n++;
  print('SHOT:fx1-${_n.toString().padLeft(2, '0')}-$name');
  await pumpMs(2200); // the host takes the screenshot meanwhile
}

class _OfflineClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    throw const SocketException('Network is unreachable (FX1)');
  }
}

Future<void> key(String k) async {
  final f = find
      .descendant(of: find.byType(Keypad), matching: find.text(k))
      .first;
  await t.tap(f);
  await pumpMs(150);
}

Future<void> typeAmount(String digits) async {
  expect(await waitFor(find.byType(Keypad), ms: 15000), isTrue);
  for (final d in digits.split('')) {
    await key(d);
  }
}

Future<void> tapKey(String k, {int ms = 800}) async {
  final f = find.byKey(Key(k));
  expect(await waitFor(f, ms: 15000), isTrue, reason: k);
  await t.ensureVisible(f.first);
  await pumpMs(300);
  await t.tap(f.first);
  await pumpMs(ms);
}

/// Opens the Composer like the home buttons do and answers a leftover draft.
Future<void> compose(String intent, {String? customerId}) async {
  unawaited(
    openCompose(
      navigatorKey.currentContext!,
      intent: intent,
      customerId: customerId,
    ),
  );
  await pumpMs(2500);
}

Future<void> closeComposer() async {
  while (find.byType(ComposeScreen).evaluate().isNotEmpty) {
    navigatorKey.currentState!.pop();
    await pumpMs(800);
  }
}

String primaryText() {
  final b = find.byKey(const Key('compose-primary'));
  return find
      .descendant(of: b, matching: find.byType(Text))
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .join(' ');
}

Future<Map<String, dynamic>> lastDocOf(
  DevSession api,
  String customerId,
) async {
  final list = await api.get('/documents?customerId=$customerId&limit=5');
  final docs = (list['documents'] as List).cast<Map<String, dynamic>>();
  return docs.first;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  persona.startPlansGuard();

  testWidgets('FX1 walkthrough compose / money fixes', (tester) async {
    t = tester;
    plansGuardOn = true;
    final api = await launchSignedInAs(tester, 'mobile-owner@tevel.test');
    expect(await waitFor(find.byKey(const Key('tab-home')), ms: 40000), isTrue);
    await pumpMs(2000);
    final opened = <Uri>[];
    urlOpener = (uri, {inApp = false}) async {
      opened.add(uri);
      print('OPEN $uri');
      return true;
    };
    final tag = DateTime.now().millisecondsSinceEpoch % 100000;

    // ---- setup over HTTP: a customer whose last document is a credit-like
    // line on an invoice (what 1472–1474 printed) after a real one.
    final customer = await api.post('/customers', {'name': 'לקוחת FX1 $tag'});
    final cid = customer['id'] as String;
    for (final description in ['עיצוב חוברת FX1', 'זיכוי חלקי לחשבונית 1468']) {
      final d = await api.post('/documents', {
        'documentType': 'TAX_INVOICE',
        'customerId': cid,
        'currency': 'ILS',
        'lines': [
          {
            'description': description,
            'quantityMicros': '1000000',
            'unitPriceMinor': '10000',
            'taxRateBasisPoints': 1800,
          },
        ],
      });
      final fin = await http.post(
        Uri.parse(
          '${const String.fromEnvironment('API_BASE')}/documents/${d['id']}/finalize',
        ),
        headers: {
          'Authorization': 'Bearer ${api.token}',
          'X-Business-Id': api.businessId!,
          'Content-Type': 'application/json',
          'Idempotency-Key': 'fx1-fin-${d['id']}',
        },
        body: '{"scopeKey":"default"}',
      );
      print('SETUP finalize ${fin.statusCode}');
    }

    // ---- #2 + #5 + #7 + #1: the composer for that customer ---------------
    await compose('TYPE:305', customerId: cid);
    final resumeNew = find.byKey(const Key('resume-draft-new')).hitTestable();
    if (resumeNew.evaluate().isNotEmpty) {
      await tester.tap(resumeNew.first);
      await pumpMs(1500);
    }
    await typeAmount('2');
    await shot('305-typed-2-kind-pill');
    final pill = find.byKey(const Key('compose-kind-label'));
    final pillText = (tester.widget<Text>(pill)).data;
    print('CHECK #5 pill="$pillText" primary="${primaryText()}"');
    expect(pillText, 'יופק: חשבונית מס');
    expect(primaryText(), 'הפק חשבונית מס');
    // #2: not prefilled with the credit text; the real last one is offered.
    expect(find.text('זיכוי חלקי לחשבונית 1468'), findsNothing);
    // #7: the handle on the keypad uncovers what is under it.
    expect(find.byKey(const Key('keypad-done')), findsOneWidget);
    await tapKey('keypad-done', ms: 1200);
    expect(find.byType(Keypad), findsNothing);
    await shot('keypad-hidden-summary-visible');
    final suggestion = find.byKey(const Key('compose-description-suggestion'));
    expect(await waitFor(suggestion, ms: 5000), isTrue);
    print(
      'CHECK #2 suggestion="${find.descendant(of: suggestion, matching: find.byType(Text)).evaluate().map((e) => (e.widget as Text).data).join()}"',
    );
    expect(find.text('בפעם הקודמת: עיצוב חוברת FX1'), findsOneWidget);
    expect(
      find.byKey(const Key('compose-more-details')).hitTestable(),
      findsOneWidget,
    );
    // #1: + a line of 3 × ₪2.00 (incl. VAT) → ₪8.00.
    await tapKey('compose-more-details', ms: 1500);
    await tapKey('s3-add-line', ms: 1000);
    await tester.enterText(
      find.byKey(const Key('s3-line-0-description')),
      'כרטיסי ביקור',
    );
    await tester.enterText(find.byKey(const Key('s3-line-0-quantity')), '3');
    await tester.enterText(find.byKey(const Key('s3-line-0-price')), '2');
    await pumpMs(800);
    await shot('s3-line-3x2');
    await tapKey('s3-done', ms: 1500);
    await shot('305-total-8');
    final amount = tester.widget<Text>(find.byKey(const Key('compose-amount')));
    print('CHECK #1 headline=${amount.textSpan?.toPlainText()}');
    expect(amount.textSpan!.toPlainText(), '₪8.00');
    await tester.ensureVisible(find.byKey(const Key('compose-primary')));
    await pumpMs(700);
    await tester.tap(find.byKey(const Key('compose-primary')));
    await pumpMs(9000);
    await shot('305-issued');
    final issued = await lastDocOf(api, cid);
    final detail = await api.get('/documents/${issued['id']}');
    final doc = (detail['document'] ?? detail) as Map<String, dynamic>;
    print(
      'CHECK #1 issued ${doc['document_number'] ?? doc['documentNumber']} '
      'status=${doc['status']} total=${doc['total_minor'] ?? doc['totalMinor']} '
      'lines=${(detail['lines'] ?? doc['lines'])}',
    );
    expect('${doc['total_minor'] ?? doc['totalMinor']}', '800');
    await closeComposer();
    await go('/');
    await pumpMs(1500);

    // ---- #6: "הפק ושלח בווטסאפ" opens WhatsApp even when e-mailed --------
    final withPhone = await api.post('/customers', {
      'name': 'לקוח וואטסאפ FX1 $tag',
      'phone': '0501234567',
      'email': 'fx1-$tag@example.test',
    });
    final pid = withPhone['id'] as String;
    await api.post('/customers/$pid/consent', {'method': 'APP_TOGGLE'});
    await compose('TYPE:300', customerId: pid);
    await typeAmount('300');
    await shot('300-pill-whatsapp-button');
    print('CHECK #5/#6 primary="${primaryText()}"');
    expect(
      (tester.widget<Text>(find.byKey(const Key('compose-kind-label')))).data,
      'יופק: חשבון עסקה / פרופורמה',
    );
    opened.clear();
    await tester.tap(find.byKey(const Key('compose-primary')));
    await pumpMs(10000);
    await shot('300-issued-whatsapp');
    print('CHECK #6 opened=$opened');
    expect(opened.any((u) => u.host == 'wa.me'), isTrue);
    await closeComposer();
    await go('/');
    await pumpMs(1500);

    // ---- #4: an offline issue attempt leaves nothing behind on "מחק" ----
    final real = ApiClient.instance.httpClient;
    await compose('TYPE:305', customerId: cid);
    final again = find.byKey(const Key('resume-draft-new')).hitTestable();
    if (again.evaluate().isNotEmpty) {
      await tester.tap(again.first);
      await pumpMs(1500);
    }
    await typeAmount('777');
    ApiClient.instance.httpClient = _OfflineClient();
    await tester.tap(find.byKey(const Key('compose-primary')));
    await pumpMs(5000);
    await shot('offline-issue-failed');
    ApiClient.instance.httpClient = real;
    await pumpMs(500);
    await tapKey('compose-close', ms: 1200);
    await tapKey('save-draft-discard', ms: 4000);
    await go('/');
    await pumpMs(1500);
    await compose('TYPE:305');
    await pumpMs(1500);
    final leftover = find.byKey(const Key('resume-draft-dialog'));
    print('CHECK #4 leftover dialog=${leftover.evaluate().isNotEmpty}');
    await shot('after-discard-no-leftover');
    expect(leftover, findsNothing);
    await closeComposer();
    await go('/');
    await pumpMs(1500);

    // ---- #3: "<לקוח> אישר את ההצעה" → convert from the home card ---------
    final quote = await api.post('/quotes', {
      'customerId': cid,
      'currency': 'ILS',
      'validUntil': DateTime.now()
          .add(const Duration(days: 14))
          .toIso8601String()
          .substring(0, 10),
      'lines': [
        {
          'description': 'הצעת FX1',
          'quantityMicros': '1000000',
          'unitPriceMinor': '423729',
          'taxRateBasisPoints': 1800,
        },
      ],
    });
    final qid = quote['id'] as String;
    final link = await api.post('/quotes/$qid/share-link');
    final token = '${link['url']}'.split('/').last;
    const base = String.fromEnvironment('API_BASE');
    await api
        .post('/quotes/$qid/status', {'to': 'SENT'})
        .catchError((Object _) => <String, dynamic>{});
    final page = await http.get(Uri.parse('$base/q/$token'));
    final version = RegExp(
      r'name="version" value="([^"]*)"',
    ).firstMatch(page.body)?.group(1);
    print('CHECK #3 quote page ${page.statusCode} version=$version');
    final accept = await http.post(
      Uri.parse('$base/q/$token/accept'),
      headers: {'Content-Type': 'application/json'},
      body: '{"fullName":"לקוחת FX1","version":"$version"}',
    );
    print('CHECK #3 accept HTTP ${accept.statusCode}');
    await go('/');
    await pumpMs(1500);
    // Pull to refresh the home inbox.
    await tester.fling(
      find.byType(Scrollable).first,
      const Offset(0, 400),
      1500,
    );
    await pumpMs(4000);
    final card = find.byKey(const Key('inbox-QUOTE_ACCEPTED'));
    if (!await waitFor(card, ms: 8000)) {
      await go('/activity?chip=inbox');
      await pumpMs(3000);
    }
    expect(await waitFor(card, ms: 10000), isTrue);
    await tester.ensureVisible(card.first);
    await pumpMs(500);
    await shot('home-quote-accepted-card');
    await tester.tap(card.first);
    await pumpMs(2500);
    await tapKey('quote-choice-later', ms: 6000);
    await shot('converted-from-card');
    final c = find.byType(ComposeScreen);
    expect(await waitFor(c, ms: 10000), isTrue);
    await pumpMs(2000);
    final headline = tester.widget<Text>(
      find.byKey(const Key('compose-amount')),
    );
    print('CHECK #3 composer amount=${headline.textSpan?.toPlainText()}');
    expect(headline.textSpan!.toPlainText(), isNot('₪0.00'));
    expect(headline.textSpan!.toPlainText(), contains('5,000'));
    await closeComposer();
    print('FX1 DONE');
  });
}
