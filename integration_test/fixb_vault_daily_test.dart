// FIXB walkthrough (tester 2026-11-18) on the simulator against a local API
// from feat/fixb-2026-11-18: reports → "סיכום יום" with real numbers, then
// "המסמכים של העסק": upload two documents (PDF + photo; the native pickers are
// replaced by in-memory files, everything else is the real UI + API), set an
// expiry date, and send one through the share sheet. SHOT: markers as in
// sign_requests_walkthrough_test.dart:
//
//   ~/flutter/bin/flutter test integration_test/fixb_vault_daily_test.dart -d $U \
//     --dart-define=API_BASE=http://127.0.0.1:3077 --dart-define=DEVICE_TOKEN=inv_… \
//     --dart-define=BUSINESS_ID=… 2>&1 | while IFS= read -r l; do echo "$l";
//     if [[ $l == *SHOT:* ]]; then xcrun simctl io $U screenshot "$OUT/${l##*SHOT:}.png"; fi; done
// ignore_for_file: avoid_print, use_build_context_synchronously
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/api/reports_api.dart' show dailySummaryKind;
import 'package:invoice/app_shell.dart' show AppTab;
import 'package:invoice/main.dart' as app;
import 'package:invoice/router.dart';
import 'package:invoice/screens/business/vault_screen.dart';

import 'crash_sweep_test.dart' show t, pumpMs, waitFor;
import 'v2_qa_gate_helpers.dart' show keychain, resetDevice;

const _token = String.fromEnvironment('DEVICE_TOKEN');
const _business = String.fromEnvironment('BUSINESS_ID');

Future<void> _shot(String name) async {
  await pumpMs(2500);
  print('SHOT:fixb-$name');
  await pumpMs(1200);
}

BuildContext get _ctx => navigatorKey.currentContext!;

final Uint8List _pdf = Uint8List.fromList(
  utf8.encode(
    '%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n'
    '2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n'
    '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 595 842]>>endobj\n'
    'trailer<</Root 1 0 R>>\n%%EOF\n',
  ),
);

Future<void> _tap(Finder f, {int ms = 900}) async {
  if (await waitFor(f.hitTestable(), ms: 6000)) {
    await t.tap(f.hitTestable().first, warnIfMissed: false);
    await pumpMs(ms);
  } else {
    print('MISSING: $f');
  }
}

Future<void> _upload(
  VaultFile file,
  String categoryLabel,
  String title, {
  bool expiry = false,
  String? shot,
}) async {
  pickVaultFile = (_) async => file;
  if (find.byKey(const Key('vault-bottom')).evaluate().isNotEmpty) {
    await _tap(find.byKey(const Key('vault-bottom')));
  } else {
    // Empty vault: the EmptyState's own button.
    await _tap(find.text('הוספת מסמך'));
  }
  await _tap(find.byKey(const Key('vault-source-pdf')));
  await pumpMs(1200);
  await _tap(find.byKey(const Key('vault-category')));
  await _tap(find.text(categoryLabel).last);
  await t.enterText(find.byKey(const Key('vault-title')), title);
  await pumpMs(500);
  FocusManager.instance.primaryFocus?.unfocus();
  await pumpMs(500);
  if (expiry) {
    await _tap(find.byKey(const Key('vault-expires')));
    await pumpMs(1200);
    await _tap(find.text('אישור').last, ms: 1200);
    await _tap(find.text('14 ימים לפני'));
  }
  if (shot != null) await _shot(shot);
  await _tap(find.byKey(const Key('vault-save')), ms: 4000);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FIXB: daily summary + business documents', (tester) async {
    t = tester;
    await resetDevice();
    await keychain.write(key: 'device_token', value: _token);
    await keychain.write(key: 'business_id', value: _business);
    app.main();
    await waitFor(find.byKey(const Key('tab-home')), ms: 40000);
    await pumpMs(3000);

    // 1. Reports → "סיכום יום".
    unawaited(openReports(_ctx));
    await pumpMs(4000);
    await _shot('1-reports');
    unawaited(openReport(_ctx, dailySummaryKind));
    await pumpMs(4000);
    await _shot('2-daily-summary');
    final list = find.byType(Scrollable);
    if (list.evaluate().isNotEmpty) {
      await tester.drag(list.first, const Offset(0, -500));
      await pumpMs(1200);
      await _shot('3-daily-summary-receipts');
    }
    Navigator.of(_ctx).popUntil((r) => r.isFirst);
    await pumpMs(1500);

    // 2. ניהול → "המסמכים של העסק".
    selectTab(AppTab.business);
    await pumpMs(3000);
    await _shot('4-business-tab');
    unawaited(openBusinessSection(_ctx, BusinessSection.vault));
    await pumpMs(3500);
    await _shot('5-vault-empty');

    final png = (await rootBundle.load(
      'assets/brand/tevel_logo.png',
    )).buffer.asUint8List();
    await _upload(
      VaultFile(_pdf, 'application/pdf', 'withholding.pdf'),
      'אישור ניכוי במקור',
      'אישור ניכוי במקור 2026',
      expiry: true,
      shot: '6-details-expiry',
    );
    await _shot('7-vault-one');
    await _upload(
      VaultFile(png, 'image/png', 'bookkeeping.png'),
      'אישור ניהול ספרים',
      'אישור ניהול ספרים 2026',
    );
    await _shot('8-vault-two');

    // 3. Send both to a customer: select → send → the iOS share sheet.
    await _tap(find.byKey(const Key('vault-select')));
    for (final row
        in find
            .byWidgetPredicate(
              (w) =>
                  w.key is ValueKey<String> &&
                  (w.key! as ValueKey<String>).value.startsWith('vault-row-'),
            )
            .evaluate()
            .toList()) {
      await tester.tap(find.byWidget(row.widget), warnIfMissed: false);
      await pumpMs(500);
    }
    await _shot('9-vault-selected');
    await _tap(find.byKey(const Key('vault-bottom')), ms: 5000);
    await _shot('10-share-sheet');
  });
}
