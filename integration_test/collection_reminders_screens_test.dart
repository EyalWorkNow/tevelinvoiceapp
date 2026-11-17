// Automatic collection reminders (server 0111) · screenshots on a local
// staging server where the sweep already ran (one e-mail reminder sent, the
// WhatsApp ones waiting). Same SHOT: protocol as persona_screens_test.dart.
//
//   U=<CUS2 simulator>; OUT=$PWD/docs/qa-2026-11-17/customers/cus2
//   ~/flutter/bin/flutter test integration_test/collection_reminders_screens_test.dart -d $U \
//     --dart-define=API_BASE=http://127.0.0.1:3047 --dart-define=MAILDIR=<catcher dir> 2>&1 |
//   while IFS= read -r l; do echo "$l"; if [[ $l == *SHOT:* ]]; then
//     n=${l##*SHOT:}; mkdir -p "$OUT/$(dirname $n)";
//     xcrun simctl io $U screenshot "$OUT/$n.png" >/dev/null 2>&1; fi; done
//
// Read-only on staging except: nothing is sent or changed (no taps on send).
// ignore_for_file: avoid_print, use_build_context_synchronously
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/api/collection_reminders_api.dart';
import 'package:invoice/router.dart' hide selectTab;
import 'package:invoice/screens/business/collection_settings_screen.dart';
import 'package:invoice/screens/debts/collection_batch_screen.dart';

import 'crash_sweep_test.dart' show t, pumpMs, waitFor;
import 'persona_screens_test.dart'
    show
        role,
        shot,
        shotScroll,
        runCaptured,
        owner,
        guarded,
        hardRoot,
        noteFor,
        ctx;
import 'v2_qa_gate_helpers.dart' show launchSignedInAs;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('collection reminder screens', (tester) async {
    await runCaptured(tester, () async {
      role = 'cus2';
      await launchSignedInAs(t, owner);
      await waitFor(find.byKey(const Key('tab-home')), ms: 40000);
      await pumpMs(3000);

      final ready = await fetchReadyReminders();
      print('NOTE:cus2: ${ready.length} reminders ready');
      final yossi = ready.where((r) => r.customerName == 'יוסי לוי (QA)');
      final history = await fetchCollectionHistory();
      final emailed = history.where((r) => r.channel == 'EMAIL').toList();

      await guarded('debts banner', () async {
        unawaited(openDebts(ctx));
        await pumpMs(3500);
        await shot('debts-ready-banner');
        await hardRoot();
      });

      await guarded('batch', () async {
        unawaited(openCollectionBatch(ctx));
        await pumpMs(3500);
        await shotScroll('whatsapp-batch', pages: 2);
        await hardRoot();
      });

      await guarded('push deep link', () async {
        final page = screenFor(AppRoute.parse('/debts?batch=1')!);
        unawaited(
          Navigator.of(
            ctx,
          ).push(MaterialPageRoute<void>(builder: (_) => page!)),
        );
        await pumpMs(4500);
        await shot('push-link-opens-batch');
        await hardRoot();
      });

      await guarded('settings', () async {
        unawaited(openCollectionSettings(ctx));
        await pumpMs(3500);
        await shotScroll('ladder-settings', pages: 2);
        final edit = find.byKey(const Key('collection-step-edit-2'));
        if (edit.evaluate().isNotEmpty) {
          await t.ensureVisible(edit);
          await t.tap(edit);
          await pumpMs(2000);
          await shotScroll('step-editor', pages: 2);
        } else {
          noteFor('no step editor button');
        }
        await hardRoot();
      });

      await guarded('customer opt-out', () async {
        if (yossi.isEmpty || yossi.first.customerId == null) {
          noteFor('no QA customer in the batch');
          return;
        }
        unawaited(openPerson(ctx, yossi.first.customerId!));
        await pumpMs(4000);
        final hold = find.byKey(const Key('reminder-hold-customer'));
        try {
          await t.scrollUntilVisible(
            hold,
            250,
            scrollable: find.byType(Scrollable).first,
          );
        } on Object {
          noteFor('reminder-hold-customer not found');
        }
        await shot('customer-opt-out');
        await hardRoot();
      });

      await guarded('document pause', () async {
        if (emailed.isEmpty || emailed.first.documentId == null) {
          noteFor('no e-mailed document');
          return;
        }
        unawaited(openDocument(ctx, emailed.first.documentId!));
        await pumpMs(4500);
        final pause = find.byKey(const Key('reminder-hold-document'));
        try {
          await t.scrollUntilVisible(
            pause,
            250,
            scrollable: find.byType(Scrollable).first,
          );
        } on Object {
          noteFor('reminder-hold-document not found');
        }
        await shot('document-pause');
        await hardRoot();
      });
    });
  });
}
