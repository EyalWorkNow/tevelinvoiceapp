// Quotes journey (owner feedback 2026-11-16: "the whole quote feature needs
// fixing"). Walks a small-business owner through the quote life cycle on the
// simulator and prints SHOT: markers (same protocol as stage_c_screens_test).
//
//   U=<QT sim udid>; OUT=$PWD/docs/qa-2026-11-16/owner-feedback/quotes/<before|after>
//   ~/flutter/bin/flutter test integration_test/quotes_journey_test.dart -d $U \
//     --dart-define=API_BASE=http://127.0.0.1:3043 \
//     --dart-define=MAILDIR=$HOME/invoiceproject-staging-qt/outgoing-emails 2>&1 |
//   while IFS= read -r l; do echo "$l"; if [[ $l == *SHOT:* ]]; then
//     n=${l##*SHOT:}; mkdir -p "$OUT/$(dirname $n)";
//     xcrun simctl io $U screenshot "$OUT/$n.png" >/dev/null 2>&1; fi; done
//
// Writes on staging: customers and quotes. WhatsApp is faked (urlOpener).
// ignore_for_file: avoid_print, use_build_context_synchronously
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/router.dart' hide selectTab;
import 'package:invoice/screens/compose/compose_submit.dart' as submit;
import 'package:invoice/util/allowed_urls.dart';

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
        noteFor,
        ctx;
import 'v2_qa_gate_helpers.dart' show launchSignedInAs;

String _day(int offset) => DateTime.now()
    .add(Duration(days: offset))
    .toIso8601String()
    .substring(0, 10);

Map<String, dynamic> _line(String d, int priceMinor, {int qty = 1}) => {
  'description': d,
  'quantityMicros': '${qty * 1000000}',
  'unitPriceMinor': '$priceMinor',
  'discountMinor': '0',
  'taxRateBasisPoints': 1800,
};

Future<void> _tapKey(String key) async {
  final f = find.byKey(Key(key)).hitTestable();
  if (!await waitFor(f, ms: 6000)) {
    noteFor('no $key');
    return;
  }
  await t.ensureVisible(f.first);
  await t.tap(f.first, warnIfMissed: false);
  await pumpMs(900);
}

Future<void> _tapText(String text) async {
  final f = find.text(text).hitTestable();
  if (!await waitFor(f, ms: 5000)) {
    noteFor('no "$text"');
    return;
  }
  await t.tap(f.last, warnIfMissed: false);
  await pumpMs(1200);
}

Future<void> _more() async {
  final m = find.byTooltip('עוד').hitTestable();
  if (!await waitFor(m, ms: 5000)) {
    noteFor('no ⋯');
    return;
  }
  await t.tap(m.last, warnIfMissed: false);
  await pumpMs(1200);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  startPlansGuard();

  testWidgets('quotes journey', (tester) async {
    await runCaptured(tester, () async {
      role = const String.fromEnvironment('ROLE', defaultValue: 'quotes');
      plansGuardOn = true;
      final launched = <Uri>[];
      urlOpener = (uri, {inApp = false}) async {
        launched.add(uri);
        print('NOTE:quotes: launch ${Uri.decodeFull(uri.toString())}');
        return true;
      };
      submit.shareText = (text) async => print('NOTE:quotes: share $text');
      await launchSignedInAs(t, owner);
      await waitFor(find.byKey(const Key('tab-home')), ms: 40000);
      await pumpMs(3000);
      final api = ApiClient.instance;
      final n = Random().nextInt(900000) + 100000;

      Future<String> customer(String name, {bool phone = true}) async {
        final c = await api.post('/customers', {
          'name': '$name $n',
          'customerType': 'INDIVIDUAL',
          if (phone) 'phone': '050${Random().nextInt(9000000) + 1000000}',
        });
        return ((c['customer'] as Map?)?['id'] ?? c['id']) as String;
      }

      late String cust;
      late String sentId;
      late String expiredId;
      // The host can be very busy (other simulators / suites): retry the
      // fixture writes rather than skip the whole journey.
      for (var attempt = 0; attempt < 3; attempt++) {
        var ok = false;
        await guarded('data', () async {
          cust = await customer('רונית שיפוצים');
          final s = await api.post('/quotes', {
            'customerId': cust,
            'currency': 'ILS',
            'validUntil': _day(14),
            'notes': 'כולל חומרים. תשלום שוטף +30.',
            'lines': [
              _line('צביעת דירה 4 חדרים', 450000),
              _line('תיקון טיח', 35000, qty: 3),
            ],
          });
          sentId = s['id'] as String;
          await api.post('/quotes/$sentId/status', {'to': 'SENT'});
          // Past validity cannot be created any more (QUOTE_VALID_UNTIL_PAST):
        // the host ages one quote in the DB and passes its id.
        expiredId = const String.fromEnvironment('EXPIRED_ID');
        ok = true;
        });
        if (ok) break;
      }

      await guarded('entry points', () async {
        unawaited(openActivity(ctx, chip: 'quotes'));
        await pumpMs(3500);
        await shotScroll('list-quotes', pages: 1);
        await hardRoot();
      });

      await guarded('compose new quote', () async {
        unawaited(openCompose(ctx, intent: 'QUOTE', customerId: cust));
        await pumpMs(3500);
        await shot('compose-empty');
        await typeKeypad('1500');
        await shot('compose-amount');
        await _tapKey('compose-more-details');
        await shotScroll('compose-more-details', pages: 3);
        await _tapKey('s3-add-line');
        await shot('compose-add-line');
        final done = find.byKey(const Key('s3-done')).hitTestable();
        if (done.evaluate().isNotEmpty) {
          await t.tap(done.first, warnIfMissed: false);
          await pumpMs(1000);
        }
        await shot('compose-before-send');
        await hardRoot();
      });

      await guarded('quote D (sent)', () async {
        unawaited(openQuote(ctx, sentId));
        await pumpMs(5000);
        await shotScroll('quote-sent', pages: 2);
        await _more();
        await shot('quote-sent-menu');
        await hardRoot();
      });

      await guarded('quote D (expired)', () async {
        unawaited(openQuote(ctx, expiredId));
        await pumpMs(5000);
        await shot('quote-expired');
        await _more();
        await shot('quote-expired-menu');
        await hardRoot();
      });

      await guarded('send flow', () async {
        unawaited(openCompose(ctx, intent: 'QUOTE', customerId: cust));
        await pumpMs(3500);
        await typeKeypad('2400');
        await _tapKey('compose-primary');
        await pumpMs(6000);
        await shot('after-send');
        noteFor(
          'launched: ${launched.map((u) => Uri.decodeFull(u.toString())).join(' || ')}',
        );
        await hardRoot();
      });

      await guarded('save without sending → D → ⋯ → delete', () async {
        unawaited(openCompose(ctx, intent: 'QUOTE', customerId: cust));
        await pumpMs(3500);
        await typeKeypad('990');
        await shot('compose-save-option');
        await _tapKey('compose-save-quote');
        await pumpMs(6000);
        await shot('saved-draft-d');
        await _more();
        await shot('saved-draft-menu');
        await _tapText('מחק טיוטה');
        await shot('delete-confirm');
        final yes = find.byKey(const Key('quote-delete-yes'));
        if (yes.evaluate().isNotEmpty) {
          await t.tap(yes, warnIfMissed: false);
          await pumpMs(3000);
        }
        await shot('after-delete');
        await hardRoot();
      });

      await guarded('edit expired → +14 days', () async {
        unawaited(openQuote(ctx, expiredId));
        await pumpMs(5000);
        await _tapKey('doc-primary');
        await pumpMs(3500);
        await _tapKey('compose-more-details');
        await shot('extend-validity-composer');
        await hardRoot();
      });

      await guarded('list after', () async {
        unawaited(openActivity(ctx, chip: 'quotes'));
        await pumpMs(3500);
        await shot('list-quotes-after');
        await hardRoot();
      });

      await guarded('convert', () async {
        unawaited(openQuote(ctx, sentId));
        await pumpMs(5000);
        await _tapText('הפוך לחשבונית');
        await shot('convert-choice');
        await hardRoot();
      });
    });
  }, timeout: const Timeout(Duration(minutes: 20)));
}
