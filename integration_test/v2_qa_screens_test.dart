// QA · screenshots of every main V2 screen (SPEC-v2 §5) against the LOCAL dev
// API (never prod). Signs in as the dev owner preset (e-mail code from the dev
// mail folder), opens each screen through the router and prints `SHOT:<name>`
// while holding the frame, so the runner can take `simctl io screenshot`:
//
//   ~/flutter/bin/flutter test integration_test/v2_qa_screens_test.dart -d <udid> \
//     --dart-define=API_BASE=http://127.0.0.1:3031 \
//     --dart-define=MAILDIR=$HOME/invoiceproject-mobile-dev-storage/outgoing-emails 2>&1 |
//   while read -r l; do echo "$l"; [[ $l == *SHOT:* ]] && \
//     xcrun simctl io <udid> screenshot docs/screenshots/v2/qa-${l##*SHOT:}.png; done
//
// ignore_for_file: use_build_context_synchronously (navigatorKey context, test driver)
// Read-only: it creates nothing on the server (Composer screens are only opened).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/app_shell.dart';
import 'package:invoice/main.dart' as app;
import 'package:invoice/router.dart';
import 'package:invoice/screens/auth/mfa_sheet.dart';
import 'package:invoice/screens/business/sheets/s13_editor.dart';
import 'package:invoice/screens/business/sheets/s14_switch.dart';
import 'package:invoice/screens/document/sheets/s5_payment.dart';
import 'package:invoice/screens/document/sheets/s6_share.dart';
import 'package:invoice/screens/document/sheets/s8_cancel.dart';
import 'package:invoice/ui/widgets/keypad.dart';
import 'package:invoice/state/session.dart';
import 'qa_plans_guard.dart';

const email = String.fromEnvironment(
  'EMAIL',
  defaultValue: 'mobile-owner@tevel.test',
);
const mailDir = String.fromEnvironment('MAILDIR');
const password = 'Mobile12345678';

Future<void> pumpFor(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> shot(WidgetTester tester, String name) async {
  await pumpFor(tester, const Duration(seconds: 3));
  debugPrint('SHOT:$name');
  await pumpFor(tester, const Duration(seconds: 4));
}

String? latestCode(String to, DateTime since) {
  final dir = Directory(mailDir);
  if (mailDir.isEmpty || !dir.existsSync()) return null;
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
        );
  for (final f in files) {
    if (f.statSync().modified.isBefore(since)) break;
    final m = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final subject = '${m['subject']}';
    if (m['to'] == to && RegExp(r'^\d{6}').hasMatch(subject))
      return subject.substring(0, 6);
  }
  return null;
}

BuildContext get ctx => navigatorKey.currentContext!;

Future<void> back(WidgetTester tester) async {
  navigatorKey.currentState!.popUntil((r) => r.isFirst);
  await pumpFor(tester, const Duration(seconds: 1));
}

Future<String?> firstId(
  String path,
  String key,
  bool Function(Map<String, dynamic>) where,
) async {
  try {
    final json = await ApiClient.instance.get(path);
    for (final r in (json[key] as List? ?? const [])) {
      final m = r as Map<String, dynamic>;
      if (where(m)) return '${m['id']}';
    }
  } on Object catch (e) {
    debugPrint('QA-SCREENS: $path failed: $e');
  }
  return null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  dismissPlansDuringTests();

  testWidgets('V2 main screens ($email)', (tester) async {
    const storage = FlutterSecureStorage();
    final stale = await storage.read(key: 'device_token');
    if (stale != null) {
      ApiClient.instance.deviceToken = stale;
      try {
        await ApiClient.instance.post('/mobile/logout');
      } on ApiException {
        // already revoked
      }
      ApiClient.instance.clearCredentials();
    }
    await storage.deleteAll();

    app.main();
    final loginButton = find.text('כניסה');
    for (var i = 0; i < 150 && loginButton.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(loginButton, findsOneWidget);
    await shot(tester, '01-login');

    await tester.enterText(find.byType(TextField).at(0), email);
    await tester.enterText(find.byType(TextField).at(1), password);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 500));
    final since = DateTime.now().subtract(const Duration(seconds: 2));
    await tester.ensureVisible(loginButton);
    await tester.tap(loginButton);

    var mfaDone = false;
    for (var i = 0; i < 300 && find.byType(AppShell).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (!mfaDone && find.byType(MfaSheet).evaluate().isNotEmpty) {
        String? code;
        for (var j = 0; j < 50 && code == null; j++) {
          await pumpFor(tester, const Duration(milliseconds: 300));
          code = latestCode(email, since);
        }
        expect(code, isNotNull, reason: 'no MFA e-mail for $email in $mailDir');
        await shot(tester, '02-mfa');
        final field = find.descendant(
          of: find.byType(CodeBoxes),
          matching: find.byType(TextField),
        );
        await tester.enterText(field, code!);
        mfaDone = true;
      }
      if (find.byType(SwitchBusinessSheet).evaluate().isNotEmpty) {
        await shot(tester, '03-s14-switch');
        final rows = find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('s14-3b773037'),
        );
        await tester.tap(rows.first, warnIfMissed: false);
      }
    }
    expect(find.byType(AppShell), findsOneWidget);
    await pumpFor(tester, const Duration(seconds: 4));
    await shot(tester, '04-home');

    await tester.tap(find.byKey(const Key('tab-create')));
    await shot(tester, '05-s1-create');
    await back(tester);

    unawaited(openActivity(ctx));
    await shot(tester, '06-activity');
    await back(tester);

    // C opens on S2 (no customer yet); "לקוח מזדמן" (already on dev, so
    // nothing is created) shows C itself.
    Future<void> composeShots(String intent, String name) async {
      unawaited(openCompose(ctx, intent: intent));
      await pumpFor(tester, const Duration(seconds: 2));
      final walkIn = find.byKey(const Key('s2-walkin'));
      if (walkIn.evaluate().isNotEmpty) {
        if (intent == 'PAID') await shot(tester, '07a-s2-customer');
        await tester.tap(walkIn);
      }
      await shot(tester, name);
      if (intent == 'PAID') {
        // An amount (typed, never submitted) reveals the summary with "פרטים נוספים".
        for (final ch in '1180'.split('')) {
          final key = find.descendant(
            of: find.byType(Keypad),
            matching: find.text(ch),
          );
          if (key.evaluate().isNotEmpty) await tester.tap(key.first);
          await tester.pump(const Duration(milliseconds: 80));
        }
        await pumpFor(tester, const Duration(milliseconds: 600));
      }
      final more = find.byKey(const Key('compose-more-details'));
      if (intent == 'PAID' && more.evaluate().isNotEmpty) {
        await tester.ensureVisible(more.first);
        await tester.tap(more.first);
        await shot(tester, '07b-s3-more');
      }
      await back(tester);
    }

    await composeShots('PAID', '07-compose-paid');
    await composeShots('REQUEST', '08-compose-request');

    final docId = await firstId(
      '/documents',
      'documents',
      (m) =>
          m['documentType'] == 'TAX_INVOICE_RECEIPT' && m['status'] != 'DRAFT',
    );
    if (docId != null) {
      unawaited(openDocument(ctx, docId));
      await shot(tester, '09-document');
      await back(tester);
    }
    final quoteId = await firstId('/quotes', 'quotes', (_) => true);
    if (quoteId != null) {
      unawaited(openQuote(ctx, quoteId));
      await shot(tester, '10-quote');
      await back(tester);
    }

    // S5 / S6 / S8 over an open חשבונית מס (opened only; nothing is submitted).
    final openId = await firstId(
      '/documents?limit=200',
      'documents',
      (m) =>
          const {'FINALIZED', 'ARCHIVED', 'SENT'}.contains(m['status']) &&
          m['documentType'] == 'TAX_INVOICE' &&
          (num.tryParse('${m['openMinor'] ?? 0}') ?? 0) > 0,
    );
    if (openId != null) {
      for (final (name, open) in <(String, Future<Object?> Function())>[
        ('09b-s5-payment', () => showPaymentSheet(ctx, documentId: openId)),
        ('09c-s6-share', () => showShareSheet(ctx, documentId: openId)),
        ('09d-s8-cancel', () => showCancelSheet(ctx, documentId: openId)),
      ]) {
        unawaited(openDocument(ctx, openId));
        await pumpFor(tester, const Duration(seconds: 3));
        unawaited(open());
        await shot(tester, name);
        await back(tester);
      }
    }

    await tester.tap(find.byKey(const Key('tab-people')));
    await shot(tester, '11-people');
    final customerId = await firstId('/customers', 'customers', (_) => true);
    if (customerId != null) {
      unawaited(openPerson(ctx, customerId));
      await shot(tester, '12-person');
      await back(tester);
    }

    unawaited(openExpenses(ctx));
    await shot(tester, '13-expenses');
    await back(tester);

    unawaited(openReports(ctx));
    await shot(tester, '14-reports');
    await back(tester);
    for (final k in ['income', 'payments']) {
      unawaited(openReport(ctx, k));
      await shot(tester, '14-report-$k');
      await back(tester);
    }

    await tester.tap(find.byKey(const Key('tab-business')));
    await shot(tester, '15-business');
    for (final s in [
      BusinessSection.team,
      BusinessSection.profile,
      BusinessSection.branding,
      BusinessSection.approvals,
      BusinessSection.shaam,
      BusinessSection.account,
      BusinessSection.desktop,
    ]) {
      unawaited(openBusinessSection(ctx, s));
      await shot(tester, '16-business-${s.name}');
      await back(tester);
    }

    unawaited(showEditorSheet(ctx, instance: '13.1'));
    await shot(tester, '17-s13-editor');
    await back(tester);

    await tester.tap(find.byKey(const Key('tab-home')));
    await pumpFor(tester, const Duration(seconds: 1));
    await session.signOut(); // revokes the dev device token
  });
}
