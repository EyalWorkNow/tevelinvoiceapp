// A · gate: invitation states, MFA as a blocking step, setup routing (SPEC-v2 §6.A).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/screens/auth/auth_flow.dart';
import 'package:invoice/screens/auth/invite_screen.dart';
import 'package:invoice/screens/auth/mfa_sheet.dart';
import 'package:invoice/screens/auth/onboarding_screen.dart';
import 'package:invoice/screens/billing/billing_screen.dart';
import 'package:invoice/app_shell.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/session.dart';
import 'package:invoice/ui/ds.dart';

import '../business/e_harness.dart';
import '../fakes/fake_api.dart';

const _token = 'tok_aaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  late FakeBackend backend;
  setUp(() async => backend = await eSetUp());

  Future<void> pumpInvite(WidgetTester tester) async {
    phone(tester);
    await tester.pumpWidget(eApp(const InviteScreen(token: _token)));
    await settle(tester);
  }

  testWidgets(
    'valid invitation, existing account: preset sentence, password, one primary',
    (tester) async {
      await pumpInvite(tester);
      expect(find.text('הוזמנת ל-סטודיו תבל כעובד'), findsOneWidget);
      expect(find.text('מאת דנה'), findsOneWidget);
      expect(find.text('יש לי סיסמה'), findsOneWidget);
      expect(find.text('שכחתי סיסמה'), findsOneWidget);
      expect(find.byType(PrimaryButton), findsOneWidget);
      expect(
        find.textContaining('Apple'),
        findsNothing,
      ); // server /accept has no Apple
    },
  );

  testWidgets(
    'wrong password → message under the field (INVALID_CREDENTIALS)',
    (tester) async {
      backend.error(
        'POST',
        '/auth/invite/:token/accept',
        401,
        'INVALID_CREDENTIALS',
      );
      await pumpInvite(tester);
      await tester.enterText(find.byKey(const Key('invite-password')), 'wrong');
      await tester.tap(find.byKey(const Key('invite-join')));
      await settle(tester);
      expect(find.text('האימייל או הסיסמה שגויים'), findsOneWidget);
      expect(backend.last('POST', '/auth/invite/:token/accept')!.body, {
        'password': 'wrong',
      });
    },
  );

  testWidgets('already a member (MEMBER_EXISTS) → "אתה כבר חבר ב-…" + "פתח"', (
    tester,
  ) async {
    backend.error('POST', '/auth/invite/:token/accept', 409, 'MEMBER_EXISTS');
    await pumpInvite(tester);
    await tester.enterText(
      find.byKey(const Key('invite-password')),
      'Mobile12345678',
    );
    await tester.tap(find.byKey(const Key('invite-join')));
    await settle(tester);
    expect(find.text('אתה כבר חבר ב-סטודיו תבל'), findsOneWidget);
    expect(find.text('פתח'), findsOneWidget);
  });

  testWidgets('expired / revoked → "ההזמנה כבר לא בתוקף. בקש מ-… לשלוח שוב"', (
    tester,
  ) async {
    for (final code in ['INVITATION_EXPIRED', 'INVITATION_REVOKED']) {
      backend.error('GET', '/auth/invite/:token', 410, code);
      await tester.pumpWidget(const SizedBox());
      await pumpInvite(tester);
      expect(
        find.text('ההזמנה כבר לא בתוקף. בקש מ-המזמין לשלוח שוב'),
        findsOneWidget,
        reason: code,
      );
    }
  });

  testWidgets(
    'new account: name + "צור סיסמה", local 12-char rule before any request',
    (tester) async {
      backend.json('GET', '/auth/invite/:token', {
        'email': 'new@tevel.test',
        'role': 'READ_ONLY',
        'permissions': ['expense:record', 'expense:approve'],
        'businessName': 'סטודיו תבל',
        'inviterName': 'דנה',
        'accountExists': false,
      });
      await pumpInvite(tester);
      expect(find.text('הוזמנת ל-סטודיו תבל כרואה חשבון'), findsOneWidget);
      expect(find.text('צור סיסמה'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('invite-password')), 'short');
      await tester.tap(find.byKey(const Key('invite-join')));
      await settle(tester);
      expect(backend.calls('POST', '/auth/invite/:token/accept'), isEmpty);
    },
  );

  testWidgets(
    'accept → device token needs MFA, method enrolled → LOGIN code step (not enroll)',
    (tester) async {
      backend
        ..error('POST', '/auth/device-token', 403, 'MFA_REQUIRED')
        ..json('GET', '/auth/mfa/methods', {
          'totp': false,
          'email': {'enabled': true},
          'emailAvailable': true,
          'recoveryCodesRemaining': 0,
        })
        ..json('POST', '/auth/mfa/email/send', {
          'sentTo': 'ne***@tevel.test',
          'resendAfterSeconds': 30,
        });
      await pumpInvite(tester);
      await tester.enterText(
        find.byKey(const Key('invite-password')),
        'Mobile12345678',
      );
      await tester.tap(find.byKey(const Key('invite-join')));
      await settle(tester);
      expect(
        find.byType(MfaSheet),
        findsOneWidget,
      ); // full-screen blocking step
      expect(find.text('קוד אימות'), findsOneWidget);
      expect(backend.last('POST', '/auth/mfa/email/send')!.body, {
        'purpose': 'LOGIN',
      });
      await tester.pump(const Duration(seconds: 60)); // drain the resend ticker
    },
  );

  testWidgets('MFA step: full screen, closing it returns false', (
    tester,
  ) async {
    backend.json('POST', '/auth/mfa/email/send', {
      'sentTo': 'ne***@tevel.test',
      'resendAfterSeconds': 30,
    });
    bool? result;
    phone(tester);
    await tester.pumpWidget(
      eApp(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  result = await showMfaStep(context, enroll: true),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await settle(tester);
    expect(find.text('עוד שכבת הגנה'), findsOneWidget);
    expect(find.textContaining('שלחנו קוד ל-'), findsOneWidget);
    await tester.tap(find.byTooltip('סגור'));
    await settle(tester);
    expect(result, isFalse);
    await tester.pump(const Duration(seconds: 60));
  });

  group('routeSignedIn: setup', () {
    Future<void> route(WidgetTester tester, Preset preset) async {
      phone(tester);
      await tester.runAsync(() => signInAs(backend, preset));
      backend.json('GET', '/me', meJson(preset, onboardingCompleted: false));
      await tester.runAsync(session.refreshBusiness);
      await tester.pumpWidget(
        eApp(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => routeSignedIn(context),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await settle(tester);
    }

    testWidgets('owner → setup', (tester) async {
      await route(tester, Preset.owner);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      // identityLocked fixture: documents exist → the name step only.
      expect(find.text('סיימתי'), findsOneWidget);
    });

    testWidgets('member → "בעל העסק עדיין מסיים להגדיר את העסק" + "נסה שוב"', (
      tester,
    ) async {
      await route(tester, Preset.employee);
      expect(find.byType(SetupPendingScreen), findsOneWidget);
      expect(find.text('בעל העסק עדיין מסיים להגדיר את העסק'), findsOneWidget);
      expect(find.byType(PrimaryButton), findsOneWidget);
      await tester.tap(find.byKey(const Key('setup-pending-retry')));
      await settle(tester);
      expect(backend.calls('GET', '/me').length, greaterThanOrEqualTo(3));
    });
  });

  testWidgets('token minted before MFA was needed → signed out to the gate', (
    tester,
  ) async {
    phone(tester);
    await tester.runAsync(() => signInAs(backend, Preset.employeeIssuer));
    session.me = null;
    backend.error('GET', '/me', 403, 'MFA_REQUIRED');
    await tester.pumpWidget(
      eApp(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => routeSignedIn(context),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await settle(tester);
    expect(session.status, SessionStatus.signedOut);
    expect(ApiClient.instance.hasDeviceToken, isFalse);
    expect(find.text('פג תוקף ההתחברות — נא להיכנס שוב'), findsOneWidget);
  });

  testWidgets(
    'cache start: home first, the subscription gate follows in the background',
    (tester) async {
      phone(tester);
      await tester.runAsync(() => signInAs(backend, Preset.owner));
      final answer = Completer<FakeResponse>();
      backend.on('GET', '/billing/subscription', (_) => answer.future);
      session.restoredFromCache = true;
      await tester.pumpWidget(
        eApp(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => routeSignedIn(context),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(AppShell), findsOneWidget);
      expect(session.restoredFromCache, isFalse);
      answer.complete(
        FakeResponse(200, {
          'active': false,
          'needsPlan': true,
          'subscription': null,
        }),
      );
      await settle(tester);
      expect(find.byType(RequiredSubscriptionScreen), findsOneWidget);
    },
  );
}
