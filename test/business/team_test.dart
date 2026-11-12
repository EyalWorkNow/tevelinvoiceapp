// B·צוות + S13 "חבר צוות" (SPEC-v2 §6.B, §12; AT-24, AT-25, AT-50; J8, J8b).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/api/team_api.dart';
import 'package:invoice/app_shell.dart';
import 'package:invoice/screens/business/business_template.dart';
import 'package:invoice/screens/business/team_page.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/session.dart';
import 'package:invoice/ui/ds.dart';

import '../fakes/fake_api.dart';
import 'e_harness.dart';

void main() {
  late FakeBackend backend;
  setUp(() async => backend = await eSetUp());

  group('presets (§4.3) ↔ server role + grants', () {
    test('presetOf goes through caps.dart', () {
      expect(presetOf('OWNER', const []), Preset.owner);
      expect(presetOf('ADMIN', const []), Preset.partner);
      expect(presetOf('EMPLOYEE', const []), Preset.employee);
      expect(
        presetOf('EMPLOYEE', const ['document:finalize', 'payment:record']),
        Preset.employeeIssuer,
      );
      expect(
        presetOf('READ_ONLY', const ['expense:record', 'expense:approve']),
        Preset.accountantRep,
      );
      expect(presetOf('READ_ONLY', const []), Preset.viewer);
      expect(presetOf('ACCOUNTANT', const []), Preset.accountantFull);
    });

    test(
      'presetToServer: P0 accountant = READ_ONLY + expense grants; issuer switch',
      () {
        void check(
          Preset p,
          String role,
          List<String> grants, {
          bool issuer = false,
        }) {
          final (r, g) = presetToServer(p, issuer: issuer);
          expect(r, role);
          expect(g, grants);
        }

        check(Preset.employee, 'EMPLOYEE', []);
        check(Preset.employee, 'EMPLOYEE', [
          'document:finalize',
          'payment:record',
          'allocation:request',
        ], issuer: true);
        check(Preset.accountantRep, 'READ_ONLY', [
          'expense:record',
          'expense:approve',
        ]);
        check(Preset.partner, 'ADMIN', []);
        check(Preset.viewer, 'READ_ONLY', []);
      },
    );

    test('"מותאם אישית" = grants that no preset explains (§12.4)', () {
      expect(hasCustomGrants('EMPLOYEE', const []), isFalse);
      expect(
        hasCustomGrants('EMPLOYEE', const [
          'document:finalize',
          'payment:record',
        ]),
        isFalse,
      );
      expect(
        hasCustomGrants('EMPLOYEE', const [
          'document:finalize',
          'payment:record',
          'allocation:request',
        ]),
        isFalse,
      );
      expect(hasCustomGrants('EMPLOYEE', const ['expense:approve']), isTrue);
      expect(hasCustomGrants('EMPLOYEE', const ['document:finalize']), isTrue);
      expect(
        hasCustomGrants('READ_ONLY', const [
          'expense:record',
          'expense:approve',
        ]),
        isFalse,
      );
      expect(hasCustomGrants('ADMIN', const []), isFalse);
    });

    test('invitation days left', () {
      final now = DateTime.utc(2026, 10, 30, 12);
      TeamInvitation inv(Duration d) => TeamInvitation(
        id: 'i',
        email: 'a',
        role: 'EMPLOYEE',
        expiresAt: now.add(d),
      );
      expect(inv(const Duration(days: 5)).daysLeft(now), 5);
      expect(inv(const Duration(days: 1, hours: 2)).daysLeft(now), 1);
      expect(inv(const Duration(hours: 3)).daysLeft(now), 0);
      expect(inv(const Duration(days: -1)).daysLeft(now), 0);
    });
  });

  testWidgets(
    'J8: עסק → צוות → "+ הזמן" → email → "שלח הזמנה" = 4 taps, role EMPLOYEE (AT-24)',
    (tester) async {
      await pumpAs(tester, backend, Preset.owner, const AppShell());
      final taps = Taps();
      await taps.tap(tester, find.byKey(const Key('tab-business')));
      // The quick actions above the rows can push צוות below the fold of the
      // lazy list; scrolling to it is not a tap (F3.1).
      await tester.scrollUntilVisible(
        find.byKey(const Key('brow-team')),
        200,
        scrollable: find
            .descendant(
              of: find.byType(BusinessPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await taps.tap(tester, find.byKey(const Key('brow-team')));
      expect(find.byType(TeamPage), findsOneWidget);
      expect(find.byType(PrimaryButton), findsOneWidget); // AT-90
      await taps.tap(tester, find.byKey(const Key('team-invite')));
      // The e-mail field has focus already (not counted, F3.1).
      final email = tester.widget<TextField>(
        find.byKey(const Key('text-email')),
      );
      expect(email.autofocus, isTrue);
      expect(find.text('עובד'), findsOneWidget); // default preset, checked
      expect(find.text('צפייה בלבד'), findsNothing); // under "עוד ▾"
      await tester.enterText(
        find.byKey(const Key('text-email')),
        'Worker@Tevel.test',
      );
      await taps.tap(tester, find.byKey(const Key('editor-save')));
      expect(taps.count, 4);
      final call = backend.last('POST', '/business/members/invite')!;
      expect(call.body, {'email': 'worker@tevel.test', 'role': 'EMPLOYEE'});
      expect(find.text('ההזמנה נשלחה'), findsOneWidget);
      expect(
        find.text('שלח בווטסאפ'),
        findsOneWidget,
      ); // snack action (inviteUrl, BE-41)
      expect(
        backend.calls('GET', '/business/members').length,
        greaterThanOrEqualTo(2),
      );
    },
  );

  testWidgets(
    'J8b: "הזמן רואה חשבון" = READ_ONLY + expense grants in one call (AT-25, BE-41)',
    (tester) async {
      await pumpAs(tester, backend, Preset.owner, const TeamPage());
      final taps = Taps();
      await taps.tap(tester, find.byKey(const Key('team-invite-accountant')));
      expect(find.text('הזמן רואה חשבון'), findsWidgets);
      await tester.enterText(
        find.byKey(const Key('text-email')),
        'cpa@tevel.test',
      );
      await taps.tap(tester, find.byKey(const Key('editor-save')));
      expect(taps.count, 2); // + עסק + צוות = J8b 4
      expect(backend.last('POST', '/business/members/invite')!.body, {
        'email': 'cpa@tevel.test',
        'role': 'READ_ONLY',
        'permissions': ['expense:record', 'expense:approve'],
      });
    },
  );

  testWidgets(
    'P0 server without BE-41: accountant grants applied when the owner reopens צוות',
    (tester) async {
      // The V1 invite answer has no `permissions`; V1 has no ACCOUNTANT_REP role.
      backend.on(
        'POST',
        '/business/members/invite',
        (r) => r.body['role'] == 'ACCOUNTANT_REP'
            ? FakeResponse.error(400, 'VALIDATION')
            : const FakeResponse(201, {
                'invitationId': 'i9',
                'link': 'https://x/#/i',
              }),
      );
      await pumpAs(tester, backend, Preset.owner, const TeamPage());
      await tester.tap(find.byKey(const Key('team-invite-accountant')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('text-email')),
        'cpa@tevel.test',
      );
      await tester.tap(find.byKey(const Key('editor-save')));
      await settle(tester);
      expect(await tester.runAsync(pendingGrantEmails), {'cpa@tevel.test'});
      // Remembered grants are not an unfinished money operation (no sign-out warning).
      expect(await tester.runAsync(AppCache.hasPending), isFalse);

      // The accountant joined (READ_ONLY, no grants yet).
      backend.json(
        'GET',
        '/business/members',
        teamJson(
          members: [
            memberJson('u-me', 'OWNER', self: true),
            memberJson('u-cpa', 'READ_ONLY', email: 'cpa@tevel.test'),
          ],
          invitations: const [],
        ),
      );
      await tester.pumpWidget(eApp(const SizedBox()));
      await tester.pumpWidget(eApp(const TeamPage()));
      await settle(tester);
      final put = backend.last('PUT', '/business/members/:userId/permissions')!;
      expect(put.params['userId'], 'u-cpa');
      expect(put.body['permissions'], ['expense:record', 'expense:approve']);
      expect(await tester.runAsync(pendingGrantEmails), isEmpty);
      await tester.runAsync(AppCache.clearAll);
    },
  );

  testWidgets(
    'read-gated server: P0 accountant is offered ACCOUNTANT_REP; nothing written on view, only after the owner confirms; no probe POSTs',
    (tester) async {
      backend.json(
        'GET',
        '/business/members',
        teamJson(
          members: [
            memberJson('u-me', 'OWNER', self: true),
            memberJson(
              'u-cpa',
              'READ_ONLY',
              email: 'cpa@tevel.test',
              permissions: ['expense:record', 'expense:approve'],
            ),
          ],
          invitations: const [],
        ),
      );
      backend.json('PUT', '/business/members/:userId/role', {
        'status': 'ok',
      }); // BE-04 server
      phone(tester);
      await tester.runAsync(() async {
        await signInAs(backend, Preset.owner);
        backend.json('GET', '/me', meJson(Preset.owner, readGating: true));
        await session.refreshBusiness();
      });
      await tester.pumpWidget(eApp(const TeamPage()));
      await settle(tester);
      // A screen view never changes permissions.
      expect(backend.calls('PUT', '/business/members/:userId/role'), isEmpty);
      expect(
        backend.calls('PUT', '/business/members/:userId/permissions'),
        isEmpty,
      );
      expect(find.textContaining('יידרש אימות דו-שלבי'), findsOneWidget);
      // Cancel → still nothing.
      await tester.tap(find.byKey(const Key('upgrade-u-cpa')));
      await settle(tester);
      await tester.tap(find.text('ביטול'));
      await settle(tester);
      expect(backend.calls('PUT', '/business/members/:userId/role'), isEmpty);
      // Confirm → role + grants.
      await tester.tap(find.byKey(const Key('upgrade-u-cpa')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('confirm-upgrade')));
      await settle(tester);
      final role = backend.last('PUT', '/business/members/:userId/role')!;
      expect(role.params['userId'], 'u-cpa');
      expect(role.body, {'role': 'ACCOUNTANT_REP'});
      expect(
        backend.last('PUT', '/business/members/:userId/permissions')!.body,
        {'permissions': <String>[]},
      );
      // V2 /me: BE-49 is known to exist, the mutating route is never probed.
      expect(backend.calls('POST', '/business/ownership/transfer'), isEmpty);
    },
  );

  testWidgets(
    'list: preset tags, pending row with days, no action on owner/self',
    (tester) async {
      backend.json(
        'GET',
        '/business/members',
        teamJson(
          members: [
            memberJson('u-me', 'OWNER', self: true, name: 'דנה'),
            memberJson(
              'u-emp',
              'EMPLOYEE',
              name: 'רון',
              permissions: ['document:finalize', 'payment:record'],
            ),
            memberJson(
              'u-x',
              'EMPLOYEE',
              name: 'מיכל',
              permissions: ['expense:approve'],
            ),
          ],
          invitations: [
            invitationJson(
              'i1',
              'new@tevel.test',
              'READ_ONLY',
              permissions: ['expense:record', 'expense:approve'],
              expiresAt: DateTime.utc(2026, 11, 4, 12),
            ),
          ],
          expired: [
            invitationJson(
              'i2',
              'old@tevel.test',
              'EMPLOYEE',
              expiresAt: DateTime.utc(2026, 10, 20),
            ),
          ],
        ),
      );
      phone(tester);
      await tester.runAsync(() => signInAs(backend, Preset.owner));
      await tester.pumpWidget(
        eApp(TeamPage(now: () => DateTime.utc(2026, 10, 30, 12))),
      );
      await settle(tester);
      expect(find.textContaining('עובד · מפיק בעצמו'), findsOneWidget);
      expect(find.textContaining('מותאם אישית'), findsOneWidget);
      expect(
        find.textContaining('רואה חשבון · ממתין · פג בעוד 5 ימים'),
        findsOneWidget,
      );
      expect(find.textContaining('פג תוקף'), findsOneWidget);
      // Owner row (self) has no tap → no sheet.
      await tester.tap(find.byKey(const Key('member-u-me')));
      await settle(tester);
      expect(find.byKey(const Key('editor-save')), findsNothing);
    },
  );

  testWidgets(
    'S13 "חבר צוות": only "מפיק בעצמו" (AT-50) → PUT role then permissions',
    (tester) async {
      await pumpAs(tester, backend, Preset.owner, const TeamPage());
      await tester.tap(find.byKey(const Key('member-u-emp')));
      await settle(tester);
      expect(find.byType(Switch), findsOneWidget);
      expect(find.text('מפיק בעצמו'), findsOneWidget);
      expect(
        find.byType(PrimaryButton),
        findsNWidgets(2),
      ); // page + sheet = one per surface
      await tester.tap(find.byKey(const Key('switch-issuer')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('editor-save')));
      await settle(tester);
      expect(backend.last('PUT', '/business/members/:userId/role')!.body, {
        'role': 'EMPLOYEE',
      });
      expect(
        backend.last('PUT', '/business/members/:userId/permissions')!.body,
        {
          'permissions': [
            'document:finalize',
            'payment:record',
            'allocation:request',
          ],
        },
      );

      // Partner preset: switch disappears; ADMIN with no grants.
      await tester.tap(find.byKey(const Key('member-u-emp')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('choice-preset-partner')));
      await settle(tester);
      expect(find.byType(Switch), findsNothing);
      await tester.tap(find.byKey(const Key('editor-save')));
      await settle(tester);
      expect(backend.last('PUT', '/business/members/:userId/role')!.body, {
        'role': 'ADMIN',
      });
      expect(
        backend.last('PUT', '/business/members/:userId/permissions')!.body,
        {'permissions': []},
      );
    },
  );

  testWidgets('⋯ "הסר מהעסק" → red dialog → POST revoke', (tester) async {
    await pumpAs(tester, backend, Preset.owner, const TeamPage());
    await tester.tap(find.byKey(const Key('member-u-partner')));
    await settle(tester);
    await tester.tap(find.byType(MoreMenu).last);
    await settle(tester);
    await tester.tap(find.text('הסר מהעסק'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('confirm-danger')));
    await settle(tester);
    expect(
      backend
          .last('POST', '/business/members/:userId/revoke')!
          .params['userId'],
      'u-partner',
    );
  });

  testWidgets('invitation ⋯: שלח שוב (BE-41) and בטל הזמנה (red, last)', (
    tester,
  ) async {
    await pumpAs(tester, backend, Preset.owner, const TeamPage());
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('invitation-i1')),
        matching: find.byType(MoreMenu),
      ),
    );
    await settle(tester);
    expect(find.text('שלח שוב'), findsOneWidget);
    expect(find.text('בטל הזמנה'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('בטל הזמנה')).dy,
      greaterThan(tester.getTopLeft(find.text('שלח שוב')).dy),
    );
    await tester.tap(find.text('שלח שוב'));
    await settle(tester);
    expect(
      backend.calls('POST', '/business/invitations/:id/resend'),
      hasLength(1),
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('invitation-i1')),
        matching: find.byType(MoreMenu),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('בטל הזמנה'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('confirm-danger')));
    await settle(tester);
    expect(
      backend.last('POST', '/business/invitations/:id/revoke')!.params['id'],
      'i1',
    );
  });

  testWidgets('partner (ADMIN) sees no action on the owner', (tester) async {
    backend.json(
      'GET',
      '/business/members',
      teamJson(
        members: [
          memberJson('u-owner', 'OWNER', name: 'דנה'),
          memberJson('u-me', 'ADMIN', self: true, name: 'יוסי'),
          memberJson('u-emp', 'EMPLOYEE', name: 'רון'),
        ],
      ),
    );
    await pumpAs(tester, backend, Preset.partner, const TeamPage());
    await tester.tap(find.byKey(const Key('member-u-owner')));
    await settle(tester);
    expect(find.byKey(const Key('editor-save')), findsNothing);
    await tester.tap(find.byKey(const Key('member-u-emp')));
    await settle(tester);
    expect(find.byKey(const Key('editor-save')), findsOneWidget);
  });

  testWidgets('error state → "נסה שוב" reloads', (tester) async {
    backend.error('GET', '/business/members', 500, 'INTERNAL');
    await pumpAs(tester, backend, Preset.owner, const TeamPage());
    expect(find.text('נסה שוב'), findsOneWidget);
    expect(find.byType(PrimaryButton), findsNothing);
    backend.json('GET', '/business/members', teamJson());
    await tester.tap(find.text('נסה שוב'));
    await settle(tester);
    expect(find.byKey(const Key('team-invite')), findsOneWidget);
  });
}
