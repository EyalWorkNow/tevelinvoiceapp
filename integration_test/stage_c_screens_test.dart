// Stage C (QA 2026-11-16) · screenshots of the six Stage C features after the
// integration (C1 מי חייב לי + ספר חובות, C2 סיכום יום, C3 פיצול / הצעה →
// שילם עכשיו / כמו בפעם הקודמת, C4 חבילת ריטיינר, C5 יומן פעולות, C6 מוכן
// לרו״ח + בקש תיקון). Same SHOT: protocol as persona_screens_test.dart.
//
//   U=EF82558D-7B24-4BDD-8B96-DA66170CF700; OUT=docs/qa-2026-11-16/stageC-screens
//   ~/flutter/bin/flutter test integration_test/stage_c_screens_test.dart -d $U \
//     --dart-define=API_BASE=http://127.0.0.1:3041 \
//     --dart-define=MAILDIR=$HOME/invoiceproject-staging-qa/outgoing-emails 2>&1 |
//   while IFS= read -r l; do echo "$l"; if [[ $l == *SHOT:* ]]; then
//     n=${l##*SHOT:}; mkdir -p "$OUT/$(dirname $n)";
//     xcrun simctl io $U screenshot "$OUT/$n.png" >/dev/null 2>&1; fi; done
//
// Writes on staging: two customers, one debt-book line, one small 320 (paid,
// cash) and one quote. Nothing is sent.
// ignore_for_file: avoid_print, use_build_context_synchronously
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/api/issue_api.dart' show fetchDocument;
import 'package:invoice/api/reports_api.dart' show dailySummaryKind;
import 'package:invoice/router.dart' hide selectTab;
import 'package:invoice/screens/audit/audit_log_screen.dart';
import 'package:invoice/screens/compose/sheets/quote_paid_choice.dart';
import 'package:invoice/screens/reports/correction_request_sheet.dart';
import 'package:invoice/screens/retainers/retainers_month_screen.dart';

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
        typeKeypad,
        closeComposeDiscard,
        noteFor,
        ctx;
import 'v2_qa_gate_helpers.dart' show launchSignedInAs;

final _line = {
  'description': 'שיעור פרטי',
  'quantityMicros': '1000000',
  'unitPriceMinor': '35000',
  'discountMinor': '0',
  'taxRateBasisPoints': 1800,
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  startPlansGuard();

  testWidgets('stage C screens', (tester) async {
    await runCaptured(tester, () async {
      role = 'stageC';
      plansGuardOn = true;
      await launchSignedInAs(t, owner);
      await waitFor(find.byKey(const Key('tab-home')), ms: 40000);
      await pumpMs(3000);
      final api = ApiClient.instance;
      final n = Random().nextInt(900000) + 100000;

      Future<String> customer(String name) async {
        final c = await api.post('/customers', {
          'name': '$name $n',
          'customerType': 'INDIVIDUAL',
          'phone': '050${Random().nextInt(9000000) + 1000000}',
        });
        return ((c['customer'] as Map?)?['id'] ?? c['id']) as String;
      }

      late String regular;
      late String paidDocId;
      await guarded('data', () async {
        final debtor = await customer('יוסי שיעורים');
        await api.post('/debt-entries', {
          'customerId': debtor,
          'amountMinor': '70000',
          'note': '2 שיעורים',
        }, 'stageC-debt-$n');
        regular = await customer('סיגל לקוחה קבועה');
        final doc = await api.post('/documents', {
          'documentType': 'TAX_INVOICE_RECEIPT',
          'customerId': regular,
          'currency': 'ILS',
          'lines': [_line],
        });
        paidDocId = doc['id'] as String;
        final fin = await api.post('/documents/$paidDocId/finalize', {
          'scopeKey': 'default',
          'recordPendingPayments': true,
          'pendingPayments': [
            {'method': 'CASH'},
          ],
        }, 'stageC-fin-$n');
        print('NOTE:stageC: finalize → ${fin['status']}');
      });

      await guarded('home', () async {
        await shot('home-debts-row');
      });

      await guarded('debts', () async {
        unawaited(openDebts(ctx));
        await pumpMs(3500);
        await shotScroll('who-owes-me', pages: 2);
        final add = find.text('רשום חוב').hitTestable();
        if (add.evaluate().isNotEmpty) {
          await t.tap(add.first, warnIfMissed: false);
          await pumpMs(1500);
          await shot('debt-book-entry-sheet');
        } else {
          noteFor('no "רשום חוב" button');
        }
        await hardRoot();
      });

      await guarded('daily summary', () async {
        unawaited(openReport(ctx, dailySummaryKind));
        await pumpMs(3500);
        await shotScroll('daily-summary', pages: 2);
        await hardRoot();
      });

      await guarded('split payment', () async {
        unawaited(openCompose(ctx, intent: 'PAID', customerId: regular));
        await pumpMs(3500);
        await shot('compose-same-as-last-time');
        await typeKeypad('1180');
        final cash = find.descendant(
          of: find.byKey(const Key('compose-methods')),
          matching: find.text('מזומן'),
        );
        if (cash.evaluate().isNotEmpty) {
          await t.ensureVisible(cash.first);
          await t.tap(cash.first, warnIfMissed: false);
          await pumpMs(600);
        }
        final split = find.byKey(const Key('compose-split'));
        if (await waitFor(split, ms: 3000)) {
          await t.ensureVisible(split.first);
          await t.tap(split.first, warnIfMissed: false);
          await pumpMs(800);
          final amount0 = find.byKey(const Key('split-amount-0'));
          if (amount0.evaluate().isNotEmpty) {
            await t.enterText(amount0, '590');
            await pumpMs(400);
            final add = find.byKey(const Key('split-add'));
            await t.ensureVisible(add);
            await t.tap(add, warnIfMissed: false);
            await pumpMs(800);
            FocusManager.instance.primaryFocus?.unfocus();
          }
          await shotScroll('compose-split-payment', pages: 2);
        } else {
          noteFor('no split button');
        }
        await closeComposeDiscard();
      });

      await guarded('same as last time (customer card)', () async {
        unawaited(openPerson(ctx, regular));
        await pumpMs(3500);
        await shot('person-same-as-last-time');
        await hardRoot();
      });

      await guarded('quote → paid now', () async {
        final q = await api.post('/quotes', {
          'customerId': regular,
          'currency': 'ILS',
          'validUntil': DateTime.now()
              .add(const Duration(days: 14))
              .toIso8601String()
              .substring(0, 10),
          'lines': [_line],
        });
        unawaited(openQuote(ctx, q['id'] as String));
        await pumpMs(3500);
        unawaited(askQuotePaid(ctx, exempt: false));
        await pumpMs(1500);
        await shot('quote-paid-now-choice');
        await hardRoot();
      });

      await guarded('retainers', () async {
        try {
          await api.post('/recurring/templates', {
            'sourceDocumentId': paidDocId,
            'dayOfMonth': 1,
          });
        } on ApiException catch (e) {
          // 320 is not a template kind (C4): the screen shows its empty month.
          print('NOTE:stageC: template from 320 → ${e.code}');
        }
        unawaited(openRetainersMonth(ctx));
        await pumpMs(3500);
        await shotScroll('retainers-month', pages: 2);
        await hardRoot();
      });

      await guarded('audit log', () async {
        unawaited(openAuditLog(ctx));
        await pumpMs(4000);
        await shotScroll('audit-log', pages: 2);
        await hardRoot();
      });

      await guarded('readiness', () async {
        unawaited(openReports(ctx));
        await pumpMs(4500);
        await shotScroll('reports-readiness-card', pages: 2);
        await hardRoot();
      });

      await guarded('correction request', () async {
        unawaited(openDocument(ctx, paidDocId));
        await pumpMs(3500);
        final doc = await fetchDocument(paidDocId);
        unawaited(showCorrectionRequestSheet(ctx, doc));
        await pumpMs(1500);
        await shot('correction-request-sheet');
        await hardRoot();
      });
    });
  }, timeout: const Timeout(Duration(minutes: 20)));
}
