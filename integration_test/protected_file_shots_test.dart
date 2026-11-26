// §7 "קובץ מוגן בסיסמה" shots, 2026-11-25, with MOCKED data (the test
// FakeBackend, no server). Prints SHOT: markers (same protocol as
// customer_page_shots_test):
//
//   U=<sim udid>; OUT=$PWD/docs/qa/2611-v2
//   ~/flutter/bin/flutter test integration_test/protected_file_shots_test.dart -d $U 2>&1 |
//   while IFS= read -r l; do echo "$l"; if [[ $l == *SHOT:* ]]; then
//     n=${l##*SHOT:}; xcrun simctl io $U screenshot "$OUT/$n.png" >/dev/null 2>&1; fi; done
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/debts/reminder_hold_tile.dart';
import 'package:invoice/screens/document/document_screen.dart';
import 'package:invoice/screens/document/sheets/s6_share.dart';
import 'package:invoice/state/caps.dart';

import '../test/business/e_harness.dart';
import '../test/fakes/fake_api.dart';

late WidgetTester t;

Future<void> pumpMs(int ms) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  do {
    await t.pump(const Duration(milliseconds: 50));
  } while (DateTime.now().isBefore(end));
}

Future<void> shot(String name) async {
  await pumpMs(1200);
  print('SHOT:$name');
  await pumpMs(1300);
}

Future<bool> tapIf(Finder f, {int waitMs = 1200}) async {
  for (var i = 0; i < 20 && f.evaluate().isEmpty; i++) {
    await pumpMs(150);
  }
  if (f.evaluate().isEmpty && find.byType(Scrollable).evaluate().isNotEmpty) {
    try {
      await t.scrollUntilVisible(
        f,
        300,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 30,
      );
      await pumpMs(400);
    } on Object {
      // reported below
    }
  }
  if (f.evaluate().isEmpty) {
    print('AUDIT: not found: $f');
    return false;
  }
  await t.ensureVisible(f.first);
  await pumpMs(300);
  await t.tap(f.first, warnIfMissed: false);
  await pumpMs(waitMs);
  return true;
}

Future<void> closeAll() async {
  navigatorKey.currentState!.popUntil((r) => r.isFirst);
  await pumpMs(900);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('protected file shots', (tester) async {
    t = tester;
    final backend = await eSetUp();
    installActionsFakes(backend);
    loadReminderHold = ({customerId, documentId}) async => false;
    pdfSharer = (bytes, name, {text}) async {};
    var sent = false;
    backend
      ..on(
        'GET',
        '/documents/:id/protection',
        (_) => FakeResponse(200, {
          'available': true,
          'customerId': 'cust-1',
          'customerAlwaysProtect': false,
          'sends': [
            if (sent)
              {
                'id': 'ps-1',
                'channel': 'LINK',
                'createdAt': DateTime.now().toUtc().toIso8601String(),
                'createdBy': 'u1',
                'recipient': null,
              },
          ],
        }),
      )
      ..on('POST', '/documents/:id/share-link', (r) {
        sent = r.body['protect'] == true;
        return const FakeResponse(201, {
          'url': 'https://invoice.test/d/tok123',
          'expiresAt': '2026-12-25T00:00:00Z',
        });
      })
      ..json('POST', '/documents/:id/protection/:sendId/reveal', {
        'password': 'K7M4Q9P2',
      })
      ..json('PUT', '/customers/:id/file-protection', {'always': true});

    await pumpAs(
      tester,
      backend,
      Preset.owner,
      const DocumentScreen(id: 'doc-1'),
    );
    await pumpMs(800);

    // 1 · S6 with the toggle (off by default).
    await tapIf(find.byTooltip('עוד'));
    await tapIf(find.text('שתף'));
    await shot('01-share-toggle-off');

    // 2 · on → the password card.
    await tapIf(find.byKey(const Key('s6-protect')));
    await shot('02-share-protected-card');

    // 3 · copy → "הועתק".
    await tapIf(find.byKey(const Key('file-password-copy')), waitMs: 300);
    await shot('03-password-copied');

    // 4 · "תמיד ללקוח הזה".
    await tapIf(find.byKey(const Key('s6-protect-always')));
    await shot('04-always-for-customer');

    // 5 · send (copy link) → the separate password message.
    await tapIf(find.byKey(const Key('s6-copy')), waitMs: 1500);
    await shot('05-after-send-password-message');
    await tapIf(find.byKey(const Key('password-done')));
    await closeAll();

    // 6 · the document page row.
    await pumpAs(
      tester,
      backend,
      Preset.owner,
      const DocumentScreen(id: 'doc-1', key: ValueKey('again')),
    );
    await pumpMs(800);
    final row = find.byKey(const Key('doc-protected'));
    if (row.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        row,
        300,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 30,
      );
    }
    await shot('06-document-protected-row');

    // 7 · "הצג סיסמה".
    await tapIf(row, waitMs: 1500);
    await shot('07-show-password-sheet');
    await closeAll();
  });
}
