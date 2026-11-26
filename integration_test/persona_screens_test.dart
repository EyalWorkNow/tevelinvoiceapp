// QA 2026-11-16 · persona review: a COMPLETE visual record of the app.
//
// Prints `SHOT:<role>/<NN-area-state>` while holding a frame (same protocol as
// v2_qa_screens_test.dart), so the runner loop below takes the screenshot.
// Also prints `NOTE:<shot>: …` (what the step saw / why it is missing),
// `UI-ERROR [<shot>] …` (framework errors such as overflow) and
// `LATIN:<shot>: …` (Latin-script words on screen) for the INDEX.
//
// PART=owner | signedout | roles  (one part per run). signedout runs with fake
// Supabase defines so the production (Supabase) recovery / invite UI shows;
// the Supabase calls are answered locally, the Tevel API is the staging one.
//
//   U=EF82558D-7B24-4BDD-8B96-DA66170CF700; OUT=docs/qa-2026-11-16/screens
//   ~/flutter/bin/flutter test integration_test/persona_screens_test.dart -d $U \
//     --dart-define=API_BASE=http://127.0.0.1:3041 \
//     --dart-define=MAILDIR=$HOME/invoiceproject-staging-qa/outgoing-emails \
//     --dart-define=PART=owner 2>&1 |
//   while IFS= read -r l; do echo "$l"; if [[ $l == *SHOT:* ]]; then
//     n=${l##*SHOT:}; mkdir -p "$OUT/$(dirname $n)";
//     xcrun simctl io $U screenshot "$OUT/$n.png" >/dev/null 2>&1; fi; done
//   (signedout adds --dart-define=SUPABASE_AUTH_URL=https://qafake.supabase.co
//    --dart-define=SUPABASE_AUTH_PUBLISHABLE_KEY=sb_publishable_qafake)
//
// It writes on staging only what a reviewer would: one small receipt (the
// issue success state), one expense upload, one CRM note. Nothing is sent.
// ignore_for_file: avoid_print, use_build_context_synchronously
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/api/inbox_api.dart';
import 'package:invoice/app_shell.dart' show AppTab;
import 'package:invoice/router.dart' hide selectTab;
import 'package:invoice/screens/auth/login_screen.dart';
import 'package:invoice/screens/auth/mfa_sheet.dart';
import 'package:invoice/screens/billing/billing_screen.dart';
import 'package:invoice/screens/business/sheets/s14_switch.dart';
import 'package:invoice/screens/document/sheets/s5_payment.dart';
import 'package:invoice/screens/document/sheets/s6_share.dart';
import 'package:invoice/screens/document/sheets/s8_cancel.dart';
import 'package:invoice/screens/home/inbox_cards.dart';
import 'package:invoice/state/business_context.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/session.dart';
import 'package:invoice/ui/widgets/keypad.dart';
import 'package:invoice/ui/widgets/safe_error_card.dart';
import 'package:invoice/util/allowed_urls.dart' show urlOpener;
import 'package:invoice/util/payment_reminder.dart' show ReminderLog;

import 'crash_sweep_test.dart'
    show
        t,
        pumpMs,
        waitFor,
        tapIf,
        back,
        systemBack,
        toRoot,
        selectTab,
        leaveIfAsked,
        topRoute,
        validTaxId;
import 'v2_qa_gate_helpers.dart'
    show

        DevSession,
        devSignIn,
        devInvite,
        devRevokeInvitation,
        launchSignedInAs,
        launchSignedOut,
        waitForMfaCode,
        devBusinessId,
        devPassword,
        ownerEmail;
import 'v2_qa_people_helpers.dart' show mockCamera, unmockCamera, uniqueJpeg;

const part = String.fromEnvironment('PART', defaultValue: 'owner');
/// Owner part only: start at this section (token sign-in, no auth shots)
/// and number the shots from START (to append to an earlier run).
const from = String.fromEnvironment('FROM');
const startNo = int.fromEnvironment('START', defaultValue: 0);
const paturBusiness = 'c934a7a8-df74-433d-a5e2-e342c16142b1';
const owner = 'mobile-owner@tevel.test';

// ---- shots ----------------------------------------------------------------------

String role = 'owner';
int shotNo = 0;
String lastShot = 'start';

Future<void> shot(String name, {int settleMs = 2200}) async {
  await pumpMs(settleMs);
  shotNo++;
  final id = '$role/${shotNo.toString().padLeft(2, '0')}-$name';
  lastShot = id;
  final texts = visibleTexts();
  final latin = texts
      .expand((s) => RegExp(r'[A-Za-z][A-Za-z_]{2,}').allMatches(s))
      .map((m) => m.group(0)!)
      .where((w) => !const {'Apple', 'Pay', 'Google', 'PDF', 'Face', 'Bit',
            'WhatsApp', 'SMS', 'mail', 'tevel', 'Tevel', 'iPhone', 'Excel',
            'CSV', 'Cardcom', 'QR', 'Gmail', 'com', 'test', 'mobile',
            'owner', 'www', 'https', 'http', 'ID'}.contains(w))
      .toSet();
  print('SHOT:$id');
  if (latin.isNotEmpty) print('LATIN:$id: ${latin.join(' ')}');
  print('TEXTS:$id: ${texts.take(45).join(' | ')}');
  await pumpMs(3800);
}

void noteFor(String what) => print('NOTE:$lastShot: $what');
void miss(String what) => print('MISS:$role: $what');

List<String> visibleTexts() {
  final out = <String>[];
  for (final e in find.byType(Text).hitTestable().evaluate()) {
    final w = e.widget as Text;
    final s = w.data ?? w.textSpan?.toPlainText();
    if (s != null && s.trim().isNotEmpty) out.add(s.replaceAll('\n', ' '));
  }
  for (final e in find.byType(RichText).hitTestable().evaluate()) {
    final s = (e.widget as RichText).text.toPlainText();
    if (s.trim().isNotEmpty && !out.contains(s)) out.add(s.replaceAll('\n', ' '));
  }
  return out;
}

/// Scrolls the biggest visible vertical list by [dy]; false when it did not move.
Future<bool> scrollDown({double dy = 520}) async {
  final lists = find
      .byWidgetPredicate(
        (w) =>
            w is Scrollable &&
            axisDirectionToAxis(w.axisDirection) == Axis.vertical,
      )
      .hitTestable()
      .evaluate()
      .toList();
  if (lists.isEmpty) return false;
  Element? best;
  var bestArea = 0.0;
  for (final e in lists) {
    final box = e.renderObject;
    if (box is RenderBox && box.hasSize) {
      final a = box.size.width * box.size.height;
      if (a > bestArea) {
        bestArea = a;
        best = e;
      }
    }
  }
  if (best == null) return false;
  final state = (best as StatefulElement).state as ScrollableState;
  final before = state.position.pixels;
  if (state.position.maxScrollExtent - before < 40) return false;
  await t.dragFrom(
    (best.renderObject! as RenderBox).localToGlobal(
      (best.renderObject! as RenderBox).size.center(Offset.zero),
    ),
    Offset(0, -dy),
  );
  await pumpMs(700);
  return (state.position.pixels - before).abs() > 30;
}

/// Shot + every further screenful (at most [pages]).
Future<void> shotScroll(String name, {int pages = 3}) async {
  await shot(name);
  for (var i = 2; i <= pages; i++) {
    if (!await scrollDown()) break;
    await shot('$name-p$i', settleMs: 600);
  }
}

BuildContext get ctx => navigatorKey.currentContext!;

/// Back to the shell root, forcing past sheets / dialogs that ask first.
Future<void> hardRoot() async {
  await toRoot();
  final nav = navigatorKey.currentState;
  if (nav != null) nav.popUntil((r) => r.isFirst);
  await pumpMs(500);
}

/// Scrolls the biggest list back to its top.
Future<void> scrollTop() async {
  for (var i = 0; i < 6; i++) {
    final lists = find
        .byWidgetPredicate(
          (w) =>
              w is Scrollable &&
              axisDirectionToAxis(w.axisDirection) == Axis.vertical,
        )
        .hitTestable();
    if (lists.evaluate().isEmpty) return;
    await t.drag(lists.first, const Offset(0, 900), warnIfMissed: false);
    await pumpMs(250);
  }
  await pumpMs(500);
}

Future<void> guarded(String label, Future<void> Function() body) async {
  try {
    await body();
  } on Object catch (e, st) {
    print(
      'STEP-FAILED:$role: $label: $e ${st.toString().split('\n').take(3).join(' | ')}',
    );
  }
  await pumpMs(200);
}

Finder keyPrefix(String prefix, {RegExp? matching}) => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith(prefix) &&
      (matching == null ||
          matching.hasMatch((w.key! as ValueKey<String>).value)),
);

List<String> keysWithPrefix(String prefix) => keyPrefix(prefix)
    .evaluate()
    .map((e) => (e.widget.key! as ValueKey<String>).value)
    .toSet()
    .toList();

Future<void> typeKeypad(String text) async {
  for (final ch in text.split('')) {
    final k = find.descendant(of: find.byType(Keypad), matching: find.text(ch));
    if (k.evaluate().isEmpty) {
      noteFor('keypad has no "$ch"');
      continue;
    }
    await t.tap(k.first, warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 90));
  }
  await pumpMs(500);
}

Future<void> closeSheetOrDialog() async {
  if (topRoute is PopupRoute) {
    await systemBack();
  }
}

// ---- plans guard with a pause (qa_plans_guard.dart cannot be paused) --------------

bool plansGuardOn = false;
Timer? _plansTimer;
final _closed = Expando<bool>();

void startPlansGuard() {
  _plansTimer ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
    if (WidgetsBinding.instance.rootElement == null) return;
    final nav = navigatorKey.currentState;
    if (nav != null) {
      nav.popUntil((r) => r.settings.name != '/demo/customer-payment');
    }
    if (!plansGuardOn) return;
    for (final el in find.byType(PlansSheet).evaluate().toList()) {
      if (!el.mounted || _closed[el] == true) continue;
      final sheet = el.widget as PlansSheet;
      if (sheet.requiredForAccess) {
        _closed[el] = true;
        sheet.onExit?.call();
      } else if (ModalRoute.of(el)?.isCurrent ?? false) {
        _closed[el] = true;
        Navigator.of(el).pop();
      }
    }
  });
}

// ---- HTTP fakes --------------------------------------------------------------------

/// Offline: every request fails like a dropped connection.
class OfflineClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future.error(const SocketException('QA offline'));
}

/// 500 for paths matching [pattern]; the rest goes to [inner].
class FailingClient extends http.BaseClient {
  FailingClient(this.inner, this.pattern);
  final http.Client inner;
  final RegExp pattern;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (pattern.hasMatch(request.url.path)) {
      return Future.value(
        http.StreamedResponse(
          Stream.value(utf8.encode('{"error":"INTERNAL","message":"qa"}')),
          500,
          headers: {'content-type': 'application/json'},
        ),
      );
    }
    return inner.send(request);
  }
}

/// Answers the Supabase Auth calls locally (signedout part only).
class FakeSupabase extends http.BaseClient {
  FakeSupabase(this.inner);
  final http.Client inner;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!request.url.host.endsWith('supabase.co')) return inner.send(request);
    final p = request.url.path;
    var status = 200;
    Object body = const {};
    if (p == '/auth/v1/token') {
      status = 400;
      body = {'error_code': 'invalid_credentials'};
    } else if (p == '/auth/v1/verify') {
      body = {'access_token': 'qa-fake-access-token', 'token_type': 'bearer'};
    } else if (p == '/auth/v1/signup') {
      body = {
        'user': {'id': 'qa-fake-user', 'identities': [{}]},
      };
    }
    print('NOTE:$lastShot: fake Supabase ${request.method} $p → $status');
    return Future.value(
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        headers: {'content-type': 'application/json'},
      ),
    );
  }
}

// ---- data lookups ---------------------------------------------------------------

Future<List<Map<String, dynamic>>> listOf(String path, String key) async {
  try {
    final json = await ApiClient.instance.get(path);
    return [
      for (final r in (json[key] as List? ?? const []))
        r as Map<String, dynamic>,
    ];
  } on Object catch (e) {
    miss('$path failed: $e');
    return const [];
  }
}

BigInt big(Object? v) => BigInt.tryParse('${v ?? 0}') ?? BigInt.zero;

// ---- error capture --------------------------------------------------------------

Future<void> runCaptured(WidgetTester tester, Future<void> Function() body) async {
  t = tester;
  final originalOnError = FlutterError.onError;
  final originalPlatformOnError = PlatformDispatcher.instance.onError;
  final seen = <String>{};
  FlutterError.onError = (d) {
    final first = d.exceptionAsString().split('\n').first;
    if (seen.add('$lastShot $first')) {
      final where = d
          .toString()
          .split('\n')
          .where((l) => l.contains('file:///') && l.contains('/lib/'))
          .take(2)
          .join(' ');
      print('UI-ERROR [$lastShot] $first $where');
    }
  };
  PlatformDispatcher.instance.onError = (e, st) {
    print('ASYNC-ERROR [$lastShot] $e');
    return true;
  };
  final done = Completer<void>();
  runZonedGuarded(
    () async {
      try {
        await body();
      } on Object catch (e, st) {
        print('PART-ABORTED [$lastShot] $e\n$st');
      } finally {
        done.complete();
      }
    },
    (e, st) => print(
      'ASYNC-ERROR [$lastShot] $e ${st.toString().split('\n').take(2).join(' | ')}',
    ),
  );
  await done.future;
  await pumpMs(1000);
  FlutterError.onError = originalOnError;
  PlatformDispatcher.instance.onError = originalPlatformOnError;
}

final List<String> externalOpens = [];

// ---- OWNER --------------------------------------------------------------------------

Future<void> ownerLoginThroughUi() async {
  await launchSignedOut(t);
  await pumpMs(1500);
  await shot('auth-login-empty');
  await t.enterText(find.byType(TextField).at(0), owner);
  await t.enterText(find.byType(TextField).at(1), devPassword);
  FocusManager.instance.primaryFocus?.unfocus();
  await pumpMs(300);
  await shot('auth-login-filled');
  final since = DateTime.now().subtract(const Duration(seconds: 2));
  await t.tap(find.text('כניסה').hitTestable().first);
  var mfaDone = false, gateShot = false, switchShot = false;
  final end = DateTime.now().add(const Duration(seconds: 120));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 200));
    if (find.byKey(const Key('tab-home')).hitTestable().evaluate().isNotEmpty) {
      break;
    }
    final boxes = find.descendant(
      of: find.byType(CodeBoxes),
      matching: find.byType(TextField),
    );
    if (!mfaDone && boxes.evaluate().isNotEmpty) {
      await shot('auth-mfa-code-sent');
      await waitForMfaCode(owner, since);
      await t.enterText(boxes, '000000');
      await shot('auth-mfa-wrong-code');
      final since2 = DateTime.now().subtract(const Duration(seconds: 1));
      // A wrong code ends that code; a new one may be sent once a minute.
      String? code;
      for (var attempt = 0; attempt < 6 && code == null; attempt++) {
        final resend = find.text('שלח קוד חדש').hitTestable();
        if (resend.evaluate().isNotEmpty) {
          await t.tap(resend.first);
          await pumpMs(800);
        }
        final end2 = DateTime.now().add(const Duration(seconds: 15));
        while (code == null && DateTime.now().isBefore(end2)) {
          await pumpMs(500);
          try {
            code = await waitForMfaCode(
              owner,
              since2,
              timeout: const Duration(milliseconds: 300),
            );
          } on Object {
            code = null;
          }
        }
      }
      if (code == null) throw StateError('no new MFA code after resend');
      noteFor('MFA: correct code entered after "שלח קוד חדש"');
      final boxes2 = find.descendant(
        of: find.byType(CodeBoxes),
        matching: find.byType(TextField),
      );
      await t.enterText(boxes2, code);
      mfaDone = true;
      continue;
    }
    if (!switchShot && find.byType(SwitchBusinessSheet).evaluate().isNotEmpty) {
      switchShot = true;
      await shot('auth-pick-business-at-login');
      final row = find.byKey(const Key('s14-$devBusinessId'));
      if (row.evaluate().isNotEmpty) {
        await t.tap(row, warnIfMissed: false);
      }
      continue;
    }
    final plans = find.byType(PlansSheet);
    if (!gateShot && plans.evaluate().isNotEmpty) {
      gateShot = true;
      await shot('gate-subscription-required');
      if (await scrollDown()) await shot('gate-subscription-required-p2');
      plansGuardOn = true;
    }
  }
  plansGuardOn = true;
  await pumpMs(3000);
  if (find.byKey(const Key('tab-home')).evaluate().isEmpty) {
    noteFor('UI sign-in did not reach home; restoring a device token instead');
    await launchSignedInAs(t, owner);
    await waitFor(find.byKey(const Key('tab-home')), ms: 40000);
    await pumpMs(3000);
  }
}

Future<void> ownerHome() async {
  await selectTab(AppTab.home);
  await pumpMs(2500);
  await shotScroll('home', pages: 4);
  await hardRoot();
  await selectTab(AppTab.home);
  for (final k in keysWithPrefix('inbox-')) {
    await guarded('inbox card $k', () async {
      await selectTab(AppTab.home);
      if (!await tapIf(find.byKey(Key(k)), waitMs: 1500)) return;
      await shot('home-inbox-card-${k.substring(6)}');
      await closeSheetOrDialog();
      await hardRoot();
    });
  }
  for (final (k, n) in [
    ('home-inbox-summary', 'home-inbox-summary'),
    ('home-money', 'home-money-card'),
    ('home-all-activity', 'activity-all'),
    ('home-switch-business', 'switch-business-sheet-from-home'),
  ]) {
    await guarded(k, () async {
      await selectTab(AppTab.home);
      if (!await tapIf(find.byKey(Key(k)), waitMs: 2000)) {
        miss('home: $k not on screen');
        return;
      }
      await shotScroll(n, pages: 2);
      await closeSheetOrDialog();
      await hardRoot();
    });
  }
  await guarded('activity chips', () async {
    for (final chip in ['unpaid', 'drafts', 'quotes', 'inbox']) {
      unawaited(openActivity(ctx, chip: chip));
      await shot('activity-chip-$chip');
      await hardRoot();
    }
    unawaited(openActivity(ctx));
    await pumpMs(1500);
    final search = find.byKey(const Key('activity-search'));
    if (await tapIf(search, waitMs: 1500)) {
      await pumpMs(400);
      final field = find.descendant(
        of: find.byKey(const Key('activity-search')),
        matching: find.byType(TextField),
      );
      final f = field.evaluate().isNotEmpty ? field : find.byType(TextField);
      if (f.evaluate().isNotEmpty) {
        await t.enterText(f.first, 'תבל');
        await shot('activity-search-typed');
      }
    }
    await hardRoot();
  });
  await guarded('recent search', () async {
    await selectTab(AppTab.home);
    if (await tapIf(find.byKey(const Key('home-recent-search')), waitMs: 1500)) {
      await pumpMs(400);
      final f = find.byKey(const Key('home-recent-search-field'));
      if (f.evaluate().isNotEmpty) {
        await t.enterText(f, 'א');
      }
      await shot('home-recent-search');
    }
    await hardRoot();
  });
}

Future<void> ownerBottomBarCreate() async {
  await guarded('tab-create', () async {
    await selectTab(AppTab.home);
    await tapIf(find.byKey(const Key('tab-create')));
    await shot('create-tab-first-screen');
    await closeSheetOrDialog();
    await hardRoot();
  });
}

Future<void> openWalkInCompose(String intent) async {
  unawaited(openCompose(ctx, intent: intent));
  await pumpMs(1800);
  await resumeNewIfAsked();
  final walkIn = find.byKey(const Key('s2-walkin'));
  if (await waitFor(walkIn, ms: 4000)) {
    await t.tap(walkIn.first, warnIfMissed: false);
    await pumpMs(1200);
  }
}

Future<void> resumeNewIfAsked() async {
  final resumeNew = find.byKey(const Key('resume-draft-new')).hitTestable();
  if (resumeNew.evaluate().isNotEmpty) {
    await shot('compose-resume-draft-dialog');
    await t.tap(resumeNew.first);
    await pumpMs(600);
  }
}

Future<void> closeComposeDiscard() async {
  await tapIf(find.byKey(const Key('compose-close')), waitMs: 1500);
  await pumpMs(600);
  await leaveIfAsked();
  await hardRoot();
}

Future<void> ownerCompose(Random rnd) async {
  // Customer picker → new customer form (+ validation).
  await guarded('compose picker', () async {
    unawaited(openCompose(ctx, intent: 'PAID'));
    await pumpMs(1800);
    await resumeNewIfAsked();
    await shotScroll('compose-customer-picker', pages: 2);
    final search = find.byKey(const Key('s2-search'));
    if (search.evaluate().isNotEmpty) {
      await t.enterText(search.first, 'מש');
      await shot('compose-customer-picker-search');
      await t.enterText(search.first, 'zzzzקקק');
      await shot('compose-customer-picker-no-results');
      await t.enterText(search.first, '');
      await pumpMs(500);
    }
    if (await tapIf(find.byKey(const Key('s2-new')), what: 's2-new')) {
      await pumpMs(800);
      await shot('compose-new-customer-form');
      final save = find.byKey(const Key('s2-save'));
      if (save.evaluate().isNotEmpty) {
        await t.ensureVisible(save);
        await pumpMs(200);
        await t.tap(save, warnIfMissed: false);
        await shot('compose-new-customer-error-empty');
      }
      final name = find.byKey(const Key('s2-name'));
      if (name.evaluate().isNotEmpty) {
        await t.enterText(name, 'לקוח בדיקה');
        await t.enterText(find.byKey(const Key('s2-phone')), '05012');
        await t.enterText(find.byKey(const Key('s2-taxid')), '123456789');
        FocusManager.instance.primaryFocus?.unfocus();
        await pumpMs(300);
        if (save.evaluate().isNotEmpty) {
          await t.ensureVisible(save);
          await t.tap(save, warnIfMissed: false);
        }
        await shot('compose-new-customer-error-bad-phone-taxid');
        if (await scrollDown()) await shot('compose-new-customer-form-p2');
      }
      await back();
      await pumpMs(500);
      if (find.byKey(const Key('discard-leave')).hitTestable().evaluate().isNotEmpty) {
        await shot('compose-new-customer-discard-dialog');
        final keep = find.text('המשך עריכה').hitTestable();
        if (keep.evaluate().isNotEmpty) {
          await t.tap(keep.first);
        } else {
          await systemBack();
        }
        await pumpMs(600);
      }
      // A valid business customer (ח.פ.) → saved → back in the Composer with
      // it: the allocation hint shows above ₪5,000 before VAT.
      if (name.evaluate().isNotEmpty) {
        await t.enterText(
          name,
          'פרסונה בע"מ ${DateTime.now().millisecondsSinceEpoch % 10000}',
        );
        await t.enterText(find.byKey(const Key('s2-phone')), '0501234567');
        await t.enterText(find.byKey(const Key('s2-taxid')), validTaxId(rnd));
        FocusManager.instance.primaryFocus?.unfocus();
        await pumpMs(300);
        await shot('compose-new-customer-valid');
        await t.ensureVisible(save);
        await t.tap(save, warnIfMissed: false);
        for (var i = 0; i < 30 && save.evaluate().isNotEmpty; i++) {
          await pumpMs(300);
        }
        await pumpMs(1200);
        await shot('compose-paid-new-business-customer-empty');
        await typeKeypad('6200');
        await shot('compose-paid-6200-allocation-hint');
        if (await scrollDown()) await shot('compose-paid-6200-summary');
      }
      await leaveIfAsked();
    }
    await closeComposeDiscard();
  });

  // Amount step: empty, typing, agorot, more details, save-draft dialog.
  await guarded('compose amount', () async {
    await openWalkInCompose('PAID');
    await shot('compose-paid-amount-empty');
    await typeKeypad('35');
    await shot('compose-paid-amount-typing');
    await typeKeypad('0.9');
    await shot('compose-paid-amount-agorot');
    if (await scrollDown()) await shot('compose-paid-amount-agorot-summary');
    final chips = ['עוד', 'ביט', "צ'ק"];
    for (final c in chips) {
      final f = find.descendant(
        of: find.byKey(const Key('compose-methods')),
        matching: find.text(c),
      );
      if (f.evaluate().isNotEmpty) {
        await t.ensureVisible(f.first);
        await t.tap(f.first, warnIfMissed: false);
        await pumpMs(500);
      }
    }
    await shot('compose-paid-method-cheque');
    final more = find.byKey(const Key('compose-more-details'));
    if (more.evaluate().isNotEmpty) {
      await t.ensureVisible(more.first);
      await t.tap(more.first, warnIfMissed: false);
      await pumpMs(1200);
      await shot('compose-more-details-sheet');
      if (await tapIf(find.byKey(const Key('s3-add-line')), waitMs: 1500)) {
        await pumpMs(500);
        final d = find.byKey(const Key('s3-line-0-description'));
        if (d.evaluate().isNotEmpty) {
          await t.enterText(d, 'שעת עבודה נוספת');
        } else {
          final ac = find.descendant(
            of: find.byKey(const Key('s3-line-0-autocomplete')),
            matching: find.byType(TextField),
          );
          if (ac.evaluate().isNotEmpty) await t.enterText(ac.first, 'שעת עבודה נוספת');
        }
        final pr = find.byKey(const Key('s3-line-0-price'));
        if (pr.evaluate().isNotEmpty) {
          final tf = find.descendant(of: pr, matching: find.byType(TextField));
          await t.enterText(tf.evaluate().isNotEmpty ? tf.first : pr, '120');
        }
        await tapIf(find.byKey(const Key('s3-add-line')), waitMs: 800);
        FocusManager.instance.primaryFocus?.unfocus();
        await shot('compose-more-details-extra-lines');
      }
      final disc = find.byKey(const Key('s3-discount'));
      if (disc.evaluate().isNotEmpty) {
        await t.ensureVisible(disc);
        final tf = find.descendant(of: disc, matching: find.byType(TextField));
        await t.enterText(tf.evaluate().isNotEmpty ? tf.first : disc, '99999');
        FocusManager.instance.primaryFocus?.unfocus();
        await shot('compose-more-details-discount-too-big');
        await pumpMs(300);
        final tf2 = find.descendant(
          of: find.byKey(const Key('s3-discount')),
          matching: find.byType(EditableText),
        );
        await t.ensureVisible(tf2.first);
        await t.tap(tf2.first, warnIfMissed: false);
        await pumpMs(200);
        await t.enterText(tf2.first, '10');
        await pumpMs(300);
        FocusManager.instance.primaryFocus?.unfocus();
      }
      final notes = find.byKey(const Key('s3-notes'));
      if (notes.evaluate().isNotEmpty) {
        await t.ensureVisible(notes);
        await t.enterText(notes, 'תודה רבה! התשלום התקבל במלואו.');
        FocusManager.instance.primaryFocus?.unfocus();
      } else {
        noteFor('no notes field in "פרטים נוספים" for a PAID receipt');
      }
      await shot('compose-more-details-discount-notes');
      if (await scrollDown()) await shot('compose-more-details-bottom');
      final done = find.text('סיום').hitTestable();
      if (done.evaluate().isNotEmpty) {
        await t.tap(done.last);
      } else {
        await systemBack();
      }
      await pumpMs(900);
      await shot('compose-after-more-details');
      if (await scrollDown()) await shot('compose-after-more-details-p2');
    }
    await tapIf(find.byKey(const Key('compose-close')), waitMs: 1500);
    await pumpMs(800);
    if (find.byKey(const Key('save-draft-dialog')).evaluate().isNotEmpty) {
      await shot('compose-save-draft-dialog');
    } else {
      miss('save-draft dialog did not appear after ✕ with data');
    }
    await leaveIfAsked();
    await hardRoot();
  });

  // REQUEST (tax invoice) with a VAT-dealer customer above ₪5,000.
  await guarded('allocation hint', () async {
    final customers = await listOf('/customers?limit=200', 'customers');
    final dealer = customers.firstWhere(
      (c) =>
          '${c['taxId'] ?? c['tax_id'] ?? ''}'.length == 9 &&
          '${c['vatDealerStatus'] ?? c['vat_dealer_status'] ?? ''}' != 'NOT_DEALER',
      orElse: () => const {},
    );
    if (dealer.isEmpty) {
      miss('no customer with a 9-digit tax id for the allocation hint');
      return;
    }
    noteFor('allocation customer ${dealer['name']} ${dealer['vatDealerStatus']}');
    unawaited(openCompose(ctx, intent: 'REQUEST', customerId: '${dealer['id']}'));
    await pumpMs(2200);
    await resumeNewIfAsked();
    await shot('compose-request-with-customer-empty');
    await typeKeypad('6200');
    await shot('compose-request-6200-allocation-hint');
    if (await scrollDown()) await shot('compose-request-6200-summary');
    await closeComposeDiscard();
    unawaited(openCompose(ctx, intent: 'QUOTE', customerId: '${dealer['id']}'));
    await pumpMs(2200);
    await resumeNewIfAsked();
    await typeKeypad('480');
    await shot('compose-quote-480');
    await closeComposeDiscard();
  });

  // Issue success (one small receipt on staging) + share sheet.
  await guarded('issue', () async {
    await openWalkInCompose('PAID');
    await typeKeypad('18');
    final primary = find.byKey(const Key('compose-primary'));
    if (!await waitFor(primary.hitTestable(), ms: 4000)) {
      miss('compose primary not shown for ₪18 walk-in');
      await closeComposeDiscard();
      return;
    }
    await shot('compose-paid-ready-to-issue');
    await t.tap(primary.hitTestable().first);
    await pumpMs(1200);
    for (var i = 0; i < 25; i++) {
      if (find.byKey(const Key('doc-issued')).evaluate().isNotEmpty ||
          find.byKey(const Key('doc-status-line')).evaluate().isNotEmpty ||
          topRoute is PopupRoute) {
        break;
      }
      await pumpMs(400);
    }
    await shot('issue-success-state');
    if (topRoute is PopupRoute) {
      noteFor('a sheet/dialog opened right after issue');
      await systemBack();
      await pumpMs(800);
      await shot('issue-success-after-closing-popup');
    }
    if (await scrollDown()) await shot('issue-success-state-p2');
  });
  await hardRoot();
}

Future<void> openDocShots(String name, String id, {bool quote = false}) async {
  unawaited(quote ? openQuote(ctx, id) : openDocument(ctx, id));
  await pumpMs(2800);
  await shotScroll(name, pages: 3);
}

Future<void> ownerDocuments() async {
  final docs = await listOf('/documents?limit=200', 'documents');
  Map<String, dynamic>? pick(bool Function(Map<String, dynamic>) f) {
    for (final d in docs) {
      if (f(d)) return d;
    }
    return null;
  }

  final draft = pick((d) => d['status'] == 'DRAFT');
  final sentUnpaid = pick(
    (d) => d['status'] == 'SENT' && big(d['openMinor']) > BigInt.zero,
  );
  Map<String, dynamic>? overdue;
  try {
    final od = await fetchOverdueDocuments(now: DateTime.now().add(const Duration(days: 75)));
    if (od.isNotEmpty) overdue = {'id': od.first.id, 'documentType': 'overdue', 'status': '', 'documentNumber': od.first.documentNumber};
  } on Object catch (e) {
    miss('fetchOverdueDocuments failed: $e');
  }
  final finalizedUnpaid = pick(
    (d) =>
        d['status'] == 'FINALIZED' &&
        d['documentType'] == 'TAX_INVOICE' &&
        big(d['openMinor']) > BigInt.zero,
  );
  final paid = pick(
    (d) =>
        d['documentType'] == 'TAX_INVOICE' &&
        d['cancelled'] != true &&
        d['voidedAt'] == null &&
        big(d['openMinor']) == BigInt.zero &&
        big(d['creditedMinor']) == BigInt.zero,
  );
  final cancelled = pick((d) => d['cancelled'] == true || d['voidedAt'] != null);
  final credit = pick((d) => d['documentType'] == 'CREDIT_DOCUMENT');
  final receipt = pick((d) => d['documentType'] == 'TAX_INVOICE_RECEIPT');
  for (final (name, d) in [
    ('doc-draft', draft),
    ('doc-sent-unpaid', sentUnpaid),
    ('doc-overdue', overdue),
    ('doc-finalized-unpaid', finalizedUnpaid),
    ('doc-paid', paid),
    ('doc-cancelled', cancelled),
    ('doc-credit-note', credit),
    ('doc-tax-invoice-receipt', receipt),
  ]) {
    if (d == null) {
      miss('$name: no such document on staging');
      continue;
    }
    await guarded(name, () async {
      await openDocShots(name, '${d['id']}');
      noteFor('${d['documentType']} ${d['status']} #${d['documentNumber']}');
      await hardRoot();
    });
  }
  final quotes = await listOf('/quotes', 'quotes');
  if (quotes.isNotEmpty) {
    await guarded('quote', () async {
      await openDocShots('doc-quote', '${quotes.first['id']}', quote: true);
      await hardRoot();
    });
  }

  final open = sentUnpaid ?? finalizedUnpaid ?? overdue;
  if (open == null) return;
  final openId = '${open['id']}';
  await guarded('doc menus', () async {
    unawaited(openDocument(ctx, openId));
    await pumpMs(2500);
    if (await tapIf(find.byTooltip('עוד'), waitMs: 1500, what: 'doc ⋯')) {
      await shot('doc-more-menu');
      await systemBack();
    }
    if (await tapIf(find.byKey(const Key('doc-secondary')), waitMs: 1500)) {
      await shot('doc-secondary-action');
      await closeSheetOrDialog();
      await leaveIfAsked();
    }
    if (await tapIf(find.byKey(const Key('doc-pdf')), waitMs: 1500)) {
      await pumpMs(2500);
      await shot('doc-pdf-viewer');
    }
    await hardRoot();
  });

  await guarded('payment sheet', () async {
    unawaited(openDocument(ctx, openId));
    await pumpMs(2500);
    unawaited(showPaymentSheet(ctx, documentId: openId));
    await pumpMs(1500);
    await shot('doc-payment-sheet-cash');
    for (final (label, name) in [
      ('העברה / ביט', 'bit-transfer'),
      ("צ'ק", 'cheque'),
    ]) {
      var f = find.text(label).hitTestable();
      if (f.evaluate().isEmpty) {
        final more = find.text('עוד').hitTestable();
        if (more.evaluate().isNotEmpty) {
          await t.tap(more.last);
          await pumpMs(400);
        }
        f = find.text(label).hitTestable();
      }
      if (f.evaluate().isEmpty) {
        miss('payment sheet: no "$label" chip');
        continue;
      }
      await t.tap(f.first);
      await shot('doc-payment-sheet-$name');
      if (name == 'cheque' && await scrollDown(dy: 300)) {
        await shot('doc-payment-sheet-cheque-fields');
      }
    }
    final add = find.byKey(const Key('s5-add'));
    if (await tapIf(add, waitMs: 800)) await shot('doc-payment-sheet-split');
    await systemBack();
    await hardRoot();
  });

  await guarded('cancel sheet', () async {
    for (final (name, d) in [
      ('unpaid', open),
      ('paid', paid),
      ('draft', draft),
    ]) {
      if (d == null) continue;
      final id = '${d['id']}';
      unawaited(openDocument(ctx, id));
      await pumpMs(2500);
      unawaited(showCancelSheet(ctx, documentId: id));
      await pumpMs(1800);
      await shot('doc-cancel-sheet-$name');
      final amount = find.byKey(const Key('s8-amount'));
      if (name == 'unpaid' && amount.evaluate().isNotEmpty) {
        await t.enterText(amount, '100');
        FocusManager.instance.primaryFocus?.unfocus();
        await shot('doc-cancel-sheet-partial-credit');
        await t.enterText(amount, '999999');
        FocusManager.instance.primaryFocus?.unfocus();
        await shot('doc-cancel-sheet-credit-too-big');
      }
      // Never tap s8-credit / s8-void (they issue the credit / void).
      await hardRoot();
    }
  });

  await guarded('share sheet', () async {
    final target = receipt ?? open;
    final id = '${target['id']}';
    unawaited(openDocument(ctx, id));
    await pumpMs(2500);
    unawaited(showShareSheet(ctx, documentId: id));
    await pumpMs(2000);
    await shot('doc-share-sheet');
    if (await tapIf(find.byKey(const Key('s6-more')), waitMs: 1200)) {
      await shotScroll('doc-share-sheet-more-expanded', pages: 2);
    }
    if (await tapIf(find.byKey(const Key('s6-qr')), waitMs: 800)) {
      await shot('doc-share-qr');
    }
    await systemBack();
    await hardRoot();
  });

  // WhatsApp payment reminder (url_launcher stubbed).
  await guarded('whatsapp reminder', () async {
    var overdueList = await fetchOverdueDocuments();
    noteFor('overdue documents today: ${overdueList.length}');
    if (overdueList.isEmpty) {
      // Staging has no invoice past due today: the same UI with the invoices
      // that will be overdue in 75 days.
      overdueList = await fetchOverdueDocuments(
        now: DateTime.now().add(const Duration(days: 75)),
      );
      noteFor('overdue in 75 days (used for the reminder UI): ${overdueList.length}');
    }
    if (overdueList.isEmpty) {
      miss('no overdue documents: reminder preview not reachable');
      return;
    }
    await selectTab(AppTab.home);
    unawaited(showReminderPreview(ctx, overdueList, reminded: ReminderLog.all()));
    await pumpMs(1500);
    await shotScroll('reminder-preview-dialog', pages: 2);
    final wa = keyPrefix('reminder-wa-').hitTestable();
    if (wa.evaluate().isNotEmpty) {
      final before = externalOpens.length;
      await t.tap(wa.first);
      await pumpMs(1500);
      await shot('reminder-after-whatsapp-tap');
      if (externalOpens.length > before) {
        noteFor('WhatsApp opened: ${Uri.decodeFull(externalOpens.last)}');
      }
    } else {
      miss('reminder preview has no "הזכר בווטסאפ" row');
    }
    await tapIf(find.byKey(const Key('reminders-cancel')), waitMs: 800);
    await hardRoot();
    unawaited(
      showWhatsAppReminders(ctx, [
        for (final d in overdueList.take(4))
          ReminderTarget(
            documentId: d.id,
            documentType: d.documentType,
            customerName: d.customerName,
            documentNumber: d.documentNumber,
            openMinor: d.openMinor ?? BigInt.zero,
            dueDate: d.dueDate,
          ),
      ]),
    );
    await shot('reminder-whatsapp-list-dialog');
    await systemBack();
    // On the document: "שלח תזכורת" is D's primary for an overdue invoice.
    final od = overdueList.first;
    unawaited(openDocument(ctx, od.id));
    await pumpMs(2500);
    final p = find.byKey(const Key('doc-primary'));
    if (p.evaluate().isNotEmpty) {
      final before = externalOpens.length;
      await t.tap(p.first, warnIfMissed: false);
      await pumpMs(1500);
      await shot('doc-overdue-after-primary-reminder');
      if (externalOpens.length > before) {
        noteFor('opened: ${Uri.decodeFull(externalOpens.last)}');
      }
      await closeSheetOrDialog();
    }
    await hardRoot();
  });
}

Future<void> ownerCustomers() async {
  await guarded('people tab', () async {
    await selectTab(AppTab.people);
    await pumpMs(2000);
    await shotScroll('customers-list', pages: 2);
    final search = find.byKey(const Key('people-search'));
    if (await waitFor(search, ms: 2000)) {
      await t.enterText(search, 'דנ');
      await shot('customers-search');
      await t.enterText(search, 'קקקזזז');
      await shot('customers-search-no-results');
      await t.enterText(search, '');
      FocusManager.instance.primaryFocus?.unfocus();
      await pumpMs(500);
    }
    for (final chip in ['ספקים', 'חייבים']) {
      final c = find.text(chip).hitTestable();
      if (c.evaluate().isNotEmpty) {
        await t.tap(c.first);
        await shot('customers-chip-$chip');
      }
    }
    for (final chip in ['לקוחות', 'הכול']) {
      final c = find.text(chip).hitTestable();
      if (c.evaluate().isNotEmpty) {
        await t.tap(c.first);
        await pumpMs(500);
        break;
      }
    }
    if (await tapIf(find.byKey(const Key('people-add')), waitMs: 1500)) {
      await shot('customers-add-form');
      await back();
      await leaveIfAsked();
    }
    await hardRoot();
  });

  await guarded('person card', () async {
    final customers = await listOf('/customers?limit=200', 'customers');
    if (customers.isEmpty) return;
    // A customer with documents makes the richest card.
    final docs = await listOf('/documents?limit=200', 'documents');
    final counts = <String, int>{};
    for (final d in docs) {
      final c = '${d['customerId']}';
      counts[c] = (counts[c] ?? 0) + 1;
    }
    customers.sort(
      (a, b) => (counts['${b['id']}'] ?? 0).compareTo(counts['${a['id']}'] ?? 0),
    );
    final id = '${customers.first['id']}';
    unawaited(openPerson(ctx, id));
    await pumpMs(3000);
    await shotScroll('customer-card', pages: 4);
    await scrollTop();
    for (final (label, n) in [
      ('ביקורים', 'visits'),
      ('פתקים ומעקב', 'notes-followups'),
      ('כסף', 'money'),
    ]) {
      final f = find.text(label);
      if (f.evaluate().isEmpty) {
        miss('customer card: CRM tab "$label" not present');
        continue;
      }
      await t.ensureVisible(f.first);
      await pumpMs(200);
      await t.tap(f.first, warnIfMissed: false);
      await pumpMs(1200);
      await shot('customer-card-crm-$n');
      if (await scrollDown(dy: 400)) await shot('customer-card-crm-$n-p2');
      await scrollTop();
    }
    for (final (label, n) in [
      ('עבודה חדשה', 'new-job'),
      ('פתק חדש', 'new-note'),
      ('תזכורת', 'new-reminder'),
    ]) {
      await scrollTop();
      if (!await tapIf(find.text(label), waitMs: 1500, what: n)) {
        miss('customer card: $n not reachable');
        continue;
      }
      await pumpMs(800);
      await shotScroll('customer-crm-dialog-$n', pages: 2);
      await systemBack();
      await leaveIfAsked();
      await pumpMs(400);
    }
    await scrollTop();
    final stage = find.byTooltip('מצב הלקוח');
    final stage2 = find.text('בעבודה');
    if (await tapIf(stage.evaluate().isNotEmpty ? stage : stage2, waitMs: 1500)) {
      await shot('customer-crm-stage-menu');
      await systemBack();
    }
    await scrollTop();
    if (await tapIf(find.byTooltip('עוד'), waitMs: 1200)) {
      await shot('customer-card-more-menu');
      await systemBack();
    }
    if (await tapIf(find.text('פרטים ועריכה'), waitMs: 1500) ||
        await tapIf(find.byKey(const Key('person-edit')), waitMs: 500)) {
      await shotScroll('customer-edit-form', pages: 2);
      await back();
      await leaveIfAsked();
    }
    // "שלח כרטסת" is not tapped: it e-mails the statement at once.
    // The business board (agenda).
    await scrollTop();
    final board = find.text('לוח העסק');
    if (await tapIf(board, waitMs: 1500, what: 'לוח העסק')) {
      await pumpMs(1500);
      await shotScroll('crm-board', pages: 2);
      for (var i = 0; i < 4; i++) {
        final b = find.byKey(Key('crm-board-$i'));
        if (b.evaluate().isEmpty) continue;
        await t.tap(b, warnIfMissed: false);
        await shot('crm-board-tab-$i');
      }
      await back();
    } else {
      miss('crm board "לוח העסק" not reachable from the customer card');
    }
    await hardRoot();
  });
  await guarded('board from home', () async {
    await selectTab(AppTab.home);
    if (await tapIf(find.byKey(const Key('home-crm-reminders')), waitMs: 1200)) {
      await shot('crm-board-from-home');
    }
    await hardRoot();
  });
}

Future<void> ownerExpenses() async {
  await guarded('expenses overview', () async {
    unawaited(openExpenseOverview(ctx));
    await pumpMs(2500);
    await shotScroll('expenses-overview', pages: 4);
    await hardRoot();
    unawaited(openExpenses(ctx));
    await pumpMs(2500);
    await shotScroll('expenses-review-list', pages: 2);
    final row = keyPrefix('expense-row-');
    if (await tapIf(row, waitMs: 1500, what: 'expense row')) {
      await pumpMs(2000);
      await shotScroll('expenses-review-card-existing', pages: 2);
    }
    await hardRoot();
  });
  await guarded('expense capture', () async {
    // The image picker never reaches iOS (no permission prompt): first it
    // answers "no camera" (the simulator's state), then a receipt photo.
    t.binding.defaultBinaryMessenger.setMockMessageHandler(
      'dev.flutter.pigeon.image_picker_ios.ImagePickerApi.pickImage',
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[
        'no_available_camera',
        'No camera available',
        null,
      ]),
    );
    unawaited(openExpenseCapture(ctx));
    await pumpMs(2500);
    await shot('expense-capture-chooser-camera-unavailable');
    await mockCamera(t, uniqueJpeg());
    final cam2 = find.text('צלם').hitTestable();
    if (cam2.evaluate().isNotEmpty) {
      await t.tap(cam2.first);
    } else {
      miss('expense capture: no "צלם" button: ${visibleTexts().join(' | ')}');
    }
    var consent = false;
    for (var i = 0; i < 40; i++) {
      await pumpMs(400);
      if (find.byKey(const Key('expense-ocr-allow')).evaluate().isNotEmpty) {
        consent = true;
        break;
      }
      if (keyPrefix('card-').evaluate().isNotEmpty && i > 10) break;
    }
    await shot('expense-after-upload');
    if (consent) {
      await shot('expense-ocr-consent-dialog');
      await t.tap(find.byKey(const Key('expense-ocr-allow')));
    }
    await pumpMs(3500);
    await shot('expense-review-card-ocr-unavailable');
    if (await scrollDown()) await shot('expense-review-card-p2');
    unmockCamera(t);
    await hardRoot();
  });
}

Future<void> ownerReports() async {
  await guarded('reports', () async {
    unawaited(openReports(ctx));
    await pumpMs(3000);
    await shotScroll('reports-list', pages: 3);
    await hardRoot();
    unawaited(openReports(ctx));
    await pumpMs(2500);
    final cards = <String>{};
    for (var i = 0; i < 5; i++) {
      cards.addAll(keysWithPrefix('report-card-'));
      if (!await scrollDown()) break;
    }
    noteFor('report cards: ${cards.join(', ')}');
    await hardRoot();
    for (final c in cards) {
      final kind = c.substring('report-card-'.length);
      unawaited(openReport(ctx, kind));
      await pumpMs(3000);
      await shotScroll('report-$kind', pages: 2);
      await hardRoot();
    }
  });
}

Future<void> ownerManagement() async {
  await selectTab(AppTab.business);
  await pumpMs(1500);
  await shotScroll('management', pages: 4);
  await hardRoot();
  await selectTab(AppTab.business);
  final rows = <String>{};
  for (var i = 0; i < 6; i++) {
    rows.addAll(keysWithPrefix('brow-'));
    if (!await scrollDown()) break;
  }
  noteFor('management rows: ${rows.join(', ')}');
  await guarded('quick actions more', () async {
    await hardRoot();
    await selectTab(AppTab.business);
    final more = keyPrefix('management-action-', matching: RegExp(r'more$'));
    if (await tapIf(more, waitMs: 1200)) {
      await shot('management-quick-actions-more');
      await systemBack();
    }
  });
  Future<void> openRow(String k, String prefix) async {
    await guarded('row $k', () async {
      final f = find.byKey(Key(k));
      for (var i = 0; i < 6 && f.hitTestable().evaluate().isEmpty; i++) {
        if (f.evaluate().isNotEmpty) {
          await t.ensureVisible(f);
          await pumpMs(200);
          break;
        }
        if (!await scrollDown(dy: 300)) break;
      }
      if (!await tapIf(f, what: k)) {
        miss('$prefix row $k not tappable');
        return;
      }
      await pumpMs(2200);
      final name = '$prefix-${k.substring(5)}';
      await shotScroll(name, pages: 3);
      if (k == 'brow-team') {
        if (await tapIf(find.byKey(const Key('team-invite')), waitMs: 1500)) {
          await shotScroll('management-team-invite', pages: 2);
          await systemBack();
          await leaveIfAsked();
        }
        if (await tapIf(find.byKey(const Key('team-invite-accountant')), waitMs: 1000)) {
          await shot('management-team-invite-accountant');
          await systemBack();
          await leaveIfAsked();
        }
        final member = keyPrefix('member-').hitTestable();
        if (member.evaluate().length > 1) {
          await t.tap(member.at(1), warnIfMissed: false);
          await pumpMs(1200);
          await shotScroll('management-team-member-permissions', pages: 2);
          await systemBack();
          await leaveIfAsked();
        }
      }
      if (k == 'brow-reminders') {
        if (find.byKey(const Key('reminders-confirm')).evaluate().isNotEmpty) {
          await shot('management-reminders-confirm-dialog');
        }
      }
      if (k == 'brow-more') {
        final sub = keysWithPrefix('brow-');
        noteFor('עוד הגדרות rows: ${sub.join(', ')}');
        for (final s in sub) {
          await openRow(s, 'management-more');
          await pumpMs(300);
          if (find.text('עוד הגדרות').evaluate().isEmpty) {
            unawaited(openBusinessSection(ctx, BusinessSection.more));
            await pumpMs(1500);
          }
        }
      }
      if (topRoute is PopupRoute) {
        await systemBack();
      } else if (k != 'brow-more' || prefix == 'management') {
        await back();
      }
      await leaveIfAsked();
      await pumpMs(400);
    });
  }

  for (final k in rows) {
    if (k == 'brow-subscription') continue;
    await hardRoot();
    await selectTab(AppTab.business);
    await pumpMs(600);
    await openRow(k, 'management');
  }
  await guarded('subscription', () async {
    await hardRoot();
    plansGuardOn = false;
    await pumpMs(500);
    unawaited(showBillingPlans(ctx));
    await pumpMs(3000);
    await shotScroll('management-subscription-plans', pages: 2);
    await systemBack();
    plansGuardOn = true;
    await hardRoot();
  });
  for (final s in BusinessSection.values) {
    await guarded('section ${s.name}', () async {
      await hardRoot();
      unawaited(openBusinessSection(ctx, s));
      await pumpMs(2200);
      await shot('management-section-${s.name}');
      await hardRoot();
    });
  }
  await guarded('switch business sheet', () async {
    await hardRoot();
    await selectTab(AppTab.business);
    if (await tapIf(find.byKey(const Key('business-name')), waitMs: 1500)) {
      await shotScroll('switch-business-sheet', pages: 2);
      await systemBack();
    }
  });
}

Future<void> ownerProfile() async {
  await guarded('profile', () async {
    await hardRoot();
    await selectTab(AppTab.profile);
    await pumpMs(1500);
    await shotScroll('profile', pages: 3);
    if (await tapIf(find.text('הגדרות'), waitMs: 1500)) {
      await pumpMs(800);
      await shotScroll('profile-settings', pages: 4);
    }
    final log = find.byKey(const Key('account-error-log'));
    for (var i = 0; i < 6 && log.evaluate().isEmpty; i++) {
      if (!await scrollDown(dy: 300)) break;
    }
    if (log.evaluate().isEmpty) {
      unawaited(openBusinessSection(ctx, BusinessSection.account));
      await pumpMs(2000);
      for (var i = 0; i < 6 && log.evaluate().isEmpty; i++) {
        if (!await scrollDown(dy: 300)) break;
      }
    }
    if (log.evaluate().isNotEmpty) {
      await t.ensureVisible(log);
      await pumpMs(300);
      await shot('settings-error-log-row');
      final before = externalOpens.length;
      await t.tap(log, warnIfMissed: false);
      await pumpMs(2000);
      await shot('settings-error-log-after-tap');
      if (externalOpens.length > before) {
        noteFor('error log shared: ${externalOpens.last}');
      }
      await closeSheetOrDialog();
    } else {
      miss('"שלח יומן תקלות" (account-error-log) not found');
    }
    // "צא מהמכשיר" signs out at once (no confirmation): not tapped here.
    if (await tapIf(find.byKey(const Key('account-delete')), waitMs: 1000)) {
      await shotScroll('settings-delete-account', pages: 2);
      await back();
    }
    await hardRoot();
    await selectTab(AppTab.profile);
    if (await tapIf(find.byKey(const Key('profile-plan-cta')), waitMs: 1200)) {
      noteFor('plan CTA opens the plans sheet (closed by the guard)');
    }
    await hardRoot();
  });
}

Future<void> ownerOfflineAndErrors() async {
  final real = ApiClient.instance.httpClient;
  await guarded('delete account screen', () async {
    unawaited(openDeleteAccount(ctx));
    await pumpMs(2000);
    await shotScroll('settings-delete-account', pages: 2);
    await hardRoot();
  });
  await guarded('offline', () async {
    await hardRoot();
    await selectTab(AppTab.home);
    ApiClient.instance.httpClient = OfflineClient();
    final list = find.byKey(const Key('home-list'));
    if (list.evaluate().isNotEmpty) {
      await t.fling(list, const Offset(0, 500), 1500);
    }
    await pumpMs(4000);
    await shot('offline-home');
    unawaited(openActivity(ctx));
    await pumpMs(2500);
    await shot('offline-activity');
    await hardRoot();
    await openWalkInCompose('PAID');
    await typeKeypad('50');
    await shot('offline-compose');
    await closeComposeDiscard();
    await selectTab(AppTab.people);
    await pumpMs(1500);
    await shot('offline-customers');
    unawaited(openReports(ctx));
    await pumpMs(3000);
    await shot('offline-reports');
    await hardRoot();
  });
  ApiClient.instance.httpClient = real;
  await guarded('server error', () async {
    await hardRoot();
    await selectTab(AppTab.home);
    final list = find.byKey(const Key('home-list'));
    if (list.evaluate().isNotEmpty) {
      await t.fling(list, const Offset(0, 500), 1500);
    }
    await pumpMs(3000);
    ApiClient.instance.httpClient = FailingClient(
      real,
      RegExp(r'^/(reports|documents|customers|expenses)'),
    );
    unawaited(openReports(ctx));
    await pumpMs(3000);
    await shot('error-500-reports');
    await hardRoot();
    unawaited(openActivity(ctx));
    await pumpMs(3000);
    await shot('error-500-activity');
    await hardRoot();
    final docs = await listOf('/documents?limit=5', 'documents');
    noteFor('documents during 500: ${docs.length}');
    unawaited(openDocument(ctx, '00000000-0000-0000-0000-000000000000'));
    await pumpMs(3000);
    await shot('error-500-document');
    await hardRoot();
  });
  ApiClient.instance.httpClient = real;
  await guarded('missing document', () async {
    unawaited(openDocument(ctx, '00000000-0000-0000-0000-000000000000'));
    await pumpMs(3000);
    await shot('error-document-not-found');
    await hardRoot();
  });
  await guarded('safe error card', () async {
    // What a build error looks like in release (ErrorWidget.builder).
    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Center(child: SafeErrorCard())),
        ),
      ),
    );
    await shot('error-safe-error-card');
    await hardRoot();
  });
  await selectTab(AppTab.home);
  await pumpMs(1500);
}

// ---- SIGNED OUT ------------------------------------------------------------------

Future<void> signedOutPart() async {
  ApiClient.instance.httpClient = FakeSupabase(ApiClient.instance.httpClient);
  await launchSignedOut(t);
  await pumpMs(1500);
  await shot('login');
  await guarded('login errors', () async {
    await tapIf(find.text('כניסה'));
    await shot('login-empty-submit');
    await t.enterText(find.byType(TextField).at(0), 'not-an-email');
    await t.enterText(find.byType(TextField).at(1), 'x');
    FocusManager.instance.primaryFocus?.unfocus();
    await tapIf(find.text('כניסה'));
    await shot('login-invalid-email');
    await t.enterText(find.byType(TextField).at(0), 'mobile-owner@tevel.test');
    await t.enterText(find.byType(TextField).at(1), 'WrongPassword123');
    FocusManager.instance.primaryFocus?.unfocus();
    await tapIf(find.text('כניסה'));
    await pumpMs(2000);
    await shot('login-wrong-password');
    final eye = find.byTooltip('הצג סיסמה');
    if (await tapIf(eye, waitMs: 800)) await shot('login-password-visible');
  });
  await guarded('forgot', () async {
    await t.enterText(find.byType(TextField).at(0), '');
    if (!await tapIf(find.text('שכחתי סיסמה'), what: 'שכחתי סיסמה')) {
      final f = find.textContaining('שכחת');
      await tapIf(f, what: 'forgot');
    }
    await pumpMs(1200);
    await shot('forgot-email-step');
    final email = find.byKey(const Key('recovery-email'));
    final send = find.byKey(const Key('recovery-send'));
    await t.enterText(email, 'not-an-email');
    await tapIf(send);
    await shot('forgot-email-invalid');
    await t.enterText(email, 'mobile-viewer@tevel.test');
    await tapIf(send);
    await pumpMs(1500);
    await shot('forgot-code-step');
    final code = find.byKey(const Key('recovery-code'));
    final verify = find.byKey(const Key('recovery-verify'));
    if (code.evaluate().isNotEmpty) {
      await t.enterText(code, '12');
      await tapIf(verify);
      await shot('forgot-code-bad-format');
      await t.enterText(code, '123456');
      await tapIf(verify);
      await pumpMs(1500);
    }
    await shot('forgot-new-password-step');
    final pw = find.byKey(const Key('recovery-password'));
    final save = find.byKey(const Key('recovery-save'));
    if (pw.evaluate().isNotEmpty) {
      await t.enterText(pw, 'short');
      await tapIf(save);
      await shot('forgot-new-password-too-short');
      await t.enterText(pw, 'QaNewPassword-2026');
      FocusManager.instance.primaryFocus?.unfocus();
      await shot('forgot-new-password-filled');
      noteFor('not saved: the fake Supabase would then sign in to staging');
    }
    await systemBack();
    await pumpMs(800);
  });

  // Invitations: created by the owner on staging, opened like the link.
  DevSession? ownerApi;
  try {
    ownerApi = await devSignIn(ownerEmail);
  } on Object catch (e) {
    miss('owner API sign-in for invites failed: $e');
  }
  Future<void> inviteShots(String name, String token, {Future<void> Function()? then}) async {
    await guarded('invite $name', () async {
      openInvite(token);
      await pumpMs(3000);
      await shotScroll('invite-$name', pages: 2);
      if (then != null) await then();
      while (find.byType(LoginScreen).hitTestable().evaluate().isEmpty &&
          topRoute?.isFirst == false) {
        await systemBack();
      }
      await pumpMs(500);
    });
  }

  final stamp = DateTime.now().millisecondsSinceEpoch % 1000000;
  if (ownerApi != null) {
    try {
      final (_, newToken) = await devInvite(
        ownerApi,
        'qa-persona-$stamp@tevel.test',
      );
      await inviteShots(
        'new-account',
        newToken,
        then: () async {
          final join = find.byKey(const Key('invite-join'));
          if (await tapIf(join, waitMs: 1000)) {
            await shot('invite-new-account-empty-submit');
          }
          final name = find.byKey(const Key('invite-name'));
          final pw = find.byKey(const Key('invite-password'));
          if (name.evaluate().isNotEmpty) await t.enterText(name, 'עובד בדיקה');
          if (pw.evaluate().isNotEmpty) await t.enterText(pw, 'QaInvite-2026-pw');
          FocusManager.instance.primaryFocus?.unfocus();
          await shot('invite-new-account-filled');
          if (await tapIf(join, waitMs: 1000)) {
            await pumpMs(3000);
            await shotScroll('invite-new-account-after-join', pages: 2);
          }
        },
      );
    } on Object catch (e) {
      miss('invite (new account) failed: $e');
    }
    try {
      final (_, existingToken) = await devInvite(
        ownerApi,
        'mobile-patur@tevel.test',
      );
      await inviteShots(
        'existing-account',
        existingToken,
        then: () async {
          final pw = find.byKey(const Key('invite-password'));
          if (pw.evaluate().isNotEmpty) {
            await t.enterText(pw, 'WrongPassword123');
            FocusManager.instance.primaryFocus?.unfocus();
            if (await tapIf(find.byKey(const Key('invite-join')), waitMs: 800)) {
              await pumpMs(2500);
              await shot('invite-existing-account-wrong-password');
            }
          }
        },
      );
    } on Object catch (e) {
      miss('invite (existing account) failed: $e');
    }
    try {
      final (id, revokedToken) = await devInvite(
        ownerApi,
        'qa-persona-revoked-$stamp@tevel.test',
      );
      await devRevokeInvitation(ownerApi, id);
      await inviteShots('revoked', revokedToken);
    } on Object catch (e) {
      miss('invite (revoked) failed: $e');
    }
    try {
      final (_, memberToken) = await devInvite(
        ownerApi,
        'mobile-viewer@tevel.test',
      );
      await inviteShots('already-member', memberToken);
    } on Object catch (e) {
      miss('invite (already member) refused at invite time: $e');
    }
    await ownerApi.logout();
  }
  await inviteShots('invalid-token', 'qaInvalidToken0000000000000000');
}

// ---- OTHER ROLES -----------------------------------------------------------------

Future<void> roleShort(String r, String email, {String business = devBusinessId}) async {
  role = r;
  shotNo = 0;
  await guarded('launch $r', () async {
    await launchSignedInAs(t, email, businessId: business);
    if (!await waitFor(find.byKey(const Key('tab-home')), ms: 40000)) {
      await shot('launch-no-home');
      return;
    }
    await pumpMs(3500);
  });
  noteFor('caps: ${Cap.values.where(businessContext.can).map((c) => c.name).join(',')}');
  await guarded('home', () async {
    await shotScroll('home', pages: 3);
    await hardRoot();
  });
  for (final tab in [AppTab.people, AppTab.profile]) {
    await guarded('tab $tab', () async {
      final f = find.byKey(Key('tab-${tab.name}'));
      if (f.evaluate().isEmpty) {
        noteFor('no ${tab.name} tab in the bottom bar');
        return;
      }
      await selectTab(tab);
      await pumpMs(1500);
      await shot('tab-${tab.name}');
      await hardRoot();
    });
  }
  await guarded('compose', () async {
    await selectTab(AppTab.home);
    if (find.byKey(const Key('tab-create')).evaluate().isEmpty ||
        !businessContext.caps.showCreateTab) {
      noteFor('no create (+) button for $r');
      return;
    }
    await tapIf(find.byKey(const Key('tab-create')));
    await pumpMs(1800);
    await resumeNewIfAsked();
    await shot('create-first-screen');
    final walkIn = find.byKey(const Key('s2-walkin'));
    if (await tapIf(walkIn, waitMs: 2000)) {
      await pumpMs(1200);
    } else {
      await closeSheetOrDialog();
      await openWalkInCompose('PAID');
    }
    await shot('compose-amount-empty');
    await typeKeypad('6200');
    await shot('compose-amount-6200');
    if (await scrollDown()) await shot('compose-amount-6200-p2');
    await closeComposeDiscard();
  });
  await guarded('management', () async {
    await hardRoot();
    await selectTab(AppTab.business);
    await pumpMs(1500);
    await shotScroll('management', pages: 3);
    await hardRoot();
    await selectTab(AppTab.business);
    final rows = <String>{};
    for (var i = 0; i < 6; i++) {
      rows.addAll(keysWithPrefix('brow-'));
      if (!await scrollDown()) break;
    }
    noteFor('management rows for $r: ${rows.join(', ')}');
    for (final k in rows) {
      if (k == 'brow-subscription' || k == 'brow-reminders') continue;
      await guarded('row $k', () async {
        await hardRoot();
        await selectTab(AppTab.business);
        await pumpMs(500);
        final f = find.byKey(Key(k));
        for (var i = 0; i < 6 && f.evaluate().isEmpty; i++) {
          if (!await scrollDown(dy: 300)) break;
        }
        if (!await tapIf(f, what: k)) return;
        await pumpMs(2200);
        await shot('management-${k.substring(5)}');
        await closeSheetOrDialog();
        await hardRoot();
      });
    }
  });
  await guarded('reports deep link', () async {
    await hardRoot();
    final ok = await go('/reports');
    await pumpMs(2500);
    await shot('reports-via-link${ok ? '' : '-refused'}');
    await hardRoot();
  });
  await session.signOutLocally();
  await pumpMs(1500);
}

// ---- main ----------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  startPlansGuard();
  urlOpener = (uri, {inApp = false}) async {
    externalOpens.add('$uri');
    return true;
  };
  pdfSharer = (bytes, name, {text}) async => externalOpens.add('pdf $name');
  textSharer = (text) async => externalOpens.add('text $text');

  testWidgets('persona screens ($part)', (tester) async {
    await runCaptured(tester, () async {
      final rnd = Random();
      switch (part) {
        case 'owner':
          role = 'owner';
          shotNo = startNo;
          const order = [
            'home', 'create', 'compose', 'documents', 'customers',
            'expenses', 'reports', 'management', 'profile', 'errors',
          ];
          final first = from.isEmpty ? 0 : order.indexOf(from);
          bool run(String s) => order.indexOf(s) >= first;
          if (from.isEmpty) {
            await ownerLoginThroughUi();
          } else {
            plansGuardOn = true;
            await launchSignedInAs(t, owner);
            await waitFor(find.byKey(const Key('tab-home')), ms: 40000);
            await pumpMs(3000);
          }
          if (run('home')) await ownerHome();
          if (run('create')) await ownerBottomBarCreate();
          if (run('compose')) await ownerCompose(rnd);
          if (run('documents')) await ownerDocuments();
          if (run('customers')) await ownerCustomers();
          if (run('expenses')) await ownerExpenses();
          if (run('reports')) await ownerReports();
          if (run('management')) await ownerManagement();
          if (run('profile')) await ownerProfile();
          if (run('errors')) await ownerOfflineAndErrors();
          await session.signOut();
          await pumpMs(1500);
        case 'signedout':
          role = 'signed-out';
          await signedOutPart();
        case 'roles':
          plansGuardOn = true;
          final only = const String.fromEnvironment('ROLES');
          for (final (r, email, business) in [
            ('employee', 'mobile-employee@tevel.test', devBusinessId),
            ('accountant', 'mobile-cpa-full@tevel.test', devBusinessId),
            ('viewer', 'mobile-viewer@tevel.test', devBusinessId),
            ('patur', 'mobile-patur@tevel.test', paturBusiness),
          ]) {
            if (only.isNotEmpty && !only.split(',').contains(r)) continue;
            await roleShort(r, email, business: business);
          }
      }
      print('EXTERNAL-OPENS: ${externalOpens.join(' || ')}');
      validTaxId(rnd);
    });
  }, timeout: const Timeout(Duration(minutes: 90)));
}
