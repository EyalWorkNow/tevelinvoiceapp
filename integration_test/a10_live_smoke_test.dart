// A10 live smoke (QA 2026-11-12, report 07 paths). Not an assertion suite:
// it drives the real app to each checkpoint, prints `CHECKPOINT <name>` and
// holds the frame while the host takes `xcrun simctl io booted screenshot`.
// Nothing is issued: the composer is left before the primary is pressed.
//
//   flutter test integration_test/a10_live_smoke_test.dart -d <sim> \
//     --dart-define=API_BASE=http://127.0.0.1:3031 --dart-define=MAILDIR=...

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/router.dart';
import 'package:invoice/ui/widgets/keypad.dart';

import 'v2_qa_people_helpers.dart';
import 'qa_plans_guard.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  dismissPlansDuringTests();
  final notes = <String>[];

  Future<void> shot(WidgetTester tester, String name) async {
    await pumpFor(tester, const Duration(milliseconds: 900));
    debugPrint('CHECKPOINT $name');
    await pumpFor(tester, const Duration(seconds: 4));
  }

  void note(String s) {
    notes.add(s);
    debugPrint('SMOKE $s');
  }

  bool has(Finder f) => f.evaluate().isNotEmpty;

  testWidgets('A10 live smoke', (tester) async {
    final owner = await signInApi(ownerEmail);
    final staff = await signInApi(staffEmail);

    // Fixtures already on the dev server (from earlier E2E runs): a customer
    // that owes, a sent open invoice, a draft.
    final docs = DevApi.expectOk(
      await owner.get('/documents', {'limit': '300'}),
    ).list('documents');
    Map<String, dynamic>? pick(bool Function(Map<String, dynamic>) ok) {
      for (final d in docs.cast<Map<String, dynamic>>()) {
        if (ok(d)) return d;
      }
      return null;
    }

    final sentOpen = pick(
      (d) =>
          d['status'] != 'DRAFT' &&
          d['sentAt'] != null &&
          (BigInt.tryParse('${d['openMinor'] ?? 0}') ?? BigInt.zero) >
              BigInt.zero,
    );
    if (docs.isNotEmpty) {
      note(
        'doc sample keys: ${(docs.first as Map).keys.join(',')} status=${(docs.first as Map)['status']}',
      );
    }
    final draft = pick((d) => d['status'] == 'DRAFT');
    final debtor = sentOpen?['customerId'] as String?;
    note('sentOpen=${sentOpen?['id']} draft=${draft?['id']} debtor=$debtor');

    // ---- 1. home (owner) -------------------------------------------------
    await launchAppAs(tester, owner);
    await pumpFor(tester, const Duration(seconds: 3));
    note(
      'home business name: ${has(find.byKey(const Key('home-business-name')))}',
    );
    note('052-0000111 anywhere: ${has(find.textContaining('0000111'))}');
    await shot(tester, '01-home-owner');
    await pumpUntilScrolled(tester, find.text('מסמכים אחרונים'));
    await shot(tester, '02-home-scrolled-bottom-bar');

    // ---- 2. composer: ＋ → S2 → walk-in → amount with agorot -------------
    await tapSafe(tester, find.byKey(const Key('tab-create')));
    await pumpFor(tester, const Duration(seconds: 2));
    note('S2 052-0000111: ${has(find.textContaining('0000111'))}');
    await shot(tester, '03-compose-s2');
    final walkin = find.byKey(const Key('s2-walkin'));
    if (has(walkin)) {
      await tapSafe(tester, walkin);
    } else {
      final recent = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('s2-recent-'),
      );
      if (has(recent)) await tapSafe(tester, recent);
    }
    await pumpFor(tester, const Duration(seconds: 2));
    final keypad = find.byType(Keypad);
    note('keypad shown: ${has(keypad)}');
    Future<void> key(String k) async {
      final f = find.descendant(of: keypad, matching: find.text(k));
      if (has(f)) {
        await tester.tap(f.first);
        await tester.pump(const Duration(milliseconds: 120));
      } else {
        note('key "$k" missing');
      }
    }

    await shot(tester, '04-amount-empty');
    await key('1');
    await shot(tester, '05-amount-1');
    await key('2');
    await key('0');
    await shot(tester, '06-amount-120');
    await key('.');
    await key('5');
    await key('0');
    note(
      'decimal key present: ${has(find.descendant(of: keypad, matching: find.text('.')))}',
    );
    await shot(tester, '07-amount-120.50-vat-line');
    await tapSafe(tester, find.byKey(const Key('compose-close')));
    await pumpFor(tester, const Duration(seconds: 1));
    await shot(tester, '08-compose-close-dialog');
    final discard = find.byKey(const Key('save-draft-discard'));
    if (has(discard)) await tapSafe(tester, discard);
    await pumpFor(tester, const Duration(seconds: 2));
    note('composer left: ${!has(find.byKey(const Key('compose-close')))}');
    await shot(tester, '09-after-compose-close');

    // ---- 3. customer card ------------------------------------------------
    if (debtor != null) {
      atRoot((c) => openPerson(c, debtor));
      await pumpFor(tester, const Duration(seconds: 3));
      note(
        'card new-invoice: ${has(find.byKey(const Key('person-new-invoice')))} '
        'paid: ${has(find.byKey(const Key('person-paid')))}',
      );
      await shot(tester, '10-customer-card');
      await pumpUntilScrolled(tester, find.byKey(const Key('person-owes')));
      await shot(tester, '11-customer-card-owes');
      navigatorKey.currentState!.popUntil((r) => r.isFirst);
      await pumpFor(tester, const Duration(seconds: 1));
    }

    // ---- 4. document by status ---------------------------------------------
    if (sentOpen != null) {
      atRoot((c) => openDocument(c, sentOpen['id'] as String));
      await pumpFor(tester, const Duration(seconds: 4));
      await shot(tester, '12-doc-sent-open');
      navigatorKey.currentState!.popUntil((r) => r.isFirst);
      await pumpFor(tester, const Duration(seconds: 1));
    }
    if (draft != null) {
      atRoot((c) => openDocument(c, draft['id'] as String));
      await pumpFor(tester, const Duration(seconds: 4));
      await shot(tester, '13-doc-draft');
      navigatorKey.currentState!.popUntil((r) => r.isFirst);
      await pumpFor(tester, const Duration(seconds: 1));
    }

    // ---- 5. management, people, profile (owner) ---------------------------
    await tapSafe(tester, find.byKey(const Key('tab-business')));
    await pumpFor(tester, const Duration(seconds: 2));
    await shot(tester, '14-management-top');
    await pumpUntilScrolled(tester, find.byKey(const Key('brow-account')));
    await shot(tester, '15-management-bottom');
    openPeople();
    await pumpFor(tester, const Duration(seconds: 2));
    await pumpUntilScrolled(tester, find.byKey(const Key('people-list')));
    final list = find.byKey(const Key('people-list'));
    if (has(list)) {
      await tester.fling(list, const Offset(0, -20000), 4000);
      await pumpFor(tester, const Duration(seconds: 2));
    }
    await shot(tester, '16-people-list-end');
    await tapSafe(tester, find.byKey(const Key('tab-profile')));
    await pumpFor(tester, const Duration(seconds: 2));
    await shot(tester, '17-profile-owner');
    await closeApp(tester);

    // ---- 6. profile + home as עובד ----------------------------------------
    await launchAppAs(tester, staff);
    await pumpFor(tester, const Duration(seconds: 3));
    await shot(tester, '18-home-staff');
    await tapSafe(tester, find.byKey(const Key('tab-profile')));
    await pumpFor(tester, const Duration(seconds: 2));
    await shot(tester, '19-profile-staff');
    await closeApp(tester);
    debugPrint('SMOKE SUMMARY\n${notes.join('\n')}');
  });
}
