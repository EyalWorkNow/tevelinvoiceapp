// Crash sweep (QA 2026-11-15): back/forward churn through every screen.
//
// TestFlight build 8 crashed "between transitions" (add a customer, go back,
// everything breaks). The E2E suites follow fixed happy paths; this one
// churns: tabs back and forth, open → back before load, double back, swipe
// back, sheets opened and dismissed, background/resume, and the add-customer
// flow from both entry points.
//
// Every framework error (FlutterError.onError), every uncaught async error
// (our own guarded zone + PlatformDispatcher.onError) and every ErrorWidget
// on screen is recorded with the step it happened in. The sweep never stops
// on the first error; the test fails at the end with the full list.
//
// Run (simulator, local staging API):
//   flutter test integration_test/crash_sweep_test.dart -d <sim> \
//     --dart-define=API_BASE=http://127.0.0.1:3041 \
//     --dart-define=MAILDIR=$HOME/invoiceproject-staging-qa/outgoing-emails
import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/app_shell.dart' show currentTab, AppTab;
import 'package:invoice/router.dart' show navigatorKey;
import 'package:invoice/screens/people/person_screen.dart';
import 'package:invoice/state/business_context.dart';
import 'package:invoice/state/session.dart';

import 'package:invoice/screens/document/sheets/s6_share.dart'
    show pdfSharer, textSharer;
import 'package:invoice/util/allowed_urls.dart' show urlOpener;

import 'qa_plans_guard.dart';
import 'v2_qa_gate_helpers.dart';

// ---- error collection ---------------------------------------------------------

class SweepError {
  SweepError(this.step, this.kind, this.error, this.stack);
  final String step;
  final String kind;
  final String error;
  final String stack;

  @override
  String toString() {
    final lines = stack.split('\n').where((l) => l.trim().isNotEmpty);
    return '[$step] $kind: $error\n    ${lines.take(14).join('\n    ')}';
  }
}

final List<SweepError> sweepErrors = [];
final List<String> sweepNotes = [];
String currentStep = 'start';
final Set<int> _seenErrorWidgets = {};

void record(String kind, Object error, StackTrace? stack) {
  final text = '$error';
  // The same error repeated in one step (e.g. a layout error every frame)
  // is one finding.
  if (sweepErrors.any(
    (e) => e.step == currentStep && e.kind == kind && e.error == text,
  )) {
    return;
  }
  sweepErrors.add(SweepError(currentStep, kind, text, '${stack ?? ''}'));
  // ignore: avoid_print
  print('SWEEP-ERROR [$currentStep] $kind: $text');
}

void note(String text) {
  sweepNotes.add('[$currentStep] $text');
  // ignore: avoid_print
  print('SWEEP-NOTE [$currentStep] $text');
}

/// Grey screens: an ErrorWidget in the tree (release shows them grey).
void checkErrorWidgets() {
  for (final e in find.byType(ErrorWidget).evaluate()) {
    final w = e.widget as ErrorWidget;
    if (_seenErrorWidgets.add(identityHashCode(w))) {
      record('ErrorWidget', w.message, null);
    }
  }
}

// ---- driving helpers -------------------------------------------------------------

late WidgetTester t;

Future<void> pumpMs(int ms) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  do {
    await t.pump(const Duration(milliseconds: 50));
    checkErrorWidgets();
  } while (DateTime.now().isBefore(end));
}

Future<bool> waitFor(Finder f, {int ms = 8000}) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 100));
    checkErrorWidgets();
    if (f.evaluate().isNotEmpty) return true;
  }
  return false;
}

/// Taps [f] when it is (or becomes) hit-testable; notes and returns false
/// otherwise (a missing widget is a note, never an app error).
/// Scrolls the visible vertical list until [f] is built (lazy lists).
Future<void> scrollTo(Finder f, {int tries = 8}) async {
  for (var i = 0; i < tries && f.evaluate().isEmpty; i++) {
    final lists = find
        .byWidgetPredicate(
          (w) =>
              w is Scrollable &&
              axisDirectionToAxis(w.axisDirection) == Axis.vertical,
        )
        .hitTestable();
    if (lists.evaluate().isEmpty) return;
    await t.drag(lists.last, const Offset(0, -350), warnIfMissed: false);
    await pumpMs(200);
  }
}

Future<bool> tapIf(Finder f, {int waitMs = 6000, String? what}) async {
  final hit = f.hitTestable();
  if (f.evaluate().isEmpty) {
    await waitFor(f, ms: waitMs ~/ 2);
    if (f.evaluate().isEmpty) await scrollTo(f);
  }
  if (!await waitFor(hit, ms: waitMs)) {
    // Maybe below the fold.
    if (f.evaluate().isNotEmpty) {
      try {
        await t.ensureVisible(f.first);
        await pumpMs(150);
      } on Object {
        // not scrollable
      }
    }
    if (hit.evaluate().isEmpty) {
      note('not found: ${what ?? f.describeMatch(Plurality.one)}');
      return false;
    }
  }
  await t.tap(hit.first, warnIfMissed: false);
  await t.pump(const Duration(milliseconds: 16));
  return true;
}

NavigatorState get nav => navigatorKey.currentState!;

Route<dynamic>? get topRoute {
  Route<dynamic>? top;
  nav.popUntil((r) {
    top = r;
    return true;
  });
  return top;
}

/// Back like a user: the screen's own back / close button when there is one,
/// else the system back (maybePop, honours PopScope).
Future<void> back({int settleMs = 450}) async {
  final candidates = [
    find.byTooltip('הקודם'),
    find.byKey(const Key('compose-close')),
    find.byTooltip('סגור'),
  ];
  for (final c in candidates) {
    final hit = c.hitTestable();
    if (hit.evaluate().isNotEmpty) {
      await t.tap(hit.last, warnIfMissed: false);
      await pumpMs(settleMs);
      return;
    }
  }
  await nav.maybePop();
  await pumpMs(settleMs);
}

/// System back without looking for a button (Android back / sheet barrier).
Future<void> systemBack({int settleMs = 400}) async {
  await nav.maybePop();
  await pumpMs(settleMs);
}

/// iOS edge swipe back (RTL: from the right edge towards the left).
Future<void> swipeBack() async {
  final size = t.view.physicalSize / t.view.devicePixelRatio;
  await t.timedDragFrom(
    Offset(size.width - 4, size.height / 2),
    Offset(-size.width * .75, 0),
    const Duration(milliseconds: 250),
  );
  await pumpMs(600);
}

/// Answers "לצאת בלי לשמור?" with leave when it is up.
Future<void> leaveIfAsked() async {
  final leave = find.byKey(const Key('discard-leave')).hitTestable();
  if (leave.evaluate().isNotEmpty) {
    await t.tap(leave.first, warnIfMissed: false);
    await pumpMs(400);
  }
  final discard = find.byKey(const Key('save-draft-discard')).hitTestable();
  if (discard.evaluate().isNotEmpty) {
    await t.tap(discard.first, warnIfMissed: false);
    await pumpMs(400);
  }
}

/// Back to the shell root (between sections), without counting as a step.
Future<void> toRoot() async {
  for (var i = 0; i < 8; i++) {
    final r = topRoute;
    if (r == null || r.isFirst) break;
    await nav.maybePop();
    await pumpMs(350);
    await leaveIfAsked();
    if (topRoute == r) {
      // PopScope said no and nothing to answer: force it.
      nav.pop();
      await pumpMs(350);
    }
  }
  await pumpMs(300);
}

Future<void> selectTab(AppTab tab) async {
  if (!await tapIf(
    find.byKey(Key('tab-${tab.name}')),
    what: 'tab ${tab.name}',
  )) {
    note('screen without tab ${tab.name}: ${describeScreen()}');
    currentTab.value = tab;
  }
  await pumpMs(450);
}

/// Top route + visible texts, for notes about where the sweep is.
String describeScreen() {
  final texts = find
      .byType(Text)
      .hitTestable()
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .whereType<String>()
      .take(12)
      .join(' | ');
  return 'route ${topRoute?.settings.name} (${topRoute.runtimeType}); $texts';
}

Future<void> step(String label, Future<void> Function() body) async {
  currentStep = label;
  // ignore: avoid_print
  print('SWEEP-STEP $label');
  try {
    await body();
  } on TestFailure catch (e, st) {
    note(
      'test helper failure: $e ${st.toString().split('\n').take(3).join(' | ')}',
    );
  } on Object catch (e, st) {
    record('step threw', e, st);
  }
  await pumpMs(150);
}

/// A valid Israeli business number (ח.פ.): 8 digits + check digit.
String validTaxId(Random rnd) {
  final digits = [5, 1, for (var i = 0; i < 6; i++) rnd.nextInt(10)];
  var sum = 0;
  for (var i = 0; i < 8; i++) {
    var d = digits[i] * (i.isEven ? 1 : 2);
    if (d > 9) d -= 9;
    sum += d;
  }
  final check = (10 - sum % 10) % 10;
  return [...digits, check].join();
}

// ---- sections ---------------------------------------------------------------------

Future<void> sweepTabs({int rounds = 3}) async {
  final tabs = [
    AppTab.home,
    if (businessContext.caps.showPeopleTab) AppTab.people,
    AppTab.business,
    AppTab.profile,
  ];
  await step('tabs: slow pass', () async {
    for (final tab in tabs) {
      await selectTab(tab);
      await pumpMs(500);
    }
  });
  await step('tabs: fast churn', () async {
    for (var r = 0; r < rounds; r++) {
      for (final tab in [...tabs, ...tabs.reversed]) {
        final f = find.byKey(Key('tab-${tab.name}')).hitTestable();
        if (f.evaluate().isNotEmpty) {
          await t.tap(f.first, warnIfMissed: false);
        }
        await t.pump(const Duration(milliseconds: 60));
      }
    }
    await pumpMs(800);
  });
  await selectTab(AppTab.home);
}

Future<void> fillCustomerForm(String name, String taxId) async {
  await waitFor(find.byKey(const Key('s2-name')));
  await t.enterText(find.byKey(const Key('s2-name')), name);
  await t.pump(const Duration(milliseconds: 100));
  await t.enterText(find.byKey(const Key('s2-phone')), '0501234567');
  await t.pump(const Duration(milliseconds: 100));
  await t.enterText(find.byKey(const Key('s2-taxid')), taxId);
  await t.pump(const Duration(milliseconds: 100));
  FocusManager.instance.primaryFocus?.unfocus();
  await pumpMs(300);
}

Future<String?> saveCustomerForm() async {
  final save = find.byKey(const Key('s2-save'));
  await t.ensureVisible(save);
  await pumpMs(200);
  await tapIf(save, what: 's2-save');
  // Until the form route is gone (pop with the saved customer).
  final end = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(end)) {
    await pumpMs(200);
    if (find.byKey(const Key('s2-save')).evaluate().isEmpty) return 'ok';
  }
  note('S2 save did not close the form');
  return null;
}

Future<void> sweepAddCustomerFromPeople(Random rnd) async {
  if (!businessContext.caps.showPeopleTab) return;
  final name = 'סוויפ ${DateTime.now().millisecondsSinceEpoch % 100000}';
  await step('people: open + לקוח, back without typing', () async {
    await selectTab(AppTab.people);
    await tapIf(find.byKey(const Key('people-add')), what: 'people-add');
    await pumpMs(500);
    await back();
  });
  await step('people: + לקוח, type, back → discard dialog → leave', () async {
    await tapIf(find.byKey(const Key('people-add')));
    await pumpMs(500);
    await waitFor(find.byKey(const Key('s2-name')));
    await t.enterText(find.byKey(const Key('s2-name')), 'זמני');
    await pumpMs(200);
    await back();
    await leaveIfAsked();
    await pumpMs(400);
  });
  await step('people: + לקוח, type, swipe back', () async {
    await tapIf(find.byKey(const Key('people-add')));
    await pumpMs(600);
    await waitFor(find.byKey(const Key('s2-name')));
    await t.enterText(find.byKey(const Key('s2-name')), 'זמני 2');
    FocusManager.instance.primaryFocus?.unfocus();
    await pumpMs(300);
    await swipeBack();
    await leaveIfAsked();
    await pumpMs(300);
    if (find.byKey(const Key('s2-name')).evaluate().isNotEmpty) await back();
    await leaveIfAsked();
  });
  await step(
    'people: + לקוח with the keyboard up, back while it is up',
    () async {
      await tapIf(find.byKey(const Key('people-add')));
      await pumpMs(400);
      t.view.viewInsets = const FakeViewPadding(bottom: 1008);
      await pumpMs(300);
      await back();
      await leaveIfAsked();
      await pumpMs(200);
      t.view.resetViewInsets();
      await pumpMs(500);
      await toRoot();
    },
  );
  await step('people: + לקוח, fill valid ח.פ., save', () async {
    await tapIf(find.byKey(const Key('people-add')));
    await pumpMs(500);
    await fillCustomerForm(name, validTaxId(rnd));
    await saveCustomerForm();
    await pumpMs(1200);
  });
  await step('people: after save: back, back again', () async {
    await back();
    await back();
    await pumpMs(600);
  });
  await step('people: reopen the new customer', () async {
    await selectTab(AppTab.people);
    final search = find.byKey(const Key('people-search'));
    if (await waitFor(search.hitTestable())) {
      await t.enterText(search, name);
      await pumpMs(800);
    }
    final row = find.ancestor(
      of: find.text(name),
      matching: find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('person-'),
      ),
    );
    if (await tapIf(row, what: 'new customer row')) {
      await pumpMs(2500);
      await back();
      await pumpMs(300);
      // and again, quickly: open → back before it loads
      await tapIf(row);
      await t.pump(const Duration(milliseconds: 120));
      await back(settleMs: 600);
    }
    final clear = find.byKey(const Key('people-search-clear')).hitTestable();
    if (clear.evaluate().isNotEmpty) await t.tap(clear.first);
    await pumpMs(300);
  });
  await step('people: save customer then immediately double back', () async {
    await tapIf(find.byKey(const Key('people-add')));
    await pumpMs(500);
    await fillCustomerForm('$name ב', validTaxId(rnd));
    final save = find.byKey(const Key('s2-save'));
    await t.ensureVisible(save);
    await pumpMs(150);
    await tapIf(save);
    await t.pump(const Duration(milliseconds: 30));
    // The user taps back twice while the save is still in flight.
    await systemBack(settleMs: 60);
    await systemBack(settleMs: 60);
    await pumpMs(3000);
    await leaveIfAsked();
    await toRoot();
  });
}

Future<void> sweepPersonCard() async {
  if (!businessContext.caps.showPeopleTab) return;
  await step('person card: open first customer', () async {
    await selectTab(AppTab.people);
    final rows = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          RegExp(
            r'^person-[0-9a-f-]{8,}$',
          ).hasMatch((w.key! as ValueKey<String>).value),
    );
    if (!await tapIf(rows, what: 'a person row')) return;
    await pumpMs(2500);
  });
  if (find.byKey(const Key('person-crm')).evaluate().isEmpty &&
      find.byKey(const Key('person-edit')).evaluate().isEmpty) {
    note('person card not open (no CRM / edit)');
    await toRoot();
    return;
  }
  await step('person card: CRM tabs', () async {
    for (final i in [1, 2, 0, 2, 1, 0]) {
      final f = find.byKey(Key('crm-section-$i'));
      if (f.evaluate().isNotEmpty) {
        await t.ensureVisible(f);
        await t.tap(f, warnIfMissed: false);
        await pumpMs(200);
      }
    }
  });
  await step('person card: new job dialog open/close', () async {
    if (await tapIf(find.byKey(const Key('crm-add-job')))) {
      await pumpMs(500);
      await systemBack();
      await leaveIfAsked();
    }
  });
  await step('person card: new job dialog, type, cancel', () async {
    if (await tapIf(find.byKey(const Key('crm-add-job')))) {
      await pumpMs(500);
      final title = find.byKey(const Key('crm-work-title'));
      if (title.evaluate().isNotEmpty) {
        await t.enterText(title, 'עבודה זמנית');
        await pumpMs(200);
      }
      await systemBack();
      await leaveIfAsked();
      await pumpMs(300);
    }
  });
  await step('person card: note dialog open/close', () async {
    if (await tapIf(find.text('פתק חדש'), what: 'פתק חדש')) {
      await pumpMs(400);
      await systemBack();
      await leaveIfAsked();
    }
  });
  await step('person card: note add (save)', () async {
    if (await tapIf(find.text('פתק חדש'))) {
      await pumpMs(400);
      await t.enterText(find.byKey(const Key('crm-note-text')), 'פתק סוויפ');
      await pumpMs(200);
      await tapIf(find.byKey(const Key('crm-note-save')));
      await pumpMs(1200);
    }
  });
  await step('person card: reminder dialog open/close', () async {
    if (await tapIf(find.text('תזכורת'), what: 'תזכורת')) {
      await pumpMs(400);
      await systemBack();
      await leaveIfAsked();
    }
  });
  await step('person card: stage menu open/close', () async {
    final stage = find.byTooltip('מצב הלקוח');
    if (await tapIf(stage, what: 'stage menu')) {
      await pumpMs(400);
      await systemBack();
    }
  });
  await step(
    'person card: follow-up tomorrow → board → tap it opens a card',
    () async {
      final name = (find.byType(PersonScreen).evaluate().isEmpty)
          ? null
          : t.state<State>(find.byType(PersonScreen)).widget.toStringShort();
      await tapIf(find.byKey(const Key('crm-section-1')));
      await pumpMs(300);
      if (!await tapIf(find.byKey(const Key('crm-follow-tomorrow')))) return;
      await pumpMs(1500);
      if (!await tapIf(find.text('לוח העסק'), what: 'לוח העסק')) return;
      await pumpMs(1500);
      await tapIf(find.byKey(const Key('crm-board-2')), what: 'board מעקבים');
      await pumpMs(500);
      final rows = find.byWidgetPredicate(
        (w) => w is ListTile && w.onTap != null,
      );
      final cardsBefore = find.byType(PersonScreen).evaluate().length;
      if (await tapIf(rows, what: 'board reminder row (${name ?? ''})')) {
        await pumpMs(1500);
        final cardsAfter = find.byType(PersonScreen).evaluate().length;
        if (cardsAfter <= cardsBefore) {
          record(
            'dead tap',
            'tapping a follow-up on לוח מעקב opened no customer card',
            null,
          );
        } else {
          await back();
        }
      }
      await back();
      await pumpMs(400);
    },
  );
  await step('person card: edit (S2 edit) open/back', () async {
    if (await tapIf(find.byKey(const Key('person-edit')))) {
      await pumpMs(600);
      await back();
      await leaveIfAsked();
    }
  });
  await step('person card: edit, save unchanged', () async {
    if (await tapIf(find.byKey(const Key('person-edit')))) {
      await pumpMs(600);
      final save = find.byKey(const Key('s2-save'));
      if (save.evaluate().isNotEmpty) {
        await t.ensureVisible(save);
        await pumpMs(150);
        await tapIf(save);
        await pumpMs(2000);
      }
      if (find.byKey(const Key('s2-save')).evaluate().isNotEmpty) await back();
      await leaveIfAsked();
    }
  });
  await step('person card: ⋯ menu open/close', () async {
    final more = find.byTooltip('עוד');
    if (await tapIf(more, waitMs: 1500, what: '⋯')) {
      await pumpMs(400);
      await systemBack();
    }
  });
  await step('person card: compose from card, X', () async {
    if (await tapIf(find.byKey(const Key('person-primary')))) {
      await pumpMs(1500);
      await back();
      await leaveIfAsked();
    }
  });
  await step('person card: swipe back to list', () async {
    await swipeBack();
    await pumpMs(400);
  });
  await toRoot();
}

Future<void> sweepCompose(Random rnd) async {
  if (!businessContext.caps.showCreateTab) return;
  await step('compose: open, back from picker', () async {
    await tapIf(find.byKey(const Key('tab-create')), what: 'tab-create');
    await pumpMs(900);
    await back();
    await pumpMs(600);
  });
  await step('compose: open, swipe back from picker', () async {
    await tapIf(find.byKey(const Key('tab-create')));
    await pumpMs(900);
    await swipeBack();
    await pumpMs(600);
    await toRoot();
  });
  await step('compose: open and X before it loads', () async {
    await tapIf(find.byKey(const Key('tab-create')));
    await t.pump(const Duration(milliseconds: 80));
    await systemBack(settleMs: 80);
    await systemBack(settleMs: 600);
    await toRoot();
  });
  await step('compose: pick existing customer, type, X', () async {
    await tapIf(find.byKey(const Key('tab-create')));
    await pumpMs(1200);
    final row = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          RegExp(
            r'^s2-(row|recent)-',
          ).hasMatch((w.key! as ValueKey<String>).value),
    );
    if (await tapIf(row, what: 'S2 row')) {
      await pumpMs(1500);
      for (final d in ['1', '2', '0']) {
        final k = find.text(d).hitTestable();
        if (k.evaluate().isNotEmpty) {
          await t.tap(k.last, warnIfMissed: false);
          await t.pump(const Duration(milliseconds: 80));
        }
      }
      await pumpMs(400);
      await tapIf(find.byKey(const Key('compose-close')));
      await pumpMs(500);
      // "לשמור טיוטה?" → discard
      await leaveIfAsked();
      await pumpMs(500);
    }
    await toRoot();
  });
  await step('compose: reopen (leftover draft dialog?), back', () async {
    await tapIf(find.byKey(const Key('tab-create')));
    await pumpMs(1500);
    final resumeNew = find.byKey(const Key('resume-draft-new')).hitTestable();
    if (resumeNew.evaluate().isNotEmpty) {
      await t.tap(resumeNew.first);
      await pumpMs(600);
    }
    await back();
    await pumpMs(600);
    await toRoot();
  });
  await step('compose: picker → + לקוח חדש → save → compose', () async {
    await tapIf(find.byKey(const Key('tab-create')));
    await pumpMs(1200);
    if (await tapIf(find.byKey(const Key('s2-new')), what: 's2-new')) {
      await pumpMs(500);
      await fillCustomerForm(
        'סוויפ קומפוזר ${DateTime.now().millisecondsSinceEpoch % 100000}',
        validTaxId(rnd),
      );
      await saveCustomerForm();
      await pumpMs(1500);
      // Change the customer from the chip, back from the picker.
      if (await tapIf(find.byKey(const Key('compose-customer')))) {
        await pumpMs(800);
        await back();
        await pumpMs(500);
      }
      await tapIf(find.byKey(const Key('compose-close')));
      await pumpMs(500);
      await leaveIfAsked();
    }
    await toRoot();
  });
  await step('compose: picker → + לקוח חדש → back to page 1 → back', () async {
    await tapIf(find.byKey(const Key('tab-create')));
    await pumpMs(1200);
    if (await tapIf(find.byKey(const Key('s2-new')))) {
      await pumpMs(400);
      await back();
      await pumpMs(300);
      await back();
      await pumpMs(700);
    }
    await toRoot();
  });
  await step('compose: intent buttons on home, back', () async {
    await selectTab(AppTab.home);
    for (final k in ['intent-paid', 'intent-request']) {
      if (await tapIf(find.byKey(Key(k)), waitMs: 2500, what: k)) {
        await pumpMs(1000);
        await back();
        await pumpMs(600);
        await toRoot();
      }
    }
  });
}

Future<void> sweepDocument() async {
  await step('document: open from home', () async {
    await selectTab(AppTab.home);
    await pumpMs(1500);
    final doc = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          RegExp(
            r'^doc-[0-9a-f]{8}-',
          ).hasMatch((w.key! as ValueKey<String>).value),
    );
    if (!await tapIf(doc, what: 'home doc row')) {
      // via activity
      if (await tapIf(find.byKey(const Key('home-all-activity')))) {
        await pumpMs(1500);
        await tapIf(doc, what: 'activity doc row');
      }
    }
    await pumpMs(2500);
  });
  if (find.byKey(const Key('doc-status-line')).evaluate().isEmpty &&
      find.byKey(const Key('doc-primary')).evaluate().isEmpty &&
      find.byKey(const Key('doc-lines')).evaluate().isEmpty) {
    note('document screen not reached');
    await toRoot();
    return;
  }
  await step('document: secondary action sheet open/dismiss', () async {
    if (await tapIf(find.byKey(const Key('doc-secondary')), waitMs: 1500)) {
      await pumpMs(900);
      await systemBack();
      await leaveIfAsked();
      await pumpMs(400);
    }
  });
  await step('document: primary action sheet open/dismiss', () async {
    if (await tapIf(find.byKey(const Key('doc-primary')), waitMs: 1500)) {
      await pumpMs(900);
      // Only dismiss what opened (never confirm a send / payment).
      if (!(topRoute?.isFirst ?? true) && topRoute is PopupRoute) {
        await systemBack();
      }
      await leaveIfAsked();
      await pumpMs(400);
    }
  });
  await step('document: ⋯ menu, each item opened and dismissed', () async {
    final more = find.byTooltip('עוד');
    if (!await tapIf(more, waitMs: 1500, what: 'doc ⋯')) return;
    await pumpMs(500);
    final labels = <String>[];
    final rows = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(Text),
    );
    for (final e in rows.evaluate()) {
      final s = (e.widget as Text).data;
      if (s != null) labels.add(s);
    }
    await systemBack();
    note('doc ⋯ items: ${labels.join(' | ')}');
    for (final label in labels) {
      // Opening these must never commit: skip one-tap actions.
      if (RegExp(
        r'שכפל|דחה|סמן|הנפק|הפק|שלח תזכורת|וואטסאפ|WhatsApp',
      ).hasMatch(label)) {
        continue;
      }
      if (!await tapIf(more, waitMs: 1500)) break;
      await pumpMs(400);
      if (!await tapIf(find.text(label), what: '⋯ $label')) {
        await systemBack();
        continue;
      }
      await pumpMs(1000);
      if (!(topRoute?.isFirst ?? true) && topRoute is PopupRoute) {
        await systemBack();
      } else if (topRoute is PageRoute &&
          find
              .byKey(const Key('doc-status-line'))
              .hitTestable()
              .evaluate()
              .isEmpty) {
        await back();
      }
      await leaveIfAsked();
      await pumpMs(500);
    }
  });
  await step('document: PDF open/back', () async {
    if (await tapIf(find.byKey(const Key('doc-pdf')), waitMs: 1500)) {
      await pumpMs(1500);
      await back();
    }
  });
  await step('document: double back', () async {
    await systemBack(settleMs: 40);
    await systemBack(settleMs: 600);
  });
  await toRoot();
}

Future<void> sweepBusiness() async {
  await step('management: tab', () async {
    await selectTab(AppTab.business);
    await pumpMs(800);
  });
  Iterable<String> keysWithPrefix(String prefix) => find
      .byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith(prefix),
      )
      .evaluate()
      .map((e) => (e.widget.key! as ValueKey<String>).value)
      .toSet();

  final actions = keysWithPrefix('management-action-').toList();
  for (final k in actions) {
    await step('management: quick action $k open/back', () async {
      await selectTab(AppTab.business);
      if (!await tapIf(find.byKey(Key(k)), what: k)) return;
      await pumpMs(1300);
      if (k.endsWith('-more')) {
        await systemBack();
        return;
      }
      await back();
      await leaveIfAsked();
      await pumpMs(500);
      await toRoot();
    });
  }
  // Rows below the fold are built only once scrolled to.
  final all = <String>{...keysWithPrefix('brow-')};
  for (var i = 0; i < 6; i++) {
    final lists = find
        .byWidgetPredicate(
          (w) =>
              w is Scrollable &&
              axisDirectionToAxis(w.axisDirection) == Axis.vertical,
        )
        .hitTestable();
    if (lists.evaluate().isEmpty) break;
    await t.drag(lists.last, const Offset(0, -300), warnIfMissed: false);
    await pumpMs(200);
    all.addAll(keysWithPrefix('brow-'));
  }
  note('management rows: $all');
  final rows = all.where((k) => k != 'brow-reminders');
  for (final k in rows.toList()) {
    await step('management: row $k open/back', () async {
      await selectTab(AppTab.business);
      if (!await tapIf(find.byKey(Key(k)), what: k)) return;
      await pumpMs(1500);
      if (k == 'brow-more') {
        final sub = keysWithPrefix('brow-').toList();
        note('עוד הגדרות rows: $sub');
        for (final s in sub) {
          await step('עוד הגדרות: $s open/back', () async {
            if (!await tapIf(find.byKey(Key(s)), what: s)) return;
            await pumpMs(1500);
            if (topRoute is PopupRoute) {
              await systemBack();
            } else {
              await back();
            }
            await leaveIfAsked();
            await pumpMs(500);
          });
        }
      }
      if (topRoute is PopupRoute) {
        await systemBack();
      } else {
        await back();
      }
      await leaveIfAsked();
      await pumpMs(400);
      await toRoot();
    });
    await step('management: row $k open → back before load', () async {
      await selectTab(AppTab.business);
      if (!await tapIf(find.byKey(Key(k)))) return;
      await t.pump(const Duration(milliseconds: 100));
      await systemBack(settleMs: 50);
      await systemBack(settleMs: 600);
      await leaveIfAsked();
      await toRoot();
    });
  }
}

Future<void> sweepReportsExpenses() async {
  await step('reports: open each report card and back', () async {
    if (businessContext.caps.homeIsReports) {
      await selectTab(AppTab.home);
    } else {
      await selectTab(AppTab.business);
      if (!await tapIf(
        find.byKey(const Key('brow-reports')),
        what: 'reports',
      )) {
        return;
      }
    }
    await pumpMs(2000);
    final cards = find
        .byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('report-card-'),
        )
        .evaluate()
        .map((e) => (e.widget.key! as ValueKey<String>).value)
        .toList();
    note('report cards: $cards');
    for (final c in cards) {
      currentStep = 'reports: $c';
      if (!await tapIf(find.byKey(Key(c)), what: c)) continue;
      await pumpMs(1800);
      await back();
      await pumpMs(500);
      // Quick: open and back before the report loads.
      if (await tapIf(find.byKey(Key(c)))) {
        await t.pump(const Duration(milliseconds: 100));
        await back(settleMs: 600);
      }
    }
    await toRoot();
  });
  await step('expenses: open and back', () async {
    await selectTab(AppTab.business);
    if (await tapIf(find.byKey(const Key('brow-expenses')), what: 'expenses')) {
      await pumpMs(2000);
      final row = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('expense-row-'),
      );
      if (await tapIf(row, waitMs: 1500, what: 'expense row')) {
        await pumpMs(1500);
        await back();
      }
      await back();
    }
    await toRoot();
  });
}

Future<void> sweepProfile() async {
  await step('profile: tab, switch to settings and back', () async {
    await selectTab(AppTab.profile);
    await pumpMs(800);
    for (var i = 0; i < 3; i++) {
      await tapIf(find.text('הגדרות'), waitMs: 1500, what: 'הגדרות');
      await pumpMs(400);
      await tapIf(find.text('פרופיל'), waitMs: 1500);
      await pumpMs(400);
    }
  });
  await step('profile: plan CTA open/back', () async {
    if (await tapIf(find.byKey(const Key('profile-plan-cta')), waitMs: 1500)) {
      await pumpMs(1500);
      if (topRoute is PopupRoute) {
        await systemBack();
      } else {
        await back();
      }
    }
    await toRoot();
  });
}

Future<void> sweepSwitchBusiness() async {
  if (!businessContext.hasManyBusinesses) {
    await step('switch business: n/a (one business)', () async {});
    return;
  }
  await step('switch business: sheet open/close', () async {
    await selectTab(AppTab.business);
    if (await tapIf(
      find.byKey(const Key('business-name')),
      what: 'business-name',
    )) {
      await pumpMs(800);
      await systemBack();
    }
  });
  await step('switch business: switch and back', () async {
    final original = businessContext.business?.businessId;
    for (var i = 0; i < 2; i++) {
      await selectTab(AppTab.business);
      if (!await tapIf(
        find.byKey(const Key('business-name')),
        what: 'business-name',
      )) {
        return;
      }
      await pumpMs(800);
      final rows = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            RegExp(
              r'^s14-[0-9a-f]{8}-',
            ).hasMatch((w.key! as ValueKey<String>).value) &&
            (w.key! as ValueKey<String>).value !=
                's14-${businessContext.business?.businessId}',
      );
      final target = i == 0 ? rows : find.byKey(Key('s14-$original'));
      if (!await tapIf(target, what: 's14 target')) {
        await systemBack();
        return;
      }
      await pumpMs(3000);
      await selectTab(AppTab.home);
      await pumpMs(1000);
      if (businessContext.caps.showPeopleTab) await selectTab(AppTab.people);
      await pumpMs(800);
    }
  });
}

/// Background → (real time passes, no frames: a paused app gets none, and
/// pumping then would wait forever) → resume. Async work started before
/// (loads, timers) completes while paused, as on a phone.
Future<void> backgroundAndResume({int awayMs = 1500}) async {
  final b = t.binding;
  b.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  await pumpMs(100);
  b.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  b.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await Future<void>.delayed(Duration(milliseconds: awayMs));
  b.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  b.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  b.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await pumpMs(1500);
}

Future<void> sweepLifecycle() async {
  await step('lifecycle: background/resume on home', () async {
    await selectTab(AppTab.home);
    await backgroundAndResume();
    await backgroundAndResume(awayMs: 300);
  });
  await step('lifecycle: background/resume with S2 open', () async {
    if (businessContext.caps.showPeopleTab) {
      await selectTab(AppTab.people);
      await tapIf(find.byKey(const Key('people-add')));
      await pumpMs(500);
    }
    await backgroundAndResume();
    await back();
    await leaveIfAsked();
    await toRoot();
  });
  await step('lifecycle: background while the Composer loads', () async {
    if (!businessContext.caps.showCreateTab) return;
    await tapIf(find.byKey(const Key('tab-create')));
    await t.pump(const Duration(milliseconds: 50));
    await backgroundAndResume(awayMs: 2500);
    await back();
    await toRoot();
  });
}

Future<void> sweepHomeChurn() async {
  await step('home: open activity and back ×3 quickly', () async {
    await selectTab(AppTab.home);
    for (var i = 0; i < 3; i++) {
      if (await tapIf(
        find.byKey(const Key('home-all-activity')),
        waitMs: 2000,
      )) {
        await t.pump(const Duration(milliseconds: 150));
        await back(settleMs: 200);
      }
    }
    await pumpMs(800);
    await toRoot();
  });
  await step('home: inbox summary / money card open/back', () async {
    for (final k in ['home-inbox-summary', 'home-money']) {
      if (await tapIf(find.byKey(Key(k)), waitMs: 1500, what: k)) {
        await pumpMs(1200);
        await back();
        await toRoot();
      }
    }
  });
  await step('home: pull to refresh', () async {
    final list = find.byKey(const Key('home-list'));
    if (list.evaluate().isNotEmpty) {
      await t.fling(list, const Offset(0, 400), 1200);
      await pumpMs(2500);
    }
  });
}

// ---- the test ---------------------------------------------------------------------------

Future<void> runGuarded(
  WidgetTester tester,
  String email,
  Future<void> Function() body,
) async {
  t = tester;
  final originalOnError = FlutterError.onError;
  final originalPlatformOnError = PlatformDispatcher.instance.onError;
  FlutterError.onError = (d) {
    // Layout errors carry no useful stack: keep the "error-causing widget"
    // lines (file:line of the widget) instead.
    final where = d
        .toString()
        .split('\n')
        .where((l) => l.contains('file:///') || l.contains('relevant'))
        .take(6)
        .join('\n');
    record(
      'FlutterError${d.library == null ? '' : ' (${d.library})'}',
      '${d.exceptionAsString()}${where.isEmpty ? '' : '\n$where'}',
      d.stack,
    );
  };
  PlatformDispatcher.instance.onError = (e, st) {
    record('PlatformDispatcher', e, st);
    return true;
  };
  final done = Completer<void>();
  runZonedGuarded(() async {
    try {
      currentStep = '$email: launch';
      await launchSignedInAs(tester, email);
      if (!await waitFor(find.byKey(const Key('tab-home')), ms: 30000)) {
        final top = topRoute?.settings.name;
        final texts = find
            .byType(Text)
            .hitTestable()
            .evaluate()
            .map((e) => (e.widget as Text).data)
            .whereType<String>()
            .take(12)
            .join(' | ');
        note('no shell after launch: top route $top; on screen: $texts');
      }
      await pumpMs(1500);
      await body();
    } on Object catch (e, st) {
      record('sweep aborted', e, st);
    } finally {
      done.complete();
    }
  }, (e, st) => record('uncaught async', e, st));
  await done.future;
  // Let late async errors land in this run.
  await pumpMs(1500);
  FlutterError.onError = originalOnError;
  PlatformDispatcher.instance.onError = originalPlatformOnError;
}

/// URLs / share sheets the sweep opened (never really opened: leaving the
/// app for WhatsApp or the share sheet stops the frames the test pumps).
final List<String> externalOpens = [];

/// --dart-define=SWEEP_ROLES=owner-only | others-only (default: all three).
const String onlyRoles = String.fromEnvironment('SWEEP_ROLES');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Plans screen / sheet (no subscription on staging) closed like a user's X.
  dismissPlansDuringTests();
  urlOpener = (uri, {inApp = false}) async {
    externalOpens.add('$uri');
    return true;
  };
  pdfSharer = (bytes, name, {text}) async => externalOpens.add('pdf $name');
  textSharer = (text) async => externalOpens.add('text');

  testWidgets(
    'crash sweep: owner, employee, viewer',
    (tester) async {
      final rnd = Random();
      if (onlyRoles != 'others-only') {
        await runGuarded(tester, ownerEmail, () async {
          await sweepTabs();
          await sweepAddCustomerFromPeople(rnd);
          await sweepPersonCard();
          await sweepCompose(rnd);
          await sweepDocument();
          await sweepBusiness();
          await sweepReportsExpenses();
          await sweepProfile();
          await sweepHomeChurn();
          await sweepSwitchBusiness();
          await sweepLifecycle();
          await sweepTabs(rounds: 2);
        });
      }

      for (final who in [
        if (onlyRoles != 'owner-only') ...[
          'mobile-employee@tevel.test',
          'mobile-viewer@tevel.test',
        ],
      ]) {
        await runGuarded(tester, who, () async {
          await sweepTabs(rounds: 2);
          await sweepAddCustomerFromPeople(rnd);
          await sweepCompose(rnd);
          await sweepDocument();
          await sweepBusiness();
          await sweepProfile();
          await sweepLifecycle();
        });
      }
      await session.signOutLocally();
      await tester.pump(const Duration(milliseconds: 500));

      // ignore: avoid_print
      print(
        'SWEEP-SUMMARY notes=${sweepNotes.length} errors=${sweepErrors.length} '
        'external=${externalOpens.length}',
      );
      for (final n in sweepNotes) {
        // ignore: avoid_print
        print('  note $n');
      }
      if (sweepErrors.isNotEmpty) {
        fail(
          '${sweepErrors.length} error(s) during the sweep:\n\n'
          '${sweepErrors.join('\n\n')}',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 40)),
  );
}
