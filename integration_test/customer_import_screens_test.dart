// ייבוא לקוחות (QA 2026-11-17 · CUS3) · screenshots of the customer import flow on the
// simulator against a local staging API: a Green Invoice style xlsx (title row, messy
// phones, invalid id, duplicates) and the phone's contacts (native multi-select source).
// Same SHOT: protocol as persona_screens_test.dart.
//
//   U=<CUS3 udid>; OUT=$PWD/docs/qa-2026-11-17/customers/cus3
//   xcrun simctl privacy $U grant contacts space.tevel.invoice
//   xcrun simctl addmedia $U integration_test/fixtures/import-contacts.vcf
//   ~/flutter/bin/flutter test integration_test/customer_import_screens_test.dart -d $U \
//     --dart-define=API_BASE=http://127.0.0.1:3048 \
//     --dart-define=MAILDIR=$HOME/invoiceproject-staging-cus3/outgoing-emails \
//     --dart-define=FIXTURE=$PWD/integration_test/fixtures/green-invoice-customers.xlsx 2>&1 |
//   while IFS= read -r l; do echo "$l"; if [[ $l == *SHOT:* ]]; then
//     n=${l##*SHOT:}; mkdir -p "$OUT/$(dirname $n)";
//     xcrun simctl io $U screenshot "$OUT/$n.png" >/dev/null 2>&1; fi; done
//
// The file is handed to the flow directly (the system document picker cannot be driven
// from a Flutter test); the contacts go through the real native channel. Writes on
// staging: the imported customers. Nothing is sent.
// ignore_for_file: avoid_print, use_build_context_synchronously
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/router.dart' hide selectTab;
import 'package:invoice/screens/people/import/customer_import_screen.dart';
import 'package:invoice/util/labels/customer_import_he.dart';

import 'crash_sweep_test.dart' show t, pumpMs, waitFor;
import 'persona_screens_test.dart'
    show role, shot, shotScroll, runCaptured, owner, guarded, hardRoot, noteFor;
import 'v2_qa_gate_helpers.dart' show launchSignedInAs;

const _fixture = String.fromEnvironment('FIXTURE');

Future<void> tapKey(String key, {int ms = 2500}) async {
  final f = find.byKey(Key(key)).hitTestable();
  await waitFor(f, ms: 20000);
  await t.tap(f.first, warnIfMissed: false);
  await pumpMs(ms);
}

Future<void> tapText(String text, {int ms = 2500}) async {
  final f = find.text(text).hitTestable();
  await waitFor(f, ms: 20000);
  await t.tap(f.first, warnIfMissed: false);
  await pumpMs(ms);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('customer import screens', (tester) async {
    await runCaptured(tester, () async {
      role = 'cus3';
      if (_fixture.isNotEmpty) {
        final bytes = await File(_fixture).readAsBytes();
        pickImportFile = () async =>
            PickedImportFile(_fixture.split('/').last, bytes);
      }
      await launchSignedInAs(t, owner);
      await waitFor(find.byKey(const Key('tab-home')), ms: 40000);
      await pumpMs(3000);

      await guarded('people menu', () async {
        openPeople();
        await pumpMs(3500);
        await shot('people-before');
        await tapKey('people-more', ms: 1500);
        await shot('people-menu');
        await tapText(ImportHe.menuImport, ms: 3000);
        await shot('import-source');
      });

      await guarded('file import', () async {
        await tapKey('import-source-file', ms: 5000);
        await shotScroll('file-mapping', pages: 4);
        await tapKey('import-check', ms: 5000);
        await shot('review-new');
        await tapText(
          find
                  .textContaining('כבר קיימים')
                  .evaluate()
                  .map((e) => (e.widget as Text).data!)
                  .firstOrNull ??
              ImportHe.tabDuplicates,
        );
        await shot('review-duplicates');
        await tapText(ImportHe.policyMerge);
        await shot('review-duplicates-merge');
        await tapText(
          find
                  .textContaining('עם שגיאות')
                  .evaluate()
                  .map((e) => (e.widget as Text).data!)
                  .firstOrNull ??
              ImportHe.tabErrors,
        );
        await shot('review-errors');
        final tiles = find.descendant(
          of: find.byKey(const Key('import-review-list')),
          matching: find.byType(ListTile),
        );
        if (tiles.evaluate().isNotEmpty) {
          await t.tap(tiles.first, warnIfMissed: false);
          await pumpMs(1500);
          await shot('fix-row-dialog');
          await tapText('ביטול', ms: 1200);
        }
        await tapKey('import-start', ms: 8000);
        await shotScroll('file-summary', pages: 2);
        await tapKey('import-done', ms: 3500);
        await shot('people-after-file');
      });

      await guarded('contacts import', () async {
        await tapKey('people-more', ms: 1500);
        await tapText(ImportHe.menuImport, ms: 3000);
        await tapKey('import-source-contacts', ms: 6000);
        await shot('contacts-list');
        final search = find.byKey(const Key('import-contacts-search'));
        if (search.evaluate().isNotEmpty) {
          await t.enterText(search, 'ל');
          await pumpMs(1500);
          await tapKey('import-contacts-all', ms: 1200);
          await shot('contacts-search-selected');
          await t.enterText(search, '');
          await pumpMs(1500);
          await shot('contacts-selected');
          await tapKey('import-contacts-continue', ms: 6000);
          await shot('contacts-review');
          await tapKey('import-start', ms: 8000);
          await shot('contacts-summary');
          await tapKey('import-done', ms: 3500);
          await shot('people-after-contacts');
        } else {
          noteFor('contacts list did not open (permission?)');
          await shot('contacts-state');
          await hardRoot();
        }
      });

      await guarded('export', () async {
        await tapKey('people-more', ms: 1500);
        unawaited(
          Future(() async {
            await tapText(ImportHe.menuExport, ms: 6000);
          }),
        );
        await pumpMs(7000);
        print('SHOT:cus3/99-export-share-sheet');
        await pumpMs(4000);
      });
    });
  });
}
