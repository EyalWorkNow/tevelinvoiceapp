// B1 (QA 2026-11-16, persona 04 pain 3 / persona 05 pain 4): the cashier
// preset ("קופאי/ת") and the office manager (payment:record without
// finalize) — caps mapping, approval by cap, the team editors and the
// cashier's Home.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/inbox_api.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/app_shell.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/business/team_page.dart';
import 'package:invoice/screens/home/home_controller.dart';
import 'package:invoice/screens/home/home_screen.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/theme.dart';
import 'package:invoice/util/composer_config.dart';
import 'package:invoice/util/intent_resolver.dart';
import 'package:invoice/util/labels/labels.dart';

import 'business/e_harness.dart';
import 'fakes/fake_api.dart';

Caps capsOf(Preset p, {Map<String, dynamic>? policy, bool gated = false}) =>
    Caps.fromMe(
      Me.fromJson(meJson(p, approvalPolicy: policy, readGating: gated)),
    );

void main() {
  group('caps (lib/state/caps.dart)', () {
    test(
      'CASHIER: receipt with payment, no issue / money / reports / cancel',
      () {
        for (final gated in [false, true]) {
          final c = capsOf(Preset.cashier, gated: gated);
          expect(c.preset, Preset.cashier);
          expect(c.isCashier, isTrue);
          expect(c.homeIsCashier, isTrue);
          expect(c.can(Cap.paymentIssue), isTrue);
          for (final cap in [
            Cap.docIssue,
            Cap.paymentRecord,
            Cap.moneyView,
            Cap.reportView,
            Cap.reportExport,
            Cap.docCancel,
            Cap.approvalDecide,
            Cap.customerManage,
            Cap.settingsBusiness,
            Cap.teamManage,
            Cap.expenseCapture,
          ]) {
            expect(c.can(cap), isFalse, reason: '$cap gated=$gated');
          }
          // No "בקש תשלום" on the cashier's Home.
          expect(c.showIntentButtons, isFalse);
        }
      },
    );

    test(
      'office manager: records payments on existing docs, issues nothing',
      () {
        final c = capsOf(Preset.officeManager, gated: true);
        expect(c.preset, Preset.officeManager);
        expect(c.can(Cap.paymentRecord), isTrue);
        expect(c.can(Cap.moneyView), isTrue);
        expect(c.can(Cap.docIssue), isFalse);
        expect(c.can(Cap.paymentIssue), isFalse);
        expect(c.isCashier, isFalse);
      },
    );

    test('self-issuing employee and owner keep both payment caps', () {
      for (final p in [Preset.owner, Preset.employeeIssuer]) {
        final c = capsOf(p);
        expect(c.can(Cap.paymentRecord), isTrue, reason: '$p');
        expect(c.can(Cap.paymentIssue), isTrue, reason: '$p');
        expect(c.isCashier, isFalse, reason: '$p');
      }
    });

    test(
      'cashier approval: paid docs up to the cap (incl.) issue directly',
      () {
        final c = capsOf(Preset.cashier);
        expect(c.approvalPolicy.cashierCapMinor, BigInt.from(200000));
        expect(c.approvalNeeded(BigInt.from(12000), paid: true), isFalse);
        expect(c.approvalNeeded(BigInt.from(200000), paid: true), isFalse);
        expect(c.approvalNeeded(BigInt.from(200001), paid: true), isTrue);
        // A 305 / 300 always goes to the owner.
        expect(c.approvalNeeded(BigInt.from(100)), isTrue);
        // The owner's cap from /me and the business threshold on top.
        final low = capsOf(
          Preset.cashier,
          policy: {'mode': 'NONE', 'cashierCapMinor': '30000'},
        );
        expect(low.approvalNeeded(BigInt.from(30001), paid: true), isTrue);
        final threshold = capsOf(
          Preset.cashier,
          policy: {'mode': 'THRESHOLD', 'thresholdMinor': '10000'},
        );
        expect(
          threshold.approvalNeeded(BigInt.from(10000), paid: true),
          isTrue,
        );
        expect(
          threshold.approvalNeeded(BigInt.from(9999), paid: true),
          isFalse,
        );
      },
    );

    test('composer: cashier gets 320 / 400, never 405; capped receipts', () {
      final c = capsOf(Preset.cashier);
      expect(kindAllowedForCaps(DocKind.taxInvoiceReceipt, c), isTrue);
      expect(kindAllowedForCaps(DocKind.receipt, c), isTrue);
      expect(kindAllowedForCaps(DocKind.donationReceipt, c), isFalse);
      expect(kindAllowedForCaps(DocKind.credit, c), isFalse);
      expect(
        kindNeedsApproval(DocKind.receipt, () => true, cappedReceipts: true),
        isTrue,
      );
      expect(kindNeedsApproval(DocKind.receipt, () => true), isFalse);
      // Exempt business: "קיבלתי תשלום" opens a receipt for the cashier.
      expect(
        resolveIntent(
          intentPaid,
          'OSEK_PATUR',
          canRecordPayment: c.can(Cap.paymentIssue),
        ),
        DocKind.receipt,
      );
    });
  });

  group('presets ↔ server', () {
    test('presetToServer / presetOf', () {
      expect(presetToServer(Preset.cashier), ('CASHIER', const <String>[]));
      expect(presetToServer(Preset.officeManager), (
        'EMPLOYEE',
        const ['payment:record', 'money:read'],
      ));
      expect(presetOf('CASHIER', const []), Preset.cashier);
      expect(
        presetOf('EMPLOYEE', const ['payment:record', 'money:read']),
        Preset.officeManager,
      );
      expect(
        hasCustomGrants('EMPLOYEE', const ['payment:record', 'money:read']),
        isFalse,
      );
      expect(hasCustomGrants('CASHIER', const []), isFalse);
      expect(invitablePresets, contains(Preset.cashier));
      expect(invitablePresets, contains(Preset.officeManager));
      expect(PresetHe.label(Preset.cashier), 'קופאי/ת');
      expect(PresetHe.hint(Preset.cashier), contains('לא רואה הכנסות'));
      expect(PresetHe.hint(Preset.cashier), isNot(contains('אימות דו-שלבי')));
      expect(
        PresetHe.hint(Preset.officeManager),
        contains('לא מפיק/ה חשבוניות'),
      );
    });
  });

  group('team editors', () {
    late FakeBackend backend;
    setUp(() async => backend = await eSetUp());

    testWidgets('invite: "קופאי/ת" with its one-line hint → role CASHIER', (
      tester,
    ) async {
      await pumpAs(tester, backend, Preset.owner, const TeamPage());
      await tester.tap(find.byKey(const Key('team-invite')));
      await settle(tester);
      expect(find.text('קופאי/ת'), findsOneWidget);
      expect(find.text(PresetHe.cashierHint), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('text-email')),
        'kupa@salon.test',
      );
      await tester.tap(find.text('קופאי/ת'));
      await settle(tester);
      // "מפיק בעצמו" is the employee's switch only.
      expect(find.text(TeamHe.issuer), findsNothing);
      await tester.tap(find.byKey(const Key('editor-save')));
      await settle(tester);
      expect(backend.last('POST', '/business/members/invite')!.body, {
        'email': 'kupa@salon.test',
        'role': 'CASHIER',
      });
    });

    testWidgets('member editor: employee → "מנהל/ת משרד" saves role + grants', (
      tester,
    ) async {
      await pumpAs(tester, backend, Preset.owner, const TeamPage());
      await tester.tap(find.byKey(const Key('member-u-emp')));
      await settle(tester);
      expect(find.text('קופאי/ת'), findsOneWidget);
      await tester.tap(find.text(TeamHe.more).last);
      await settle(tester);
      await tester.tap(find.text('מנהל/ת משרד'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('editor-save')));
      await settle(tester);
      final put = backend.last('PUT', '/business/members/:userId/permissions')!;
      expect(put.params['userId'], 'u-emp');
      expect(put.body['permissions'], ['payment:record', 'money:read']);
    });
  });

  group("the cashier's Home", () {
    late FakeBackend backend;
    late Directory tmp;

    setUpAll(() async {
      tmp = await Directory.systemTemp.createTemp('b1_home');
      AppCache.directoryProvider = () async => tmp;
    });

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      resetSession();
      currentTab.value = AppTab.home;
      mobileInboxAvailable = null;
      localUnfinishedProbe = () async => null;
      backend = FakeBackend()..install();
      await AppCache.clearAll();
    });

    testWidgets(
      'one big "קיבלתי תשלום", the cap line, no money card / request',
      (tester) async {
        tester.view.physicalSize = const Size(1170, 2532);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        installInboxFakes(
          backend,
          documents: const [],
          dashboard: dashboardJson(unpaid: 1240000),
        );
        await tester.runAsync(() => signInAs(backend, Preset.cashier));
        final c = HomeController(now: () => DateTime(2026, 11, 16));
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigatorKey,
            scaffoldMessengerKey: messengerKey,
            navigatorObservers: [AppRouter.instance.observer],
            locale: const Locale('he', 'IL'),
            supportedLocales: const [Locale('he', 'IL')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: buildTheme(Brightness.light),
            home: HomeScreen(controller: c),
          ),
        );
        await tester.runAsync(() => c.load());
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('cashier-paid')), findsOneWidget);
        expect(find.text('קיבלתי תשלום'), findsOneWidget);
        expect(
          find.text('קבלה על תשלום שקיבלת עכשיו · עד ₪2,000 בלי אישור'),
          findsOneWidget,
        );
        // No money card (moneyView is off even though the fake sends sums).
        expect(find.text('יתרה לגבייה'), findsNothing);
        expect(find.textContaining('12,400'), findsNothing);
        expect(find.byKey(const Key('intent-request')), findsNothing);
        expect(find.byKey(const Key('intent-paid')), findsNothing);
        expect(find.text('קופאי/ת'), findsOneWidget); // role tag
      },
    );
  });
}
