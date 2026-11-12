// ignore_for_file: file_names
// QA gate · SPEC-v2 §17 acceptance tests for A (gate, MFA, invitation,
// setup), team invites (J8/J8b), the accountant home (J9), switching
// business (J12), live role change and account deletion. Owner: QA.
//
// Real app against the LOCAL dev API (never prod). State is set up and
// verified with direct API calls (v2_qa_gate_helpers.dart). Throwaway
// accounts are `qa-gate-*@tevel.test`; the suite deletes them again.
// Only the single simulator runner executes this file:
//
//   ~/flutter/bin/flutter test integration_test/v2_qa-gate_test.dart -d <udid> \
//     --dart-define=API_BASE=http://127.0.0.1:3031 \
//     --dart-define=MAILDIR=$HOME/invoiceproject-mobile-dev-storage/outgoing-emails
//
// Items of A that have no AT number in §17 are tagged with their spec section.
// The tests share one throwaway employee ("T") in order; each test can also
// create what it needs when an earlier one failed (ensureTester / ensureTesterBusiness).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/api/client.dart' show ApiException;
import 'package:invoice/api/settings_api.dart' show deleteAccountErrorHe;
import 'package:invoice/app_shell.dart';
import 'package:invoice/main.dart' as app;
import 'package:invoice/router.dart' show navigatorKey;
import 'package:invoice/screens/auth/invite_screen.dart';
import 'package:invoice/screens/auth/login_screen.dart';
import 'package:invoice/screens/auth/onboarding_screen.dart';
import 'package:invoice/screens/business/account_page.dart' show SoleOwnerWarning;
import 'package:invoice/screens/business/delete_account_screen.dart';
import 'package:invoice/screens/home/home_screen.dart';
import 'package:invoice/screens/reports/reports_screen.dart';
import 'package:invoice/state/business_context.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/session.dart';
import 'package:invoice/util/errors_he.dart';
import 'package:invoice/util/labels/labels.dart';

import 'v2_qa_gate_helpers.dart';
import 'qa_plans_guard.dart';

Finder byKey(String k) => find.byKey(Key(k));

/// The header text of H for [name].
Finder homeBusinessName(String name) =>
    find.byWidgetPredicate((w) => w is Text && w.key == const Key('home-business-name') && w.data == name);

/// Role tag text on H ("עובד", "צפייה בלבד" …).
String? roleTagText(WidgetTester tester) {
  final tag = byKey('home-role-tag');
  if (tag.evaluate().isEmpty) return null;
  return tester.widget<Text>(find.descendant(of: tag, matching: find.byType(Text)).first).data;
}

/// §6.R period label computed from /me.vatReporting on its own (not with the
/// app's ReportPeriod): MONTHLY → "10.2026", BIMONTHLY/null → "9–10.2026",
/// NONE → "2026".
String expectedVatPeriodLabel(String? vatReporting, DateTime now) {
  if (vatReporting == 'NONE') return '${now.year}';
  final months = vatReporting == 'MONTHLY' ? 1 : 2;
  final start = ((now.month - 1) ~/ months) * months + 1;
  final end = start + months - 1;
  return start == end ? '$start.${now.year}' : '$start–$end.${now.year}';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  dismissPlansDuringTests();

  late DevSession owner;
  final invitationIds = <String>[];

  // The throwaway employee "T".
  String? testerEmail;
  String? testerUserId;
  String? testerUsedToken;
  String? testerBusinessId;
  String? testerBusinessName;
  var testerDeleted = false;

  Future<void> ensureTester() async {
    if (testerEmail != null) return;
    final email = uniqueEmail('t');
    final (id, token) = await devInvite(owner, email);
    invitationIds.add(id);
    await devAcceptInvite(token, testerPassword);
    testerEmail = email;
    testerUsedToken = token;
    testerUserId = '${(await devFindMember(owner, email))!['userId']}';
  }

  /// T owns a second, fully set-up business (normally made by the AT-29 test).
  Future<void> ensureTesterBusiness() async {
    await ensureTester();
    if (testerBusinessId != null) return;
    final t = await devSignIn(testerEmail!, password: testerPassword);
    final name = 'QA שער ${DateTime.now().millisecondsSinceEpoch % 100000}';
    final created = await t.post('/businesses', {'businessType': 'OSEK_PATUR', 'legalName': name});
    await t.logout();
    testerBusinessId = '${created['businessId']}';
    testerBusinessName = name;
    final asOwner = await devSignIn(testerEmail!, password: testerPassword, businessId: testerBusinessId);
    // Same order as the app's setup: profile first (onboarding refuses an empty one).
    await asOwner.put('/business/profile', {'legalName': name, 'businessType': 'OSEK_PATUR', 'taxId': '123456782'});
    await asOwner.put('/business/onboarding', {'completed': true});
    await asOwner.logout();
  }

  setUpAll(() async {
    owner = await devSignIn(ownerEmail);
  });

  tearDownAll(() async {
    for (final id in invitationIds) {
      await devRevokeInvitation(owner, id);
    }
    if (testerEmail != null && !testerDeleted) {
      try {
        final t = await devSignIn(testerEmail!, password: testerPassword);
        await t.post('/mobile/account/delete', {'confirm': 'DELETE', 'password': testerPassword});
      } on Object catch (e) {
        debugPrint('QA-GATE cleanup: could not delete $testerEmail: $e');
      }
    }
    await resetDevice();
    await owner.logout();
  });

  // ---- A · gate --------------------------------------------------------------

  testWidgets('§6.A gate (no AT no.): wrong password → INVALID_CREDENTIALS in Hebrew, stays on sign-in',
      (tester) async {
    await launchSignedOut(tester);
    await tester.enterText(find.byType(TextField).at(0), staffEmail);
    await tester.enterText(find.byType(TextField).at(1), 'not-the-password-1');
    await tapOn(tester, find.text('כניסה'));
    await pumpUntil(tester, find.text(errorMessageHe('INVALID_CREDENTIALS')), reason: 'Hebrew INVALID_CREDENTIALS');
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
  });

  testWidgets('§6.A gate (no AT no.): a revoked device token → 401 → sign-in with "פג תוקף ההתחברות"',
      (tester) async {
    await resetDevice();
    final s = await devSignIn(staffEmail);
    await s.logout(); // revoked from "another device"
    await keychain.write(key: 'device_token', value: s.token);
    await keychain.write(key: 'business_id', value: devBusinessId);
    app.main();
    await pumpUntil(tester, find.textContaining('פג תוקף ההתחברות'), reason: 'expired notice');
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(session.status, SessionStatus.signedOut);
  });

  testWidgets('§6.A MFA (no AT no.): owner → blocking e-mail code step "שלחנו קוד ל-mo***" → home with owner caps',
      (tester) async {
    await launchSignedOut(tester);
    await signInThroughUi(
      tester,
      ownerEmail,
      devPassword,
      expectSentTo: 'mo***@tevel.test',
      pickBusinessId: devBusinessId,
      until: find.byType(HomeScreen),
    );
    expect(find.byType(AppShell), findsOneWidget);
    expect(session.business?.businessId, devBusinessId);
    expect(session.me?.role, 'OWNER');
    expect(businessContext.caps.preset, Preset.owner);
    expect(byKey('home-role-tag'), findsNothing, reason: 'no role tag for the owner (§6.H)');
    expect(byKey('tab-create'), findsOneWidget);
  });

  // ---- J9 · accountant home --------------------------------------------------

  testWidgets('AT-26 (P0b) J9 + AT-44: accountant signs in → home tab is R on the /me.vatReporting period; no ＋',
      (tester) async {
    final s = await launchSignedInAs(tester, cpaRepEmail);
    await pumpUntil(tester, find.byType(AppShell), reason: 'app shell');
    await pumpUntil(tester, find.byType(ReportsScreen), reason: 'R as the home tab');
    expect(find.byType(HomeScreen), findsNothing);
    expect(businessContext.caps.homeIsReports, isTrue);
    expect(byKey('tab-create'), findsNothing, reason: 'AT-44: no ＋ for the accountant');
    final me = await s.get('/me');
    final label = expectedVatPeriodLabel(me['vatReporting'] as String?, DateTime.now());
    await pumpUntil(tester, find.textContaining(label), reason: 'VAT period $label on R');
  });

  // ---- J8 / J8b · invitations -------------------------------------------------

  testWidgets('AT-24 (P0b) J8: owner invites an employee in 4 taps → invitation with role EMPLOYEE',
      (tester) async {
    await launchSignedInAs(tester, ownerEmail);
    await pumpUntil(tester, find.byType(HomeScreen), reason: 'home');
    final email = uniqueEmail('j8');
    final taps = TapCounter();
    await taps.tap(tester, byKey('tab-business')); // (1) עסק
    await pumpUntilScrolled(tester, byKey('brow-team')); // below the quick actions; scrolling is not a tap
    await taps.tap(tester, byKey('brow-team')); // (2) צוות והרשאות
    await taps.tap(tester, byKey('team-invite')); // (3) + הזמן
    await pumpUntil(tester, byKey('text-email'));
    await tester.enterText(byKey('text-email'), email); // auto focus: not counted
    expect(byKey('choice-preset-employee'), findsOneWidget, reason: 'preset עובד by default');
    await taps.tap(tester, byKey('editor-save')); // (4) שלח הזמנה
    await pumpUntilScrolled(tester, find.text(email), reason: 'pending invitation row');
    expect(taps.count, 4);

    final row = await devFindInvitation(owner, email);
    expect(row, isNotNull, reason: 'invitation on the server');
    invitationIds.add('${row!['id']}');
    expect(row['role'], 'EMPLOYEE');
    expect(row['permissions'] as List? ?? const [], isEmpty);
    await devRevokeInvitation(owner, '${row['id']}');
  });

  testWidgets('AT-25 (P2) J8b: owner invites an accountant in 4 taps → invitation with role ACCOUNTANT_REP',
      (tester) async {
    await launchSignedInAs(tester, ownerEmail);
    await pumpUntil(tester, find.byType(HomeScreen), reason: 'home');
    final email = uniqueEmail('j8b');
    final taps = TapCounter();
    await taps.tap(tester, byKey('tab-business')); // (1)
    await pumpUntilScrolled(tester, byKey('brow-team'));
    await taps.tap(tester, byKey('brow-team')); // (2)
    await taps.tap(tester, byKey('team-invite-accountant')); // (3) הזמן רואה חשבון
    await pumpUntil(tester, byKey('text-email'));
    await tester.enterText(byKey('text-email'), email);
    await taps.tap(tester, byKey('editor-save')); // (4)
    await pumpUntilScrolled(tester, find.text(email), reason: 'pending invitation row');
    expect(taps.count, 4);

    final row = await devFindInvitation(owner, email);
    expect(row, isNotNull);
    invitationIds.add('${row!['id']}');
    expect(row['role'], 'ACCOUNTANT_REP', reason: 'P2 (BE-04): the representing accountant role');
    await devRevokeInvitation(owner, '${row['id']}');
  });

  // ---- A · invitation ---------------------------------------------------------

  testWidgets('§6.A invitation (AT-24 → join): a new employee joins from the invite screen → home tagged "עובד"',
      (tester) async {
    final email = uniqueEmail('t');
    final (id, token) = await devInvite(owner, email);
    invitationIds.add(id);
    await launchSignedOut(tester);
    // The universal link /m/invite/:token opens this screen (BE-00 §5).
    navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => InviteScreen(token: token)));
    await pumpUntil(
      tester,
      find.text(AuthHe.invitedTo(devBusinessName, PresetHe.label(Preset.employee))),
      reason: '"הוזמנת ל-{עסק} כעובד"',
    );
    await tester.enterText(find.byType(TextField).first, 'בודק QA');
    await tester.enterText(byKey('invite-password'), testerPassword);
    FocusManager.instance.primaryFocus?.unfocus();
    await tapOn(tester, byKey('invite-join'));
    await pumpUntil(tester, find.byType(HomeScreen), reason: 'home after joining');

    testerEmail = email;
    testerUsedToken = token;
    testerUserId = '${(await devFindMember(owner, email))!['userId']}';
    expect(roleTagText(tester), presetTagLabels[Preset.employee]);
    expect(session.me?.role, 'EMPLOYEE');
    final t = await devSignIn(email, password: testerPassword);
    expect((await t.get('/me'))['role'], 'EMPLOYEE');
    await t.logout();
  });

  testWidgets('§6.A invitation states (no AT no.): used and revoked links → "ההזמנה כבר לא בתוקף", no join button',
      (tester) async {
    await ensureTester();
    final revokedEmail = uniqueEmail('rv');
    final (revokedId, revokedToken) = await devInvite(owner, revokedEmail);
    await devRevokeInvitation(owner, revokedId);

    await launchSignedOut(tester);
    for (final token in [testerUsedToken!, revokedToken]) {
      navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => InviteScreen(token: token)));
      await pumpUntil(tester, find.textContaining('ההזמנה כבר לא בתוקף'), reason: 'dead invitation');
      expect(byKey('invite-join'), findsNothing);
      navigatorKey.currentState!.pop();
      await pumpUntilGone(tester, find.byType(InviteScreen));
    }
  });

  // ---- team member editor -----------------------------------------------------

  testWidgets('AT-50 (P0b): S13 "חבר צוות" for an employee shows only the presets + "מפיק בעצמו"', (tester) async {
    await ensureTester();
    await launchSignedInAs(tester, ownerEmail);
    await pumpUntil(tester, find.byType(HomeScreen), reason: 'home');
    await tapOn(tester, byKey('tab-business'));
    await pumpUntilScrolled(tester, byKey('brow-team'));
    await tapOn(tester, byKey('brow-team'));
    // The dev team list keeps growing (deleted QA accounts stay listed), so the
    // tester's row can be below the fold of the lazy list: scroll to it first.
    for (var i = 0; i < 40 && find.byType(Scrollable).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.pump(const Duration(seconds: 2));
    await tester.scrollUntilVisible(byKey('member-$testerUserId'), 300, scrollable: find.byType(Scrollable).last);
    await tapOn(tester, byKey('member-$testerUserId'));
    await pumpUntil(tester, byKey('switch-issuer'), reason: '"מפיק בעצמו"');

    expect(find.text(TeamHe.issuer), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget, reason: 'the only toggle is "מפיק בעצמו"');
    final toggles = find.byWidgetPredicate(
        (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('switch-'));
    expect(toggles, findsOneWidget, reason: 'no settings / team toggles in "חבר צוות"');
    for (final p in [Preset.employee, Preset.partner, Preset.accountantRep]) {
      expect(byKey('choice-preset-${p.name}'), findsOneWidget, reason: 'preset ${p.name}');
    }
    Navigator.of(tester.element(byKey('switch-issuer'))).pop(false);
    await pumpUntilGone(tester, byKey('switch-issuer'));
  });

  // ---- §4.6 · role change from another device ---------------------------------

  testWidgets('AT-46 (P0b): role changed from another device → back to foreground → UI updates', (tester) async {
    await ensureTester();
    await launchSignedInAs(tester, testerEmail!, password: testerPassword);
    await pumpUntil(tester, find.byType(HomeScreen), reason: 'home');
    await pumpUntil(tester, byKey('home-role-tag'));
    expect(roleTagText(tester), presetTagLabels[Preset.employee]);
    expect(byKey('tab-create'), findsOneWidget, reason: 'employee drafts → ＋');

    try {
      // The owner, on another device, makes T "צפייה בלבד".
      await owner.put('/business/members/$testerUserId/role', {'role': 'READ_ONLY'});
      await owner.put('/business/members/$testerUserId/permissions', {'permissions': <String>[]});

      // > 60 s in the background (§4.6 refresh rule), then foreground.
      session.meFetchedAt = DateTime.now().subtract(const Duration(minutes: 2));
      final binding = tester.binding;
      for (final s in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        // No pump between states: on the device binding frames are disabled
        // while hidden/paused, so a pump there never completes (it hung).
        binding.handleAppLifecycleStateChanged(s);
      }
      await tester.pump(const Duration(milliseconds: 100));
      await pumpUntilGone(tester, byKey('tab-create'), reason: '＋ after the role change');
      expect(businessContext.caps.preset, Preset.viewer);
      expect(roleTagText(tester), presetTagLabels[Preset.viewer]);
    } finally {
      await owner.put('/business/members/$testerUserId/role', {'role': 'EMPLOYEE'});
      await owner.put('/business/members/$testerUserId/permissions', {'permissions': <String>[]});
    }
  });

  // ---- A · MFA enrolment + S14 + setup, then J12 --------------------------------

  testWidgets(
      'AT-29 (P0b) J12 + §6.A MFA enrolment + S14 + setup: new owner sets up, then switches business in 2 taps; '
      'caps and cache reset', (tester) async {
    await ensureTester();
    // T opens a second business (BE-40) → OWNER there → MFA becomes required.
    final t = await devSignIn(testerEmail!, password: testerPassword);
    final name = 'QA שער ${DateTime.now().millisecondsSinceEpoch % 100000}';
    final created = await t.post('/businesses', {'businessType': 'OSEK_MURSHE', 'legalName': name});
    await t.logout();
    testerBusinessId = '${created['businessId']}';
    testerBusinessName = name;

    await launchSignedOut(tester);
    await signInThroughUi(
      tester,
      testerEmail!,
      testerPassword,
      wrongCodeFirst: true, // also: a wrong code keeps the step (MFA_CODE_INVALID)
      pickBusinessId: testerBusinessId, // S14 is required with two businesses
      until: find.byType(OnboardingScreen),
    );

    // Setup (§6.A): type → name + id → "כבר הפקת…?" לא → סיימתי.
    await pumpUntil(tester, find.text(AuthHe.setupStep(1)));
    await tapOn(tester, find.text(businessTypeLabels['OSEK_PATUR']!));
    await pumpUntil(tester, find.text(AuthHe.setupStep(2)));
    expect(find.text(name), findsOneWidget, reason: 'business name prefilled');
    await tester.enterText(find.byType(TextField).at(1), '123456782');
    await tapOn(tester, byKey('setup-next'));
    await pumpUntil(tester, find.text(AuthHe.setupStep(3)));
    await tapOn(tester, byKey('setup-next')); // סיימתי
    await pumpUntil(tester, find.byType(HomeScreen), reason: 'home after setup');
    await pumpUntil(tester, homeBusinessName(name));
    expect(businessContext.caps.preset, Preset.owner);

    final asOwner = await devSignIn(testerEmail!, password: testerPassword, businessId: testerBusinessId);
    final me = await asOwner.get('/me');
    expect((me['onboarding'] as Map)['completed'], isTrue);
    expect(me['businessType'], 'OSEK_PATUR');
    final profile = (await asOwner.get('/business/profile'))['profile'] as Map<String, dynamic>;
    expect(profile['taxId'], '123456782');
    await asOwner.logout();

    // J12: (1) business name in the header → (2) the other business.
    final taps = TapCounter();
    await taps.tap(tester, byKey('home-switch-business'));
    await taps.tap(tester, byKey('s14-$devBusinessId'));
    await pumpUntil(tester, homeBusinessName(devBusinessName), reason: 'home of the other business');
    expect(taps.count, 2);
    expect(session.business?.businessId, devBusinessId);
    final member = await devFindMember(owner, testerEmail!);
    expect(session.me?.role, member!['role'], reason: '/me re-read for the new business');
    expect(businessContext.caps.preset, isNot(Preset.owner), reason: 'caps reset to the membership there');
    expect(roleTagText(tester), presetTagLabels[businessContext.caps.preset]);
    expect(session.profile?.legalName, devBusinessName, reason: 'profile reloaded');
    expect(homeBusinessName(name), findsNothing);
  });

  // ---- §13.15 · delete account -------------------------------------------------

  testWidgets(
      '§13.15 delete account (no AT no.; App Store 5.1.1(v)): sole owner → warning → wrong password refused → '
      'password + "מחק" → signed out; login refused', (tester) async {
    await ensureTesterBusiness();
    await launchSignedInAs(tester, testerEmail!, password: testerPassword, businessId: testerBusinessId!);
    await pumpUntil(tester, find.byType(HomeScreen), reason: 'home');
    await pumpUntil(tester, homeBusinessName(testerBusinessName!));

    await tapOn(tester, byKey('tab-business'));
    await pumpUntilScrolled(tester, byKey('brow-account'));
    await tapOn(tester, byKey('brow-account'));
    await pumpUntilScrolled(tester, byKey('account-delete')); // last row of a lazy list
    await tapOn(tester, byKey('account-delete'));
    await pumpUntil(tester, find.byType(SoleOwnerWarning), reason: 'sole-owner warning');
    expect(find.textContaining(testerBusinessName!), findsWidgets, reason: 'names the business that closes');
    await tapOn(tester, byKey('delete-anyway'));
    await pumpUntil(tester, find.byType(DeleteAccountScreen));

    // The screen is a lazy ListView: the confirm field can be below the fold,
    // so each field is found by its own trait and scrolled into view.
    final passwordField = find.byWidgetPredicate((w) => w is TextField && w.obscureText);
    final confirmField =
        find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == deleteConfirmWord);
    await pumpUntilScrolled(tester, passwordField);
    await tester.enterText(passwordField, 'wrong-password-123');
    await pumpUntilScrolled(tester, confirmField);
    await tester.enterText(confirmField, deleteConfirmWord);
    FocusManager.instance.primaryFocus?.unfocus();
    await pumpUntilScrolled(tester, find.text('מחיקת החשבון לצמיתות'));
    await tapOn(tester, find.text('מחיקת החשבון לצמיתות'));
    await pumpUntilScrolled(tester, find.text(deleteAccountErrorHe(ApiException(403, 'REAUTH_FAILED', ''))),
        reason: 'REAUTH_FAILED in Hebrew');
    expect(find.byType(DeleteAccountScreen), findsOneWidget, reason: 'still signed in after a wrong password');

    await pumpUntilScrolled(tester, passwordField);
    await tester.enterText(passwordField, testerPassword);
    FocusManager.instance.primaryFocus?.unfocus();
    await pumpUntilScrolled(tester, find.text('מחיקת החשבון לצמיתות'));
    await tapOn(tester, find.text('מחיקת החשבון לצמיתות'));
    await pumpUntil(tester, find.byType(LoginScreen), reason: 'sign-in after deletion');
    testerDeleted = true;
    expect(session.status, SessionStatus.signedOut);
    expect(await devLoginStatus(testerEmail!, testerPassword), 'INVALID_CREDENTIALS');
    expect(await devFindMember(owner, testerEmail!), isNull, reason: 'membership revoked');
  });
}
