// CUS1 (feat/customer-timeline-terms) · screenshots of the customer timeline
// (ציר זמן) and payment terms (תנאי תשלום) against a local staging API that
// has migration 0110. Same SHOT: protocol as stage_c_screens_test.dart.
//
//   U=<CUS1 simulator udid>; OUT=$PWD/docs/qa-2026-11-17/customers/cus1
//   ~/flutter/bin/flutter test integration_test/cus1_screens_test.dart -d $U \
//     --dart-define=API_BASE=http://127.0.0.1:3046 [--dart-define=CUS1_PART=employee] 2>&1 |
//   while IFS= read -r l; do echo "$l"; if [[ $l == *SHOT:* ]]; then
//     n=${l##*SHOT:}; mkdir -p "$OUT/$(dirname $n)";
//     xcrun simctl io $U screenshot "$OUT/$n.png" >/dev/null 2>&1; fi; done
//
// PART owner (default) writes on staging: one customer with terms, a 305, a
// payment, a debt-book line, a WhatsApp reminder log row, a quote (sent +
// accepted) and a note. Nothing is sent to anyone. PART employee reads it.
// ignore_for_file: avoid_print, use_build_context_synchronously
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/router.dart' hide selectTab;
import 'package:invoice/screens/business/business_screen.dart'
    show openBusinessRow;

import 'crash_sweep_test.dart' show t, pumpMs, waitFor;
import 'persona_screens_test.dart'
    show
        role,
        shot,
        shotScroll,
        runCaptured,
        startPlansGuard,
        plansGuardOn,
        owner,
        guarded,
        hardRoot,
        noteFor,
        ctx;
import 'v2_qa_gate_helpers.dart' show launchSignedInAs;

const part = String.fromEnvironment('CUS1_PART', defaultValue: 'owner');
const employee = 'mobile-employee@tevel.test';
const customerName = 'סטודיו CUS1';

Future<void> tapKey(String key, {int ms = 1800}) async {
  final f = find.byKey(Key(key)).hitTestable();
  if (f.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      find.byKey(Key(key)),
      300,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await t.tap(find.byKey(Key(key)).first, warnIfMissed: false);
  await pumpMs(ms);
}

Future<String?> findCustomer() async {
  final r = await ApiClient.instance.get(
    '/customers',
    query: {'q': customerName, 'sort': 'recent', 'limit': '5'},
  );
  final list = (r['customers'] as List?) ?? const [];
  return list.isEmpty ? null : (list.first as Map)['id'] as String;
}

/// The Composer for the customer: the due date from the terms (S3) and the
/// preferred method chip of a paid kind.
Future<void> composeShots(String id) async {
  await guarded('compose prefill', () async {
    unawaited(openCompose(ctx, intent: 'PAID', customerId: id));
    await pumpMs(4500);
    await shot('compose-paid-preferred-method');
    await hardRoot();
    unawaited(openCompose(ctx, intent: 'REQUEST', customerId: id));
    await pumpMs(4500);
    await shot('compose-request');
    final more = find.byKey(const Key('compose-more-details'));
    if (more.evaluate().isEmpty) {
      final keypad = find.byKey(const Key('compose-show-keypad'));
      noteFor('more-details hidden (keypad up?) ${keypad.evaluate().length}');
      await t.tap(find.text('1').first, warnIfMissed: false);
      await pumpMs(500);
      await t.tap(find.text('0').first, warnIfMissed: false);
      await pumpMs(800);
    }
    if (more.evaluate().isNotEmpty) {
      await t.ensureVisible(more.first);
      await t.tap(more.first, warnIfMissed: false);
      await pumpMs(2200);
      await shot('compose-due-date-prefilled');
    } else {
      noteFor('no compose-more-details');
    }
    await hardRoot();
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  startPlansGuard();

  testWidgets('cus1 screens ($part)', (tester) async {
    await runCaptured(tester, () async {
      role = part;
      plansGuardOn = true;
      await launchSignedInAs(t, part == 'employee' ? employee : owner);
      await waitFor(find.byKey(const Key('tab-home')), ms: 40000);
      await pumpMs(3000);
      final api = ApiClient.instance;
      final n = Random().nextInt(900000) + 100000;
      String? customerId;

      if (part == 'owner') {
        await guarded('data', () async {
          final c = await api.post('/customers', {
            'name': '$customerName $n',
            'customerType': 'BUSINESS',
            'phone': '050${Random().nextInt(9000000) + 1000000}',
          });
          customerId = ((c['customer'] as Map?)?['id'] ?? c['id']) as String;
          await api.patch('/customers/$customerId', {
            'vatDealerStatus': 'PRIVATE',
            'paymentTerms': 'EOM_30',
            'preferredPaymentMethod': 'BANK_TRANSFER',
          });
          final doc = await api.post('/documents', {
            'documentType': 'TAX_INVOICE',
            'customerId': customerId,
            'currency': 'ILS',
            'lines': [
              {
                'description': 'עיצוב לוגו',
                'quantityMicros': '1000000',
                'unitPriceMinor': '250000',
                'discountMinor': '0',
                'taxRateBasisPoints': 1800,
              },
            ],
          });
          final docId = doc['id'] as String;
          final fin = await api.post('/documents/$docId/finalize', {
            'scopeKey': 'default',
          }, 'cus1-fin-$n');
          print('NOTE:cus1: finalize → ${fin['status']}');
          final pay = await api.post('/payments', {
            'method': 'BANK_TRANSFER',
            'amountMinor': '100000',
            'currency': 'ILS',
            'paymentDate': DateTime.now().toIso8601String().substring(0, 10),
          }, 'cus1-pay-$n');
          await api.post('/documents/$docId/payments', {
            'paymentId': pay['paymentId'] ?? pay['id'],
            'amountMinor': '100000',
          });
          await api.post('/reminders/log', {
            'documentIds': [docId],
            'debtEntryIds': <String>[],
            'channel': 'WHATSAPP',
          });
          await api.post('/debt-entries', {
            'customerId': customerId,
            'amountMinor': '45000',
            'note': 'שעת ייעוץ נוספת',
          }, 'cus1-debt-$n');
          final q = await api.post('/quotes', {
            'customerId': customerId,
            'currency': 'ILS',
            'lines': [
              {
                'description': 'אתר תדמית',
                'quantityMicros': '1000000',
                'unitPriceMinor': '900000',
              },
            ],
          });
          final qid = ((q['quote'] as Map?)?['id'] ?? q['id']) as String;
          await api.post('/quotes/$qid/status', {'to': 'SENT'});
          await api.post('/quotes/$qid/status', {'to': 'ACCEPTED'});
          await api.post('/customers/$customerId/notes', {
            'body': 'מעדיפה שיחה בבוקר. החשבונית נשלחת גם לרו״ח שלה.',
          });
        });
      } else {
        customerId = await findCustomer();
      }
      final id = customerId;
      if (id == null) {
        noteFor('no customer');
        return;
      }

      if (part == 'compose') {
        await composeShots(id);
        return;
      }

      await guarded('card', () async {
        unawaited(openPerson(ctx, id));
        await pumpMs(3500);
        await shotScroll('card', pages: 2);
      });

      await guarded('timeline', () async {
        await tapKey('person-timeline', ms: 3500);
        await shotScroll('timeline', pages: 2);
        if (part == 'owner') {
          await tapKey('timeline-add-note');
          await shot('add-note-sheet');
          await t.enterText(
            find.byKey(const Key('note-text')),
            'לשלוח הצעה לתחזוקה שנתית בינואר',
          );
          await pumpMs(600);
          await tapKey('note-save', ms: 3000);
          await shot('timeline-after-note');
        }
        await hardRoot();
      });

      if (part != 'owner') return;

      await guarded('terms sheet', () async {
        unawaited(openPerson(ctx, id));
        await pumpMs(3500);
        await tapKey('person-terms');
        await shot('terms-sheet');
        await t.tap(find.text('מותאם').first, warnIfMissed: false);
        await pumpMs(600);
        await t.enterText(find.byKey(const Key('terms-days')), '14');
        await t.tap(find.text('מתאריך המסמך').first, warnIfMissed: false);
        await pumpMs(800);
        await shot('terms-sheet-custom');
        await tapKey('terms-save', ms: 3000);
        await shot('card-after-terms');
        await hardRoot();
      });

      await composeShots(id);

      await guarded('business default', () async {
        openBusinessRow(ctx, 'paymentTerms');
        await pumpMs(3000);
        await shot('business-default-terms');
        await hardRoot();
      });
    });
  });
}
