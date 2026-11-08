// B · עסק list, S13 settings instances, B·חשבון, רשות המסים, S14
// (SPEC-v2 §6.B, §13, §4.4; AT-29, AT-43b, AT-49, AT-90, AT-96; J12).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/settings_api.dart';
import 'package:invoice/screens/business/account_page.dart';
import 'package:invoice/screens/business/business_screen.dart';
import 'package:invoice/screens/business/branding_screen.dart';
import 'package:invoice/screens/business/delete_account_screen.dart';
import 'package:invoice/screens/business/shaam_page.dart';
import 'package:invoice/screens/reports/reports_screen.dart';
import 'package:invoice/screens/business/sheets/editor_configs.dart';
import 'package:invoice/screens/business/sheets/s14_switch.dart';
import 'package:invoice/state/business_context.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/session.dart';
import 'package:invoice/ui/ds.dart';

import '../fakes/fake_api.dart';
import 'e_harness.dart';

void main() {
  late FakeBackend backend;
  setUp(() async => backend = await eSetUp());

  group('§4.4 rows per preset (hidden, not disabled)', () {
    Future<List<String>> rowsFor(Preset p, {int members = 3}) async {
      final b = FakeBackend()..install();
      await signInAs(b, p);
      return [for (final r in businessRows(businessContext.caps, memberCount: members)) r.key];
    }

    test('owner: commerce rows in order; approvals only with another member', () async {
      expect(await rowsFor(Preset.owner), [
        'reports',
        'expenses',
        'team',
        'profile',
        'branding',
        'approvals',
        'shaam',
        'integrations',
        'subscription',
        'account',
        'desktop',
      ]);
      expect(await rowsFor(Preset.owner, members: 1), isNot(contains('approvals')));
      expect((await rowsFor(Preset.owner)).length, lessThanOrEqualTo(12));
    });

    test('partner = owner rows; employee: expenses + account only', () async {
      expect(await rowsFor(Preset.partner),
          (await rowsFor(Preset.owner)).where((row) => row != 'subscription').toList());
      expect(await rowsFor(Preset.employee), ['expenses', 'account']);
      expect(await rowsFor(Preset.employeeIssuer), ['expenses', 'account']);
    });

    test('accountant (P0): reports live on the home tab; viewer: account only', () async {
      expect(await rowsFor(Preset.accountantRep), ['expenses', 'shaam', 'account', 'desktop']);
      expect(await rowsFor(Preset.viewer), ['account']);
    });
  });

  testWidgets('owner list: business name header, rows, no PrimaryButton (read screen)', (tester) async {
    await pumpAs(tester, backend, Preset.owner, const BusinessScreen());
    expect(find.text('סטודיו תבל'), findsOneWidget);
    expect(find.text('צוות והרשאות'), findsOneWidget);
    expect(find.text('דוחות'), findsOneWidget);
    expect(find.byType(PrimaryButton), findsNothing);
    expect(find.text('החלף'), findsNothing); // one business → no S14
    for (final word in ['אין הרשאה', 'מנוי', 'שדרג']) {
      expect(find.textContaining(word), findsNothing);
    }
  });

  testWidgets('employee sees no team / settings rows at all (F5)', (tester) async {
    await pumpAs(tester, backend, Preset.employee, const BusinessScreen());
    expect(find.text('צוות והרשאות'), findsNothing);
    expect(find.text('מיתוג'), findsNothing);
    expect(find.text('דוחות'), findsNothing);
    expect(find.text('החשבון שלי'), findsOneWidget);
  });

  testWidgets('S13 13.1 פרטי העסק: identity locked, save PUTs the profile', (tester) async {
    backend.json('PUT', '/business/profile', {'profile': profileJson()['profile']});
    await pumpAs(tester, backend, Preset.owner, const BusinessScreen());
    await tester.tap(find.byKey(const Key('brow-profile')));
    await settle(tester);
    expect(find.text('זהות העסק'), findsOneWidget);
    expect(find.text('פרטי קשר'), findsOneWidget);
    expect(find.text('חשבוניות ומיסוי'), findsOneWidget);
    expect(find.text('פרטי תשלום'), findsOneWidget);
    expect(find.text('רואה החשבון'), findsOneWidget);
    expect(find.text('אחרי הפקה ראשונה לא משנים סוג עסק כאן – המשך במחשב'), findsOneWidget);
    expect(find.byType(PrimaryButton), findsOneWidget);
    await tester.enterText(find.byKey(const Key('text-legalName')), 'סטודיו תבל בע"מ');
    await tester.enterText(find.byKey(const Key('text-paymentLinkUrl')), 'http://bad');
    await tester.tap(find.byKey(const Key('editor-save')));
    await settle(tester);
    expect(find.text('הקישור חייב להתחיל ב-https:// ובלי רווחים'), findsOneWidget);
    expect(backend.calls('PUT', '/business/profile'), isEmpty);
    await tester.enterText(find.byKey(const Key('text-paymentLinkUrl')), 'https://pay.test/x');
    await tester.tap(find.byKey(const Key('editor-save')));
    await settle(tester);
    final body = backend.last('PUT', '/business/profile')!.body;
    expect(body['legalName'], 'סטודיו תבל בע"מ');
    expect(body['paymentLinkUrl'], 'https://pay.test/x');
    expect(body.containsKey('businessType'), isFalse); // locked identity never resent
    expect(body.containsKey('taxId'), isFalse);
    expect(find.text('נשמר ✓'), findsOneWidget);
  });

  testWidgets('S13 13.6 אישורים, sole approver: no self switch, selfApprovalAllowed:true (AT-43b)', (
    tester,
  ) async {
    backend.json(
      'GET',
      '/business/members',
      teamJson(members: [memberJson('u-me', 'OWNER', self: true), memberJson('u-emp', 'EMPLOYEE')]),
    );
    await pumpAs(tester, backend, Preset.owner, const BusinessScreen());
    await tester.tap(find.byKey(const Key('brow-approvals')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('switch-enabled')));
    await settle(tester);
    expect(find.byKey(const Key('switch-notSelf')), findsNothing);
    await tester.enterText(find.byKey(const Key('text-threshold')), '5000');
    await tester.tap(find.byKey(const Key('editor-save')));
    await settle(tester);
    expect(backend.last('PUT', '/settings/approval')!.body, {
      'mode': 'THRESHOLD',
      'thresholdMinor': '500000',
      'selfApprovalAllowed': true,
    });
  });

  testWidgets(
    'S13 13.6 with another approver: "גם מסמכים שאני יוצר…" → selfApprovalAllowed:false; 422 shown',
    (tester) async {
      backend
        ..json(
          'GET',
          '/business/members',
          teamJson(
            members: [
              memberJson('u-me', 'OWNER', self: true),
              memberJson('u-p', 'ADMIN', name: 'יוסי'),
            ],
          ),
        )
        ..error('PUT', '/settings/approval', 422, 'APPROVAL_NO_OTHER_APPROVER');
      await pumpAs(tester, backend, Preset.owner, const BusinessScreen());
      await tester.tap(find.byKey(const Key('brow-approvals')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('switch-enabled')));
      await settle(tester);
      expect(find.text('גם מסמכים שאני יוצר צריכים אישור של יוסי'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('text-threshold')), '5000');
      await tester.tap(find.byKey(const Key('switch-notSelf')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('editor-save')));
      await settle(tester);
      expect(backend.last('PUT', '/settings/approval')!.body['selfApprovalAllowed'], isFalse);
      expect(find.text('אין בעסק מאשר נוסף — אי אפשר לחייב אישור של מישהו אחר'), findsOneWidget);
    },
  );

  testWidgets('S13 13.9 המשך במחשב → POST /mobile/web-handoff {topic}; 404 → mailto to self', (tester) async {
    final launcher = FakeLauncher()..install();
    addTearDown(FakeLauncher.uninstall);
    await pumpAs(tester, backend, Preset.owner, const BusinessScreen());
    await tester.tap(find.byKey(const Key('brow-desktop')));
    await settle(tester);
    expect(find.text('רשות המסים'), findsOneWidget);
    await tester.tap(find.byKey(const Key('choice-topic-TAX_AUTHORITY')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('editor-save')));
    await settle(tester);
    expect(backend.last('POST', '/mobile/web-handoff')!.body, {'topic': 'TAX_AUTHORITY'});
    expect(find.text('שלחנו לך קישור למייל'), findsOneWidget);

    backend.off('POST', '/mobile/web-handoff');
    await tester.runAsync(() => sendWebHandoff('INVENTORY', 'מלאי'));
    expect(launcher.last.toString(), startsWith('mailto:me@tevel.test?subject='));
  });

  testWidgets('S13 13.2 מיתוג: colour + logo, whole branding object sent back', (tester) async {
    final png = File('assets/brand/tevel_mark.png').readAsBytesSync();
    logoPicker = () async => png;
    await pumpAs(tester, backend, Preset.owner, const BusinessScreen());
    await tester.tap(find.byKey(const Key('brow-branding')));
    await settle(tester);
    expect(find.byType(BrandingScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('color-#0b6e4f')));
    await tester.ensureVisible(find.byKey(const Key('logo-pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logo-pick')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('editor-save')));
    await settle(tester);
    final body = backend.last('PUT', '/settings/branding')!.body;
    expect(body['accentColor'], '#0b6e4f');
    expect(body['template'], 'modern'); // kept from the web
    expect(body['headerNote'], 'כותרת');
    expect(body['logoDataUri'] as String, startsWith('data:image/png;base64,'));
    expect((body['logoDataUri'] as String).length, lessThanOrEqualTo(700000));
  });

  testWidgets('B·חשבון: logout-all after a red confirm; hide amounts switch', (tester) async {
    await pumpAs(tester, backend, Preset.employee, const AccountPage());
    expect(find.text('me@tevel.test'), findsNothing); // LTR isolated
    expect(find.textContaining('me@tevel.test'), findsOneWidget);
    expect(find.byType(PrimaryButton), findsNothing);
    await tester.tap(find.byKey(const Key('account-hide-amounts')));
    await settle(tester);
    expect(hideAmounts.value, isTrue);
    await tester.runAsync(() => setHideAmounts(false));

    await tester.ensureVisible(find.byKey(const Key('account-signout-all')));
    await tester.tap(find.byKey(const Key('account-signout-all')));
    await settle(tester);
    expect(find.text('לצאת מכל המכשירים?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-danger')));
    await settle(tester);
    expect(backend.calls('POST', '/mobile/logout-all'), hasLength(1));
    expect(session.status, SessionStatus.signedOut);
  });

  testWidgets('sole owner → warning lists who loses access → "מחק בכל זאת" → delete screen (§13.15)', (
    tester,
  ) async {
    await pumpAs(tester, backend, Preset.owner, const AccountPage());
    await tester.scrollUntilVisible(find.byKey(const Key('account-delete')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('account-delete')));
    await settle(tester);
    expect(find.byType(SoleOwnerWarning), findsOneWidget);
    expect(find.textContaining('2 חברי צוות (יוסי, רון)'), findsOneWidget);
    expect(find.textContaining('7 שנים'), findsOneWidget);
    await tester.tap(find.byKey(const Key('delete-anyway')));
    await settle(tester);
    expect(find.byType(DeleteAccountScreen), findsOneWidget);
  });

  testWidgets('non-owner goes straight to the delete screen', (tester) async {
    await pumpAs(tester, backend, Preset.partner, const AccountPage());
    await tester.scrollUntilVisible(find.byKey(const Key('account-delete')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('account-delete')));
    await settle(tester);
    expect(find.byType(SoleOwnerWarning), findsNothing);
    expect(find.byType(DeleteAccountScreen), findsOneWidget);
  });

  testWidgets('רשות המסים וחתימה: status words, connect = המשך במחשב, signing status', (tester) async {
    await pumpAs(tester, backend, Preset.owner, const ShaamPage());
    expect(find.text('מחובר לרשות המסים'), findsOneWidget);
    expect(find.textContaining('בתוקף עד 10.1.2027'), findsOneWidget);
    expect(find.text('תשוחרר ב-Face ID בהפקה הבאה'), findsOneWidget);
    expect(find.byType(PrimaryButton), findsNothing);
    await tester.tap(find.byKey(const Key('shaam-connect')));
    await settle(tester);
    expect(find.text('שלח לי קישור במייל'), findsOneWidget);
  });

  testWidgets('accountant sees the tax status but no connect row and no signing', (tester) async {
    await pumpAs(tester, backend, Preset.accountantRep, const ShaamPage());
    expect(find.text('מחובר לרשות המסים'), findsOneWidget);
    expect(find.byKey(const Key('shaam-connect')), findsNothing);
    expect(find.byKey(const Key('signing-status')), findsNothing);
  });

  testWidgets('J12/AT-29: S14 switch = 2 taps; /me reloads for the new business', (tester) async {
    await pumpAs(tester, backend, Preset.owner, const BusinessScreen(), businesses: 3);
    final taps = Taps();
    await taps.tap(tester, find.byKey(const Key('business-name')));
    expect(find.text('החלפת עסק'), findsOneWidget);
    expect(find.text('פעיל'), findsOneWidget);
    expect(find.byKey(const Key('s14-search')), findsNothing); // ≤ 7
    final before = backend.calls('GET', '/me').length;
    await taps.tap(tester, find.byKey(const Key('s14-b2')));
    expect(taps.count, 2);
    expect(session.business!.businessId, 'b2');
    expect(backend.calls('GET', '/me').length, before + 1);
    expect(backend.last('GET', '/me')!.headers['X-Business-Id'], 'b2');
  });

  testWidgets('S14 search shows with more than 7 businesses', (tester) async {
    await pumpAs(tester, backend, Preset.owner, const BusinessScreen(), businesses: 9);
    await tester.tap(find.byKey(const Key('business-name')));
    await settle(tester);
    expect(find.byKey(const Key('s14-search')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('s14-search')), 'עסק 9');
    await settle(tester);
    expect(find.byKey(const Key('s14-b9')), findsOneWidget);
    expect(find.byKey(const Key('s14-b2')), findsNothing);
    expect(find.byType(SwitchBusinessSheet), findsOneWidget);
  });

  testWidgets('Dynamic Type 200% + dark: B, צוות, חשבון, רשות המסים, R do not overflow (AT-70)', (
    tester,
  ) async {
    phone(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.runAsync(() => signInAs(backend, Preset.owner, businesses: 2));
    for (final b in Brightness.values) {
      for (final screen in <Widget>[
        const BusinessScreen(),
        const BusinessScreen(section: 'team'),
        const BusinessScreen(section: 'account'),
        const BusinessScreen(section: 'shaam'),
        const BusinessScreen(section: 'profile'),
        const ReportsScreen(),
      ]) {
        await tester.pumpWidget(eApp(screen, brightness: b));
        await settle(tester);
        expect(tester.takeException(), isNull, reason: '$screen $b');
      }
    }
  });

  testWidgets('VoiceOver: every B row is a labelled button', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpAs(tester, backend, Preset.owner, const BusinessScreen());
    for (final label in ['צוות והרשאות', 'פרטי העסק', 'החשבון שלי']) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    handle.dispose();
  });

  test('subscription management is limited to the business owner', () async {
    final b = FakeBackend()..install();
    await signInAs(b, Preset.owner);
    expect(
      businessRows(businessContext.caps, memberCount: 1).map((r) => r.key),
      contains('subscription'),
    );
    await signInAs(b, Preset.employee);
    expect(
      businessRows(businessContext.caps, memberCount: 1).map((r) => r.key),
      isNot(contains('subscription')),
    );
  });
}
