// Squad E · P1/P2 on the real SRV endpoints: S14 search + "+ עסק נוסף"
// (BE-24, BE-40), B "תזכורות אוטומטיות" (BE-19), 13.1 extras (BE-13, BE-22,
// BE-18 advances, BE-43 type change), accountant role (BE-04), ownership
// transfer (BE-49). Routes the server does not have answer 404 NOT_FOUND and
// their rows/fields stay hidden (F5).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/screens/auth/onboarding_screen.dart';
import 'package:invoice/screens/business/account_page.dart';
import 'package:invoice/screens/business/business_screen.dart';
import 'package:invoice/screens/business/sheets/editor_configs.dart';
import 'package:invoice/screens/business/team_page.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/session.dart';
import 'package:invoice/ui/ds.dart';

import '../fakes/fake_api.dart';
import 'e_harness.dart';

/// Scrolls the form/list until [f] is on screen (ensureVisible does not
/// move a ListView whose single child holds the whole form).
Future<void> reveal(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  late FakeBackend backend;
  setUp(() async => backend = await eSetUp());

  group('S14 (BE-24 / BE-40)', () {
    testWidgets('search > 7 asks GET /mobile/businesses?q= and pages with "הצג עוד"', (tester) async {
      backend.on('GET', '/mobile/businesses', (r) {
        final q = r.raw.url.queryParameters;
        final offset = int.parse(q['offset']!);
        final limit = int.parse(q['limit']!);
        return FakeResponse(200, {
          'total': 60,
          'offset': offset,
          'limit': limit,
          'businesses': [
            for (var i = offset; i < (offset + limit).clamp(0, 60); i++)
              {'businessId': 'srv-$i', 'legalName': 'לקוח $i', 'role': 'ACCOUNTANT'},
          ],
        });
      });
      await pumpAs(tester, backend, Preset.owner, const BusinessScreen(), businesses: 9);
      await tester.tap(find.byKey(const Key('business-name')));
      await settle(tester);
      expect(find.byKey(const Key('s14-add')), findsNothing); // no POST /businesses yet
      await tester.enterText(find.byKey(const Key('s14-search')), 'לקוח');
      await tester.pump(const Duration(milliseconds: 350));
      await settle(tester);
      final call = backend.last('GET', '/mobile/businesses')!;
      expect(call.raw.url.queryParameters['q'], 'לקוח');
      expect(call.raw.url.queryParameters['offset'], '0');
      expect(find.byKey(const Key('s14-srv-0')), findsOneWidget);
      expect(find.byKey(const Key('s14-b1')), findsNothing); // server results replace the local list
      await tester.scrollUntilVisible(
        find.byKey(const Key('s14-more')),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const Key('s14-more')));
      await settle(tester);
      expect(backend.last('GET', '/mobile/businesses')!.raw.url.queryParameters['offset'], '50');
      expect(find.byKey(const Key('s14-more')), findsNothing); // 60 of 60
    });

    testWidgets('server without BE-24 → local filter', (tester) async {
      backend.off('GET', '/mobile/businesses');
      await pumpAs(tester, backend, Preset.owner, const BusinessScreen(), businesses: 9);
      await tester.tap(find.byKey(const Key('business-name')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('s14-search')), 'עסק 9');
      await tester.pump(const Duration(milliseconds: 350));
      await settle(tester);
      expect(find.byKey(const Key('s14-b9')), findsOneWidget);
      expect(find.byKey(const Key('s14-b2')), findsNothing);
    });

    testWidgets('"+ עסק נוסף" (BE-40) → setup → POST /businesses → switch to it', (tester) async {
      backend
        ..on('POST', '/businesses', (r) {
          if (r.body.isEmpty) return FakeResponse.error(422, 'VALIDATION');
          // From now on the account lists the new business too.
          final account = accountJson(count: 2);
          (account['businesses'] as List).add({
            'businessId': 'b-new',
            'legalName': 'העסק השני',
            'role': 'OWNER',
          });
          backend.json('GET', '/mobile/session', account);
          return const FakeResponse(201, {'businessId': 'b-new'});
        })
        ..on('PUT', '/business/profile', (r) => FakeResponse(200, {'profile': profileJson()['profile']}))
        ..json('PUT', '/business/onboarding', {
          'onboarding': {'completed': true},
        });
      await pumpAs(tester, backend, Preset.owner, const BusinessScreen(), businesses: 2);
      await tester.tap(find.byKey(const Key('business-name')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('s14-add')));
      await settle(tester);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('איזה עסק יש לך?'), findsOneWidget);
      await tester.tap(find.text('עוסק פטור'));
      await settle(tester);
      await tester.enterText(find.byType(TextField).at(0), 'העסק השני');
      await tester.enterText(find.byType(TextField).at(1), '123456782');
      await tester.tap(find.byKey(const Key('setup-next')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('setup-next'))); // "סיימתי"
      await settle(tester);
      final create = backend.last('POST', '/businesses')!.body;
      expect(create, {'businessType': 'OSEK_PATUR', 'legalName': 'העסק השני', 'taxId': '123456782'});
      expect(session.business?.businessId, 'b-new');
      // The profile/onboarding writes went to the NEW business.
      expect(backend.last('PUT', '/business/onboarding')!.raw.headers['X-Business-Id'], 'b-new');
    });
  });

  group('B row "תזכורות אוטומטיות" (BE-19)', () {
    testWidgets('hidden while the server has no /settings/reminders', (tester) async {
      await pumpAs(tester, backend, Preset.owner, const BusinessScreen());
      expect(find.byKey(const Key('brow-reminders')), findsNothing);
    });

    testWidgets('switch in the row → confirm → PUT /settings/reminders; owner includes commerce settings', (tester) async {
      backend
        ..json('GET', '/settings/reminders', {'enabled': false})
        ..on('PUT', '/settings/reminders', (r) => FakeResponse(200, {'enabled': r.body['enabled']}));
      await pumpAs(tester, backend, Preset.owner, const BusinessScreen());
      expect(find.byKey(const Key('brow-reminders')), findsOneWidget);
      // Tapping the label (to read it) toggles nothing.
      await tester.tap(find.text('תזכורות אוטומטיות'));
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(backend.last('PUT', '/settings/reminders'), isNull);
      // Turning on says what will be sent; "ביטול" leaves it off.
      await tester.tap(find.byKey(const Key('reminders-switch')));
      await settle(tester);
      expect(find.text('להפעיל תזכורות אוטומטיות?'), findsOneWidget);
      await tester.tap(find.text('ביטול'));
      await settle(tester);
      expect(backend.last('PUT', '/settings/reminders'), isNull);
      await tester.tap(find.byKey(const Key('reminders-switch')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('reminders-confirm')));
      await settle(tester);
      expect(backend.last('PUT', '/settings/reminders')!.body, {'enabled': true});
      expect(find.text('תזכורות אוטומטיות פועלות'), findsOneWidget);
      final rows = find.byWidgetPredicate(
        (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('brow-'),
      );
      expect(rows.evaluate().length, lessThanOrEqualTo(12));
    });

    testWidgets('an employee never sees it', (tester) async {
      backend.json('GET', '/settings/reminders', {'enabled': true});
      await pumpAs(tester, backend, Preset.employee, const BusinessScreen());
      expect(find.byKey(const Key('brow-reminders')), findsNothing);
    });
  });

  group('13.1 פרטי העסק extras', () {
    testWidgets('BE-13 "עותק של כל מסמך אליי" → PUT /settings/document-email', (tester) async {
      backend.json('PUT', '/business/profile', {'profile': profileJson()['profile']});
      await pumpAs(tester, backend, Preset.owner, const BusinessScreen(section: 'profile'));
      expect(find.byKey(const Key('switch-autoEvery')), findsNothing); // no BE-22 yet
      expect(find.byKey(const Key('text-advanceRate')), findsNothing); // no BE-18 yet
      await reveal(tester, find.byKey(const Key('switch-ccOwner')));
      await tester.tap(find.byKey(const Key('switch-ccOwner')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('editor-save')));
      await settle(tester);
      expect(backend.last('PUT', '/settings/document-email')!.body, {'ccOwnerEmail': true});
    });

    testWidgets('unchanged copy setting is not re-sent', (tester) async {
      backend.json('PUT', '/business/profile', {'profile': profileJson()['profile']});
      await pumpAs(tester, backend, Preset.owner, const BusinessScreen(section: 'profile'));
      await tester.tap(find.byKey(const Key('editor-save')));
      await settle(tester);
      expect(backend.calls('PUT', '/settings/document-email'), isEmpty);
    });

    testWidgets('BE-22 accountant automation + BE-18 advances % when the server has them', (tester) async {
      backend
        ..json('PUT', '/business/profile', {'profile': profileJson()['profile']})
        ..json('GET', '/settings/accountant-automation', {'sendReports': null, 'forwardEveryDocument': false})
        ..on('PUT', '/settings/accountant-automation', (r) => FakeResponse(200, r.body))
        ..json('GET', '/reports/:kind', {'kpis': const [], 'columns': const [], 'rows': const []});
      await pumpAs(
        tester,
        backend,
        Preset.owner,
        const BusinessScreen(section: 'profile'),
        profile: {
          'profile': {
            ...profileJson()['profile'] as Map<String, dynamic>,
            'accountant': {'name': 'רו״ח לוי', 'email': 'cpa@tevel.test'},
            'advanceRateBasisPoints': 250,
          },
          'canConfigure': true,
        },
      );
      expect(tester.widget<TextField>(find.byKey(const Key('text-advanceRate'))).controller!.text, '2.5');
      await reveal(tester, find.byKey(const Key('choice-autoEvery-MONTH')));
      await tester.tap(find.byKey(const Key('choice-autoEvery-MONTH')));
      await settle(tester);
      await reveal(tester, find.byKey(const Key('text-autoDay')));
      await tester.enterText(find.byKey(const Key('text-autoDay')), '15');
      await reveal(tester, find.byKey(const Key('text-advanceRate')));
      await tester.enterText(find.byKey(const Key('text-advanceRate')), '3');
      await tester.tap(find.byKey(const Key('editor-save')));
      await settle(tester);
      expect(backend.last('PUT', '/business/profile')!.body['advanceRateBasisPoints'], 300);
      expect(backend.last('PUT', '/settings/accountant-automation')!.body, {
        'sendReports': {'every': 'MONTH', 'dayOfMonth': 15},
        'forwardEveryDocument': false,
      });
    });

    testWidgets('automation without the accountant e-mail → Hebrew error, nothing saved', (tester) async {
      backend
        ..json('PUT', '/business/profile', {'profile': profileJson()['profile']})
        ..json('GET', '/settings/accountant-automation', {
          'sendReports': null,
          'forwardEveryDocument': false,
        });
      await pumpAs(tester, backend, Preset.owner, const BusinessScreen(section: 'profile'));
      await reveal(tester, find.byKey(const Key('switch-autoForward')));
      await tester.tap(find.byKey(const Key('switch-autoForward')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('editor-save')));
      await settle(tester);
      expect(find.text('לשליחה אוטומטית צריך את מייל הרו״ח', skipOffstage: false), findsOneWidget);
      expect(backend.calls('PUT', '/business/profile'), isEmpty);
    });

    testWidgets('BE-43: locked פטור → ⋯ "עוברים לעוסק מורשה" → POST /business/type-change', (tester) async {
      backend.on(
        'POST',
        '/business/type-change',
        (r) => r.body.isEmpty
            ? FakeResponse.error(422, 'VALIDATION')
            : const FakeResponse(201, {'status': 'SCHEDULED'}),
      );
      await pumpAs(
        tester,
        backend,
        Preset.owner,
        const BusinessScreen(section: 'profile'),
        businessType: 'OSEK_PATUR',
      );
      await tester.tap(find.byType(MoreMenu));
      await settle(tester);
      await tester.tap(find.text('עוברים לעוסק מורשה'));
      await settle(tester);
      expect(find.text('מעבר לעוסק מורשה'), findsOneWidget);
      await tester.tap(find.text('מתחילת השנה הבאה'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('editor-save')).last);
      await settle(tester);
      final body = backend.last('POST', '/business/type-change')!.body;
      expect(body['newType'], 'OSEK_MURSHE');
      expect(body['effectiveDate'], '${DateTime.now().year + 1}-01-01');
    });

    test('advances %: "2.5" → 250 bp; out of range → null', () {
      expect(advanceBasisPoints('2.5'), 250);
      expect(advanceBasisPoints('7%'), 700);
      expect(advanceBasisPoints('101'), isNull);
      expect(advanceBasisPoints('abc'), isNull);
    });

    test('type change dates: today, 1st of next month, 1st of next year', () {
      final cfg = typeChangeEditor(now: DateTime(2026, 12, 15));
      expect(
        [for (final o in cfg.fields.single.options) o.value],
        ['2026-12-15', '2027-01-01', '2027-01-01'],
      );
    });
  });

  group('BE-04 accountant role', () {
    testWidgets('server with ACCOUNTANT_REP: one invite with that role, no grants', (tester) async {
      backend.on(
        'POST',
        '/business/members/invite',
        (r) => FakeResponse(201, {
          'invitationId': 'i-rep',
          'inviteUrl': 'https://app.test/m/invite/x',
          'role': r.body['role'],
          'permissions': const [],
        }),
      );
      await pumpAs(tester, backend, Preset.owner, const TeamPage());
      await tester.tap(find.byKey(const Key('team-invite-accountant')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('text-email')), 'cpa@tevel.test');
      await tester.tap(find.byKey(const Key('editor-save')));
      await settle(tester);
      final calls = backend.calls('POST', '/business/members/invite');
      expect(calls, hasLength(1));
      expect(calls.single.body, {'email': 'cpa@tevel.test', 'role': 'ACCOUNTANT_REP'});
    });

    testWidgets('server without it (today): falls back to READ_ONLY + expense grants', (tester) async {
      await pumpAs(tester, backend, Preset.owner, const TeamPage());
      await tester.tap(find.byKey(const Key('team-invite-accountant')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('text-email')), 'cpa@tevel.test');
      await tester.tap(find.byKey(const Key('editor-save')));
      await settle(tester);
      final calls = backend.calls('POST', '/business/members/invite');
      expect([for (final c in calls) c.body['role']], ['ACCOUNTANT_REP', 'READ_ONLY']);
      expect(calls.last.body['permissions'], ['expense:record', 'expense:approve']);
    });

    test('an ACCOUNTANT_REP member is the accountant preset, not "מותאם אישית"', () {
      expect(presetOf('ACCOUNTANT_REP', const []), Preset.accountantRep);
      expect(hasCustomGrants('ACCOUNTANT_REP', const []), isFalse);
    });
  });

  group('BE-49 ownership transfer', () {
    void serveTransfer(FakeBackend b) => b.on('POST', '/business/ownership/transfer', (r) {
      if (r.body.isEmpty) return FakeResponse.error(422, 'VALIDATION');
      final code = r.body['code'];
      if (code == null) {
        return const FakeResponse(202, {'status': 'CODE_SENT', 'sentTo': 'm***@tevel.test'});
      }
      if (code != '123456') return FakeResponse.error(422, 'OWNERSHIP_CODE_INVALID');
      return const FakeResponse(200, {'status': 'TRANSFERRED'});
    });

    testWidgets('no ⋯ item while the server has no transfer route', (tester) async {
      await pumpAs(tester, backend, Preset.owner, const TeamPage());
      await tester.tap(find.byKey(const Key('member-u-partner')));
      await settle(tester);
      await tester.tap(find.byType(MoreMenu).last);
      await settle(tester);
      expect(find.text('העבר בעלות'), findsNothing);
    });

    testWidgets('owner → member ⋯ "העבר בעלות" → red confirm → code (wrong, then right)', (tester) async {
      serveTransfer(backend);
      await pumpAs(tester, backend, Preset.owner, const TeamPage());
      await tester.tap(find.byKey(const Key('member-u-partner')));
      await settle(tester);
      await tester.tap(find.byType(MoreMenu).last);
      await settle(tester);
      await tester.tap(find.text('העבר בעלות'));
      await settle(tester);
      expect(find.text('להעביר את הבעלות ל-יוסי?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm-danger')));
      await settle(tester);
      expect(find.text('שלחנו קוד ל-m***@tevel.test'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('transfer-code')), '000000');
      await tester.tap(find.byKey(const Key('transfer-confirm')));
      await settle(tester);
      expect(find.text('הקוד שגוי. נסה שוב.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('transfer-code')), '123456');
      await tester.tap(find.byKey(const Key('transfer-confirm')));
      await settle(tester);
      final bodies = [for (final c in backend.calls('POST', '/business/ownership/transfer')) c.body];
      expect(bodies.where((b) => b.isNotEmpty), [
        {'toUserId': 'u-partner'},
        {'toUserId': 'u-partner', 'code': '000000'},
        {'toUserId': 'u-partner', 'code': '123456'},
      ]);
      expect(find.text('הבעלות הועברה ל-יוסי'), findsOneWidget);
    });

    testWidgets('a partner never gets the item', (tester) async {
      serveTransfer(backend);
      await pumpAs(tester, backend, Preset.partner, const TeamPage());
      await tester.tap(find.byKey(const Key('member-u-emp')));
      await settle(tester);
      await tester.tap(find.byType(MoreMenu).last);
      await settle(tester);
      expect(find.text('העבר בעלות'), findsNothing);
    });

    testWidgets('sole-owner delete warning offers "העבר בעלות" when the server has it', (tester) async {
      serveTransfer(backend);
      await pumpAs(tester, backend, Preset.owner, const BusinessScreen(section: 'account'));
      await tester.ensureVisible(find.byKey(const Key('account-delete')));
      await tester.tap(find.byKey(const Key('account-delete')));
      await settle(tester);
      expect(find.byType(SoleOwnerWarning), findsOneWidget);
      expect(find.byKey(const Key('delete-transfer')), findsOneWidget);
      await tester.tap(find.byKey(const Key('delete-transfer')));
      await settle(tester);
      expect(find.byType(TeamPage), findsOneWidget);
    });
  });
}
