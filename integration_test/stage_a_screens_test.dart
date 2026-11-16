// Stage A (QA 2026-11-16) · screenshots the persona driver does not reach:
// a document waiting for its allocation number with a payment kept on the
// server (SA2). Same SHOT: protocol as persona_screens_test.dart.
//
//   U=EF82558D-7B24-4BDD-8B96-DA66170CF700
//   ~/flutter/bin/flutter test integration_test/stage_a_screens_test.dart -d $U \
//     --dart-define=API_BASE=http://127.0.0.1:3041 \
//     --dart-define=MAILDIR=$HOME/invoiceproject-staging-qa/outgoing-emails
//   (pipe through the persona runner loop to take the screenshots)
//
// Writes on staging: one customer and one 320 that waits for its number
// (rule 0094, SHAAM off) with a pending cash payment.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/router.dart' hide selectTab;

import 'crash_sweep_test.dart' show t, pumpMs, waitFor;
import 'persona_screens_test.dart'
    show
        role,
        shotScroll,
        runCaptured,
        startPlansGuard,
        plansGuardOn,
        owner,
        guarded;
import 'v2_qa_gate_helpers.dart' show launchSignedInAs;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  startPlansGuard();

  testWidgets('stage A screens', (tester) async {
    await runCaptured(tester, () async {
      role = 'stageA';
      plansGuardOn = true;
      await launchSignedInAs(t, owner);
      await waitFor(find.byKey(const Key('tab-home')), ms: 40000);
      await pumpMs(3000);
      await guarded('pending payment on a waiting document', () async {
        final api = ApiClient.instance;
        final n = Random().nextInt(900000) + 100000;
        final customer = await api.post('/customers', {
          'name': 'לקוח עסקי שלב A $n',
          'phone': '050${Random().nextInt(9000000) + 1000000}',
          'taxId': _validTaxId(),
          'vatDealerStatus': 'AUTHORIZED_DEALER',
        });
        final customerId =
            (customer['customer'] as Map?)?['id'] ?? customer['id'];
        final doc = await api.post('/documents', {
          'documentType': 'TAX_INVOICE_RECEIPT',
          'customerId': customerId,
          'currency': 'ILS',
          'lines': [
            {
              'description': 'עבודת חשמל',
              'quantityMicros': '1000000',
              'unitPriceMinor': '600000',
              'discountMinor': '0',
              'taxRateBasisPoints': 1800,
            },
          ],
        });
        final id = doc['id'] as String;
        final fin = await api.post(
          '/documents/$id/finalize',
          {
            'scopeKey': 'default',
            'pendingPayments': [
              {'method': 'CASH'},
            ],
          },
          'stageA-$n',
        );
        print('NOTE:stageA: finalize → ${fin['status']} ${fin['pendingPayments']}');
        // Completes when D closes.
        unawaited(openDocument(navigatorKey.currentContext!, id));
        await pumpMs(3500);
        await shotScroll('doc-waiting-pending-payment', pages: 2);
      });
    });
  }, timeout: const Timeout(Duration(minutes: 15)));
}

/// A valid Israeli ח.פ. (check digit), starting with 51.
String _validTaxId() {
  final r = Random();
  final d = [5, 1, for (var i = 0; i < 6; i++) r.nextInt(10)];
  var sum = 0;
  for (var i = 0; i < 8; i++) {
    var x = d[i] * (i.isEven ? 1 : 2);
    if (x > 9) x -= 9;
    sum += x;
  }
  return '${d.join()}${(10 - sum % 10) % 10}';
}
