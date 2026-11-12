// ignore_for_file: file_names
// QA (qa-perms) · SPEC-v2 §17 "הרשאות ותצוגה" against the LOCAL dev API.
//
// For every role preset of §4.3 (dev accounts in docs/API-MOBILE.md):
// * the server is the gate: /me.permissions, the BE-03a / BE-03 / BE-37
//   refusals (403 / 422 codes) called directly;
// * the app hides, never disables (§4.4 matrix, §4.5, F5): tabs, H, B rows,
//   S1 tiles, D primary + "⋯", Composer label — checked on the real screens
//   with the real /me of that preset, plus a textual per-preset "golden"
//   (`GOLDEN:<preset> …` lines) of everything the preset sees.
//
// Run (single QA runner only; needs the dev API on :3031 and its mail folder):
//   ~/flutter/bin/flutter test integration_test/v2_qa-perms_test.dart -d <sim-udid> \
//     --dart-define=API_BASE=http://127.0.0.1:3031 \
//     --dart-define=MAILDIR=$HOME/invoiceproject-mobile-dev-storage/outgoing-emails
//
// Test data: creates ONE small 305 draft as mobile-staff, submits it for
// approval and the owner rejects it in tearDownAll (it stays as a rejected
// draft: the server refuses DELETE of a draft with an approval history).
// Every other write in this file is expected to be refused by the server.
// AT-46 flips mobile-viewer to EMPLOYEE and back (restored in `finally`).

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/app_shell.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/business/business_screen.dart';
import 'package:invoice/screens/compose/compose_screen.dart';
import 'package:invoice/screens/document/document_screen.dart';
import 'package:invoice/screens/home/home_screen.dart';
import 'package:invoice/screens/reports/reports_screen.dart';
import 'package:invoice/state/business_context.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/session.dart';
import 'package:invoice/ui/theme.dart';
import 'package:invoice/ui/widgets/keypad.dart';
import 'package:invoice/ui/widgets/primary_button.dart';
import 'package:invoice/util/labels/common_he.dart';
import 'package:invoice/util/labels/compose_he.dart';
import 'package:invoice/util/labels/document_he.dart';

import 'v2_qa_perms_helpers.dart';
import 'qa_plans_guard.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  dismissPlansDuringTests();
  qaPermsSuite();
}

/// The suite (separate from main so a host dry-run can reuse it).
void qaPermsSuite() {
  /// Presets inside the dev OSEK_MURSHE business (D / Composer checks).
  final murshePresets = presets.where((p) => p.businessId == murshe).toList();
  const nonCancel = ['staff', 'employee', 'accountant', 'cpaRep', 'viewer'];

  String? ownersDoc; // an open 305 of the owner = "someone else's" for the rest
  String?
  employeesDoc; // an open 305 issued by "עובד + מפיק בעצמו" (own amounts visible)
  String? pendingDoc; // staff's 305, PENDING_APPROVAL
  String? customerId;
  final transcript = <String>[]; // GOLDEN lines, printed at the end

  setUpAll(() async {
    await restoreP0Accountant();
    for (final p in presets) {
      await qaApi(p.key);
    }
    final owner = await qaApi('owner');
    final staff = await qaApi('staff');
    ownersDoc = await findOpenTaxInvoiceBy(owner, presetSpec('owner').email);
    employeesDoc = await findOpenTaxInvoiceBy(
      owner,
      presetSpec('employee').email,
    );
    final customers = await staff.get('/customers?limit=1');
    customerId =
        ((customers.json['customers'] as List?)?.firstOrNull as Map?)?['id']
            as String?;
    if (customerId != null) {
      final draft = await staff.post('/documents', draftBody(customerId!));
      if (draft.status == 201) {
        final id = draft.json['id'] as String;
        final submitted = await staff.post('/documents/$id/submit');
        if (submitted.json['status'] == 'PENDING_APPROVAL') pendingDoc = id;
      }
    }
  });

  tearDownAll(() async {
    if (pendingDoc != null) {
      final owner = await qaApi('owner');
      await owner.post('/documents/$pendingDoc/reject', {
        'reason': 'QA הרשאות – ניקוי',
      });
      await (await qaApi(
        'staff',
      )).delete('/documents/$pendingDoc'); // best effort
    }
    leaveApp();
    await qaLogoutAll();
    for (final line in transcript) {
      debugPrint(line);
    }
  });

  // ---------------------------------------------------------------- server --

  group('server is the gate (§4.1, BE-02/03a/03/04/37)', () {
    testWidgets(
      'AT-52 §4.1: /me.permissions per preset = §4.3 preset; client preset derived from it',
      (tester) async {
        for (final p in presets) {
          final me = await (await qaApi(p.key)).get('/me');
          expect(me.status, 200, reason: p.key);
          final perms = {for (final x in me.json['permissions'] as List) '$x'};
          expect(perms, p.permissions, reason: '${p.key} /me.permissions');
          expect(
            Caps.fromMe(Me.fromJson(me.json)).preset,
            p.preset,
            reason: '${p.key} preset',
          );
          expect(
            me.json['enforcement']?['readGating'],
            isTrue,
            reason: '${p.key} BE-03 read gating',
          );
        }
      },
    );

    testWidgets(
      'AT-42 BE-03a: POST /credit on someone else\'s 305 → 403 for every preset without document:cancel',
      (tester) async {
        expect(
          ownersDoc,
          isNotNull,
          reason: 'dev data: no open 305 of the owner',
        );
        final lines = await creditLinesOf(await qaApi('owner'), ownersDoc!);
        for (final key in nonCancel) {
          final r = await (await qaApi(key)).post(
            '/documents/$ownersDoc/credit',
            {'scopeKey': 'default', 'lines': lines},
            true,
          );
          expect(r.status, 403, reason: '$key credit → $r');
          expect(r.error, 'DOCUMENT_ACTION_FORBIDDEN', reason: key);
        }
      },
    );

    testWidgets(
      'AT-22/AT-23 BE-03a: approve / reject → 403 without approval:decide',
      (tester) async {
        expect(
          pendingDoc,
          isNotNull,
          reason: 'could not create the PENDING_APPROVAL fixture',
        );
        for (final key in nonCancel) {
          final api = await qaApi(key);
          final a = await api.post(
            '/documents/$pendingDoc/approve',
            const {},
            true,
          );
          expect(a.status, 403, reason: '$key approve → $a');
          final r = await api.post('/documents/$pendingDoc/reject', {
            'reason': 'QA',
          });
          expect(r.status, 403, reason: '$key reject → $r');
          expect(r.error, 'DOCUMENT_ACTION_FORBIDDEN', reason: key);
        }
        final doc = await (await qaApi('owner')).get('/documents/$pendingDoc');
        expect(
          doc.json['document']?['status'],
          'PENDING_APPROVAL',
          reason: 'refused calls changed nothing',
        );
      },
    );

    testWidgets(
      'AT-57 BE-03a: issueDate yesterday → 403 BACKDATING_OWNER_ONLY for every non-owner who drafts',
      (tester) async {
        expect(customerId, isNotNull);
        for (final key in ['partner', 'staff', 'employee', 'cpaFull']) {
          final r = await (await qaApi(
            key,
          )).post('/documents', draftBody(customerId!, issueDate: qaDay(-1)));
          expect(r.status, 403, reason: '$key backdate → $r');
          expect(r.error, 'BACKDATING_OWNER_ONLY', reason: key);
        }
      },
    );

    testWidgets(
      'AT-56 BE-03a: credit on a receipt (400) → 422 CREDIT_SOURCE_TYPE_INVALID',
      (tester) async {
        final owner = await qaApi('owner');
        final receipt = await findIssued(owner, 'RECEIPT');
        expect(receipt, isNotNull, reason: 'dev data: no issued receipt');
        final lines = await creditLinesOf(owner, receipt!['id'] as String);
        final r = await owner.post('/documents/${receipt['id']}/credit', {
          'scopeKey': 'default',
          'lines': lines,
        }, true);
        expect(r.status, 422, reason: '$r');
        expect(r.error, 'CREDIT_SOURCE_TYPE_INVALID');
      },
    );

    testWidgets(
      'AT-43b BE-37: sole owner → THRESHOLD without self-approval → 422 APPROVAL_NO_OTHER_APPROVER',
      (tester) async {
        final solo = await qaApi('patur');
        final me = await solo.get('/me');
        expect(
          me.json['memberCount'],
          1,
          reason: 'dev patur business must have a single member',
        );
        expect(me.json['approvalPolicy']?['otherApproverExists'], isFalse);
        final r = await solo.put('/settings/approval', {
          'mode': 'THRESHOLD',
          'thresholdMinor': '500000',
          'selfApprovalAllowed': false,
        });
        expect(r.status, 422, reason: '$r');
        expect(r.error, 'APPROVAL_NO_OTHER_APPROVER');
      },
    );

    testWidgets('AT-51 BE-03: read + write gating (employee and viewer)', (
      tester,
    ) async {
      final staff = await qaApi('staff');
      final dash = await staff.get('/dashboard');
      expect(dash.status, 200);
      final s = dash.json['summary'] as Map<String, dynamic>;
      for (final k in [
        'month_income',
        'unpaid_balance',
        'unpaid_total',
        'overdue_total',
        'month_expenses',
      ]) {
        expect(s[k], isNull, reason: 'staff /dashboard $k must be null');
      }
      expect(
        (await staff.post('/exports/excel')).status,
        403,
        reason: 'staff /exports/excel',
      );
      expect(customerId, isNotNull);
      final patch = await staff.patch('/customers/$customerId', {
        'notes': 'QA',
      });
      expect(patch.status, 403, reason: 'staff PATCH /customers: $patch');
      expect(ownersDoc, isNotNull);
      expect(
        (await staff.get('/documents/$ownersDoc/pdf')).status,
        403,
        reason: 'staff pdf of owner doc',
      );
      final other = await staff.get('/documents/$ownersDoc');
      expect(
        other.json['document']?['total_minor'],
        isNull,
        reason: 'staff sees no amount on others\' docs',
      );

      final viewer = await qaApi('viewer');
      expect(
        (await viewer.post('/exports/accountant')).status,
        403,
        reason: 'viewer /exports/accountant',
      );
      expect(
        (await viewer.post('/exports/excel')).status,
        403,
        reason: 'viewer /exports/excel',
      );
    });

    testWidgets(
      'AT-51 read matrix: 403 rows of docs/API-MOBILE.md per preset',
      (tester) async {
        // path → presets that must be refused (everything else 200).
        const refused = {
          '/business/members': {
            'employee',
            'staff',
            'accountant',
            'cpaFull',
            'cpaRep',
            'viewer',
          },
          '/reports/income': {'employee', 'staff', 'accountant', 'viewer'},
          '/expenses?limit=3': {'viewer'},
          '/settings/document-email': {
            'employee',
            'staff',
            'accountant',
            'cpaFull',
            'cpaRep',
            'viewer',
          },
        };
        for (final entry in refused.entries) {
          for (final p in presets) {
            final r = await (await qaApi(p.key)).get(entry.key);
            final want = entry.value.contains(p.key) ? 403 : 200;
            expect(r.status, want, reason: '${p.key} GET ${entry.key} → $r');
            if (want == 403) {
              expect(
                r.error,
                'DOCUMENT_ACTION_FORBIDDEN',
                reason: '${p.key} ${entry.key}',
              );
            }
          }
        }
      },
    );

    testWidgets(
      'AT-50 §12.4: non-grantable permissions are refused; only managers invite',
      (tester) async {
        final owner = await qaApi('owner');
        final team = await owner.get('/business/members');
        final staffId =
            ((team.json['members'] as List).cast<Map<String, dynamic>>())
                .firstWhere(
                  (m) => m['email'] == presetSpec('staff').email,
                )['userId'];
        for (final p in [
          'document:cancel',
          'approval:decide',
          'business:configure',
          'membership:manage',
        ]) {
          final r = await owner.put('/business/members/$staffId/permissions', {
            'permissions': [p],
          });
          expect(r.status, 400, reason: 'grant $p → $r');
          final inv = await owner.post('/business/members/invite', {
            'email': 'qa-perms-never@tevel.test',
            'role': 'EMPLOYEE',
            'permissions': [p],
          });
          expect(inv.status, 400, reason: 'invite with $p → $inv');
        }
        final staffInvite = await (await qaApi('staff')).post(
          '/business/members/invite',
          {'email': 'qa-perms-never@tevel.test', 'role': 'EMPLOYEE'},
        );
        expect(staffInvite.status, 403, reason: 'staff invite → $staffInvite');
        final after = await owner.get('/me'); // unchanged team
        expect(after.status, 200);
      },
    );
  });

  // -------------------------------------------------------------------- UI --

  Future<void> pumpApp(WidgetTester tester, String key) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await AppCache.clearAll(); // a fresh sign-in never sees another member's cache
    await enterAppAs(key);
    AppRouter.instance.install();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: messengerKey,
        navigatorObservers: [AppRouter.instance.observer],
        locale: const Locale('he', 'IL'),
        supportedLocales: const [Locale('he', 'IL')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildTheme(Brightness.light),
        home: const AppShell(),
      ),
    );
    await pumpFor(tester, const Duration(seconds: 3)); // H/R: cache → network
  }

  Future<void> popTop(WidgetTester tester) async {
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    await pumpFor(tester, const Duration(milliseconds: 800));
  }

  for (final p in presets) {
    testWidgets(
      'AT-52 AT-49 AT-40/41/44 [${p.key}] shell · H/R · ＋ · B: hidden, not disabled (§4.4)',
      (tester) async {
        await pumpApp(tester, p.key);
        final caps = businessContext.caps;
        expect(caps.preset, p.preset);
        expect(
          caps.fromFallback,
          isFalse,
          reason: 'BE-02 permissions must drive caps',
        );

        // Tabs.
        expect(find.byKey(const Key('tab-home')), findsOneWidget);
        // The bottom bar has no "לקוחות" tab any more (ניהול → לקוחות).
        expect(find.byKey(const Key('tab-people')), findsNothing);
        expect(find.byKey(const Key('tab-business')), findsOneWidget);
        expect(
          find.byKey(const Key('tab-create')),
          p.createTab ? findsOneWidget : findsNothing,
          reason: '＋ for ${p.key}',
        );

        // Home tab: R for accountants, H for the rest.
        expect(
          find.byType(ReportsScreen),
          p.homeIsReports ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(HomeScreen),
          p.homeIsReports ? findsNothing : findsOneWidget,
        );
        if (!p.homeIsReports) {
          await pumpUntil(tester, find.byKey(const Key('home-business-name')));
          expect(
            find.byKey(const Key('home-money')),
            p.moneyCard ? findsOneWidget : findsNothing,
            reason: 'money card ${p.key}',
          );
          expect(
            find.byKey(const Key('intent-paid')),
            p.paidIntent ? findsOneWidget : findsNothing,
            reason: '"קיבלתי תשלום" for ${p.key} (§4.4, §19 q7)',
          );
          expect(
            find.byKey(const Key('intent-request')),
            p.intents ? findsOneWidget : findsNothing,
          );
          expect(
            find.byKey(const Key('home-role-tag')),
            p.preset == Preset.owner ? findsNothing : findsOneWidget,
          );
        }
        expectHiddenNotDisabled(tester, '${p.key} H/R');
        final home = {
          if (find.byKey(const Key('home-money')).evaluate().isNotEmpty)
            'money',
          if (find.byKey(const Key('intent-paid')).evaluate().isNotEmpty)
            'intent-paid',
          if (find.byKey(const Key('intent-request')).evaluate().isNotEmpty)
            'intent-request',
          if (find.byType(ReportsScreen).evaluate().isNotEmpty) 'R',
        };

        // ＋ opens the composer directly (S1 was removed from the UI; the
        // other S1 tiles live in ניהול's quick actions, recorded below).
        var s1 = <String>{};
        if (p.createTab) {
          await tester.tap(find.byKey(const Key('tab-create')));
          expect(await pumpUntil(tester, find.byType(ComposeScreen)), isTrue);
          await pumpFor(tester, const Duration(milliseconds: 600));
          s1 = {'compose'};
          // Nothing typed: closing the composer (and its "ממי?" page) keeps
          // no draft.
          navigatorKey.currentState!.popUntil((r) => r.isFirst);
          await pumpFor(tester, const Duration(milliseconds: 800));
          expect(find.byType(ComposeScreen, skipOffstage: false), findsNothing);
        }

        // B rows.
        await tester.tap(find.byKey(const Key('tab-business')));
        await pumpFor(tester, const Duration(seconds: 2));
        final rows = await keysWithPrefixScrolling(
          tester,
          find.byType(BusinessScreen),
          'brow-',
        );
        expect(rows, p.businessRows, reason: 'B rows ${p.key}');
        expectHiddenNotDisabled(tester, '${p.key} B');
        final quick = keysWithPrefix('management-action-');
        debugPrint('QUICK:${p.key} ${(quick.toList()..sort()).join(',')}');

        final golden =
            'GOLDEN:${p.key} tabs=${p.createTab ? 'H·P·＋·B' : 'H·P·B'} '
            'home=${(home.toList()..sort()).join(',')} s1=${(s1.toList()..sort()).join(',')} '
            'B=${(rows.toList()..sort()).join(',')}';
        transcript.add(golden);
        debugPrint(golden);
      },
    );
  }

  for (final p in murshePresets) {
    testWidgets(
      'AT-40/41/42/44 AT-49 [${p.key}] D: primary + ⋯ on someone else\'s 305 and on a pending one',
      (tester) async {
        expect(ownersDoc, isNotNull);
        await pumpApp(tester, p.key);

        Future<(List<String>, Set<String>)> openDoc(String id) async {
          expect(await go('tevel://doc/$id'), isTrue);
          expect(await pumpUntil(tester, find.byType(DocumentScreen)), isTrue);
          await pumpUntil(tester, find.byKey(const Key('doc-pdf')));
          await pumpFor(tester, const Duration(seconds: 1));
          expectHiddenNotDisabled(tester, '${p.key} D $id');
          final primary = primaryLabels();
          var menu = <String>{};
          final more = find.byTooltip(CommonHe.more);
          if (more.evaluate().isNotEmpty) {
            await tester.tap(more.last);
            await pumpFor(tester, const Duration(milliseconds: 800));
            menu = openMenuLabels(tester, const [
              DocumentHe.cancelOrCredit,
              DocumentHe.recordPayment,
              DocumentHe.reject,
              DocumentHe.approveAndIssue,
              DocumentHe.share,
              DocumentHe.duplicate,
              DocumentHe.sendAgain,
            ]);
            expectHiddenNotDisabled(tester, '${p.key} D ⋯');
            await tester.tapAt(const Offset(10, 10)); // dismiss the sheet
            await pumpFor(tester, const Duration(milliseconds: 600));
          }
          return (primary, menu);
        }

        // An open 305 created by the owner.
        final (primary, menu) = await openDoc(ownersDoc!);
        final all = {...primary, ...menu};
        expect(
          primary.length,
          lessThanOrEqualTo(1),
          reason: 'F2: one PrimaryButton at most',
        );
        expect(
          menu.contains(DocumentHe.cancelOrCredit),
          p.cancelCredit,
          reason: '"בטל / זכה" for ${p.key}',
        );
        // Without money:read the amounts of someone else's 305 are null (BE-03),
        // so "קיבלתי תשלום" is checked on a document the preset may see.
        if (p.permissions.contains('money:read') || !p.recordPayment) {
          expect(
            all.contains(DocumentHe.recordPayment),
            p.recordPayment,
            reason: '"קיבלתי תשלום" for ${p.key}',
          );
        }
        if (p.shareOnly) {
          expect(primary, [
            DocumentHe.share,
          ], reason: '${p.key}: D primary = "שתף" (local PDF)');
        }
        await popTop(tester);

        // AT-42: the self-issuer records payments on its own open 305 (S5 reachable).
        if (p.recordPayment && !p.permissions.contains('money:read')) {
          expect(
            employeesDoc,
            isNotNull,
            reason: 'dev data: no open 305 issued by mobile-employee',
          );
          final (ownPrimary, ownMenu) = await openDoc(employeesDoc!);
          expect(
            {...ownPrimary, ...ownMenu}.contains(DocumentHe.recordPayment),
            isTrue,
            reason: '"קיבלתי תשלום" on ${p.key}\'s own 305',
          );
          expect(
            ownMenu.contains(DocumentHe.cancelOrCredit),
            isFalse,
            reason: 'no "בטל / זכה" on own 305 either',
          );
          await popTop(tester);
        }

        // Staff's document waiting for approval.
        var pending = '-';
        if (pendingDoc != null) {
          final (pPrimary, pMenu) = await openDoc(pendingDoc!);
          expect(
            pPrimary.contains(DocumentHe.approveAndIssue),
            p.approve,
            reason: '"אשר והפק" for ${p.key}',
          );
          expect(
            pMenu.contains(DocumentHe.reject),
            p.approve,
            reason: '"דחה" for ${p.key}',
          );
          pending =
              '${pPrimary.join('|')}/${(pMenu.toList()..sort()).join('|')}';
          await popTop(tester);
        }
        final golden =
            'GOLDEN:${p.key} D305=${primary.join('|')}/${(menu.toList()..sort()).join('|')} '
            'Dpending=$pending';
        transcript.add(golden);
        debugPrint(golden);
      },
    );
  }

  for (final p in murshePresets.where((p) => p.intents)) {
    testWidgets(
      'AT-41/42 [${p.key}] Composer primary: "שלח לאישור" only without document:finalize',
      (tester) async {
        await pumpApp(tester, p.key);
        await pumpUntil(tester, find.byKey(const Key('intent-request')));
        await tester.tap(find.byKey(const Key('intent-request')));
        expect(await pumpUntil(tester, find.byType(ComposeScreen)), isTrue);
        // §19 q4: customer first. Pick "לקוח מזדמן" in S2 when it opens.
        if (await pumpUntil(
          tester,
          find.byKey(const Key('s2-walkin')),
          timeout: const Duration(seconds: 5),
        )) {
          await tester.ensureVisible(find.byKey(const Key('s2-walkin')));
          await tester.pump(const Duration(milliseconds: 200));
          await tester.tap(find.byKey(const Key('s2-walkin')));
          await pumpFor(tester, const Duration(seconds: 1));
        }
        // ₪100 on the keypad: the primary exists once the Composer is ready.
        for (final k in ['1', '0', '0']) {
          await tester.tap(
            find.descendant(of: find.byType(Keypad), matching: find.text(k)),
          );
          await tester.pump(const Duration(milliseconds: 150));
        }
        expect(
          await pumpUntil(
            tester,
            find.byKey(const Key('compose-primary'), skipOffstage: false),
          ),
          isTrue,
          reason: 'Composer never became ready for ${p.key}',
        );
        final label = tester
            .widget<PrimaryButton>(
              find.byKey(const Key('compose-primary'), skipOffstage: false),
            )
            .label;
        if (p.composerSubmits) {
          expect(
            label,
            ComposeHe.submit,
            reason: '${p.key}: Composer must end with "שלח לאישור"',
          );
        } else {
          expect(
            label,
            isNot(ComposeHe.submit),
            reason: '${p.key} issues by itself (policy NONE)',
          );
        }
        expectHiddenNotDisabled(tester, '${p.key} C');
        transcript.add('GOLDEN:${p.key} C=$label');
        await popTop(tester);
      },
    );
  }

  testWidgets(
    'AT-50 [owner] S13 "חבר צוות" offers only the "מפיק בעצמו" switch',
    (tester) async {
      await pumpApp(tester, 'owner');
      final team = await (await qaApi('owner')).get('/business/members');
      final staffId =
          ((team.json['members'] as List).cast<Map<String, dynamic>>())
              .firstWhere(
                (m) => m['email'] == presetSpec('staff').email,
              )['userId'];
      expect(await go('/business/team'), isTrue);
      final row = find.byKey(Key('member-$staffId'));
      expect(await pumpUntil(tester, row), isTrue);
      await tester.ensureVisible(row);
      await tester.tap(row);
      await pumpFor(tester, const Duration(seconds: 1));
      expect(
        keysWithPrefix('switch-'),
        {'issuer'},
        reason: 'S13: no settings/team switches (§12.4)',
      );
      expectHiddenNotDisabled(tester, 'S13 member');
      await popTop(tester);
    },
  );

  testWidgets(
    'AT-47 [staff] a capability 403 → toast "ההרשאות שלך עודכנו" + /me refresh',
    (tester) async {
      await pumpApp(tester, 'staff');
      final before = session.meFetchedAt;
      try {
        await ApiClient.instance.get('/business/members');
        fail('staff must not read the team');
      } on ApiException catch (e) {
        expect(e.status, 403);
        expect(e.code, 'DOCUMENT_ACTION_FORBIDDEN');
      }
      expect(
        await pumpUntil(tester, find.text(CommonHe.permissionsUpdated)),
        isTrue,
      );
      expect(
        session.meFetchedAt!.isAfter(before!),
        isTrue,
        reason: '/me refreshed after the 403',
      );
      expect(find.byType(HomeScreen), findsOneWidget);
    },
  );

  testWidgets(
    'AT-46 [viewer→עובד→viewer] role changed elsewhere → foreground → UI follows',
    (tester) async {
      final owner = await qaApi('owner');
      final team = await owner.get('/business/members');
      final viewerId =
          ((team.json['members'] as List).cast<Map<String, dynamic>>())
              .firstWhere(
                (m) => m['email'] == presetSpec('viewer').email,
              )['userId'];
      await pumpApp(tester, 'viewer');
      expect(find.byKey(const Key('tab-create')), findsNothing);
      expect(find.byKey(const Key('intent-request')), findsNothing);

      Future<void> resume() async {
        session.meFetchedAt = DateTime.now().subtract(
          const Duration(minutes: 2),
        );
        await businessContext.onResumed();
        await pumpFor(tester, const Duration(seconds: 2));
      }

      try {
        final r = await owner.put('/business/members/$viewerId/role', {
          'role': 'EMPLOYEE',
        });
        expect(r.status, 200, reason: '$r');
        await resume();
        expect(businessContext.caps.preset, Preset.employee);
        expect(find.byKey(const Key('tab-create')), findsOneWidget);
        expect(find.byKey(const Key('intent-request')), findsOneWidget);
        expect(
          find.byKey(const Key('home-money')),
          findsNothing,
          reason: 'EMPLOYEE has no money:read',
        );
      } finally {
        final back = await owner.put('/business/members/$viewerId/role', {
          'role': 'READ_ONLY',
        });
        expect(back.status, 200, reason: 'restore viewer: $back');
      }
      await resume();
      expect(businessContext.caps.preset, Preset.viewer);
      expect(find.byKey(const Key('tab-create')), findsNothing);
      expect(find.byKey(const Key('intent-request')), findsNothing);
      final perms = {
        for (final x
            in (await (await qaApi('viewer')).get('/me')).json['permissions']
                as List)
          '$x',
      };
      expect(
        perms,
        presetSpec('viewer').permissions,
        reason: 'viewer restored exactly',
      );
    },
  );
}
