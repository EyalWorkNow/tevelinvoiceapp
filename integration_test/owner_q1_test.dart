// Owner feedback Q1 (2026-11-16) on the simulator, against local staging
// (never prod). Real app, real text input (registerTestTextInput is false in
// integration tests: the iOS keyboard really opens when the simulator's
// hardware keyboard is disconnected).
//
//   U=<udid>; OUT=$PWD/docs/qa-2026-11-16/owner-feedback/q1
//   ~/flutter/bin/flutter test integration_test/owner_q1_test.dart -d $U \
//     --dart-define=API_BASE=http://127.0.0.1:3041 \
//     --dart-define=MAILDIR=$HOME/invoiceproject-staging-qa/outgoing-emails 2>&1 |
//   while IFS= read -r l; do echo "$l"; if [[ $l == *SHOT:* ]]; then
//     n=${l##*SHOT:}; xcrun simctl io $U screenshot "$OUT/$n.png" >/dev/null 2>&1; fi; done
//
// Writes on staging: the branding notes (restored at the end) and one draft
// (deleted at the end).
// ignore_for_file: avoid_print
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/compose/compose_state.dart';
import 'package:invoice/util/composer_config.dart';

import 'crash_sweep_test.dart' show t, pumpMs, waitFor;
import 'persona_screens_test.dart' as persona show startPlansGuard;
import 'persona_screens_test.dart' show plansGuardOn;
import 'v2_qa_gate_helpers.dart' show launchSignedInAs;

int _n = 0;
Future<void> shot(String name) async {
  await pumpMs(1500);
  _n++;
  print('SHOT:${_n.toString().padLeft(2, '0')}-$name');
  await pumpMs(2500); // the host takes the screenshot meanwhile
}

double insets() => t.view.viewInsets.bottom / t.view.devicePixelRatio;

bool editing(Finder field) => t
    .widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    )
    .focusNode
    .hasFocus;

Future<void> waitKeyboard(bool up) async {
  for (var i = 0; i < 40 && (insets() > 0) != up; i++) {
    await pumpMs(100);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  persona.startPlansGuard();

  testWidgets('owner Q1', (tester) async {
    t = tester;
    plansGuardOn = true;
    final api = await launchSignedInAs(tester, 'mobile-owner@tevel.test');
    final home = await waitFor(find.byKey(const Key('tab-home')), ms: 40000);
    if (!home) {
      await shot('no-home');
      print(
        'TEXTS ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).take(30).toList()}',
      );
    }
    expect(home, isTrue);
    await pumpMs(2000);
    final me = await api.get('/me');
    print('ME lineAgreedTotal=${me['lineAgreedTotal']}');
    final before =
        (await api.get('/settings/branding'))['branding']
            as Map<String, dynamic>;

    // ---- 3. document design -------------------------------------------
    await go('/business/branding');
    expect(
      await waitFor(find.byKey(const Key('branding-footer-note')), ms: 20000),
      isTrue,
    );
    await pumpMs(2500);
    ScrollPosition pos() => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const Key('branding-controls')),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    final tile = find.widgetWithText(SwitchListTile, 'הדגשת כותרת הטבלה');
    await tester.ensureVisible(tile);
    await pumpMs(800);
    final y0 = pos().pixels;
    final was = tester.widget<SwitchListTile>(tile).value;
    await shot('branding-before-switch');
    await tester.tap(tile);
    await pumpMs(2500);
    final y1 = pos().pixels;
    final now = tester.widget<SwitchListTile>(tile).value;
    print('CHECK switch: $was → $now, scroll $y0 → $y1');
    expect(now, !was);
    expect((y1 - y0).abs() < 1, isTrue);
    await shot('branding-after-switch');

    final footer = find.byKey(const Key('branding-footer-note'));
    await tester.ensureVisible(footer);
    await pumpMs(500);
    await tester.tap(footer);
    await waitKeyboard(true);
    var fakeKeyboard = false;
    if (insets() == 0) {
      // Hardware keyboard connected: the iOS keyboard stays down. Give the
      // view the keyboard's inset (336 pt) so the layout reacts the same.
      fakeKeyboard = true;
      tester.view.viewInsets = FakeViewPadding(
        bottom: 336 * tester.view.devicePixelRatio,
      );
      await pumpMs(800);
    }
    print('CHECK fakeKeyboard=$fakeKeyboard');
    print(
      'CHECK keyboard insets=${insets()} focus=${editing(footer)} '
      'scroll=${pos().pixels}',
    );
    expect(editing(footer), isTrue);
    await tester.enterText(footer, 'תודה שבחרתם בנו · Q1');
    await pumpMs(1500);
    expect(editing(footer), isTrue);
    await shot('branding-footer-typing-keyboard-up');

    final header = find.byKey(const Key('branding-header-note'));
    await tester.ensureVisible(header);
    await tester.tap(header);
    await pumpMs(800);
    expect(editing(header), isTrue);
    expect(editing(footer), isFalse);
    await tester.enterText(header, 'א׳–ה׳ 9:00–18:00');
    await pumpMs(1500);
    await shot('branding-header-typing');

    // ---- 1. tap outside closes the keyboard -----------------------------
    // The heading "לוגו העסק" area: plain text, no control.
    final plain = find.text(
      'העיצוב יחול על מסמכים חדשים. פרטי העסק, המספור '
      'והסכומים נשמרים בכל התבניות; מקור שכבר הופק אינו משתנה.',
    );
    await tester.ensureVisible(plain);
    await pumpMs(500);
    await tester.tap(plain, warnIfMissed: false);
    if (fakeKeyboard) {
      await pumpMs(500);
      tester.view.resetViewInsets();
    }
    await waitKeyboard(false);
    print(
      'CHECK after tap outside: insets=${insets()} '
      'focus=${editing(header)}',
    );
    expect(editing(header), isFalse);
    await shot('tap-outside-keyboard-closed');

    await tester.tap(find.byKey(const Key('editor-save')));
    await pumpMs(3000);
    final saved =
        (await api.get('/settings/branding'))['branding']
            as Map<String, dynamic>;
    print(
      'CHECK saved footer=${saved['footerNote']} header=${saved['headerNote']} '
      'accentTableHeader=${saved['accentTableHeader']}',
    );
    expect(saved['footerNote'], 'תודה שבחרתם בנו · Q1');
    expect(saved['headerNote'], 'א׳–ה׳ 9:00–18:00');
    expect(saved['accentTableHeader'], !was);
    await shot('branding-saved-preview');
    await tester.tap(find.byKey(const Key('branding-preview-full')));
    await pumpMs(3000);
    await shot('branding-full-preview');
    navigatorKey.currentState!.pop();
    await pumpMs(1000);

    // ---- 2. compose: type 2 → ₪2.00 -------------------------------------
    await go('/');
    await pumpMs(1000);
    unawaited(openCompose(navigatorKey.currentContext!, intent: 'PAID'));
    await pumpMs(3000);
    final resumeNew = find.byKey(const Key('resume-draft-new')).hitTestable();
    if (resumeNew.evaluate().isNotEmpty) {
      await tester.tap(resumeNew.first);
      await pumpMs(1000);
    }
    final walkIn = find.byKey(const Key('s2-walkin'));
    if (await waitFor(walkIn, ms: 4000)) {
      await tester.tap(walkIn.first, warnIfMissed: false);
      await pumpMs(1200);
    }
    for (final ch in ['2']) {
      final k = find.descendant(
        of: find.byWidgetPredicate((w) => w.runtimeType.toString() == 'Keypad'),
        matching: find.text(ch),
      );
      await tester.tap(k.first, warnIfMissed: false);
      await pumpMs(300);
    }
    await pumpMs(1000);
    final texts = find
        .byType(RichText)
        .evaluate()
        .map((e) => (e.widget as RichText).text.toPlainText())
        .where((s) => s.contains('₪'))
        .take(6)
        .toList();
    print('CHECK compose texts: $texts');
    await shot('compose-typed-2');

    // Server: the same lines the Composer sends total exactly ₪2.00.
    final s =
        ComposeState(
            kind: DocKind.taxInvoice,
            businessType: me['businessType'] as String? ?? 'OSEK_MURSHE',
            vatBasisPoints: 1800,
          )
          ..agreedTotals = me['lineAgreedTotal'] == true
          ..amountText = '2'
          ..description = 'Q1 בדיקה';
    final customers = await api.get('/customers?limit=1');
    final list = (customers['customers'] ?? customers['items']) as List;
    final draft = await api.post('/documents', {
      ...s.requestBody(),
      'customerId': (list.first as Map)['id'],
    });
    final id = draft['id'] ?? draft['documentId'];
    final doc = await api.get('/documents/$id');
    print(
      'CHECK server draft total=${doc['totalMinor'] ?? doc['total_minor']} '
      'lines=${doc['lines']}',
    );
    print('DRAFT $id (delete: DELETE /documents/$id)');

    // Restore the branding notes.
    await api.put('/settings/branding', {
      for (final k in ['template', 'fontFamily', 'logoSize', 'accentColor'])
        k: saved[k],
      'headerNote': before['headerNote'],
      'footerNote': before['footerNote'],
      'accentTableHeader': before['accentTableHeader'],
    });
  }, timeout: const Timeout(Duration(minutes: 15)));
}
