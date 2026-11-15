// AUTH-INVITE-RESET (2026-11-15): the invited employee creates an account in
// the app (Supabase sign-up with the invited e-mail → server accept + link),
// and "שכחתי סיסמה" with a 6-digit recovery code. Supabase HTTP is mocked
// through the same MockClient as the Tevel API (by host).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invoice/api/auth_api.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/api/environment.dart';
import 'package:invoice/api/supabase_auth.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/auth/invite_screen.dart';
import 'package:invoice/screens/auth/login_screen.dart';
import 'package:invoice/screens/auth/password_recovery.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/session.dart';
import 'package:invoice/ui/ds.dart';

const settings = SupabaseAuthSettings(
  url: 'https://example.supabase.co',
  publishableKey: 'sb_publishable_test',
);
const inviteToken = 'invite_token_abcdefghijklmnopqrstuvwxyz0123';
const invited = 'new.employee@example.test';

Widget app(Widget home) => MaterialApp(
  navigatorKey: navigatorKey,
  locale: const Locale('he', 'IL'),
  supportedLocales: const [Locale('he', 'IL')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: buildTheme(Brightness.light),
  home: home,
);

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// "METHOD /path" → (status, body) for both hosts; records every request.
final List<http.Request> sent = [];
void serve(Map<String, (int, Object) Function(http.Request)> routes) {
  ApiClient.instance.httpClient = MockClient((request) async {
    sent.add(request);
    final hit = routes['${request.method} ${request.url.path}'];
    if (hit == null) {
      return http.Response(jsonEncode({'error': 'NOT_FOUND'}), 404);
    }
    final (status, body) = hit(request);
    return http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

(int, Object) Function(http.Request) reply(int status, Object body) =>
    (_) => (status, body);

Map<String, dynamic> bodyOf(String path) =>
    jsonDecode(sent.lastWhere((r) => r.url.path == path).body)
        as Map<String, dynamic>;

Map<String, (int, Object) Function(http.Request)> preview({
  bool accountExists = false,
}) => {
  'GET /auth/invite/$inviteToken': reply(200, {
    'email': invited,
    'role': 'EMPLOYEE',
    'permissions': <String>[],
    'businessName': 'סטודיו תבל',
    'inviterName': 'דנה',
    'expiresAt': '2026-11-22T00:00:00Z',
    'accountExists': accountExists,
  }),
};

/// After /accept: device token + a session without businesses (stops at the
/// "no business" gate, enough to prove the sign-in completed).
final Map<String, (int, Object) Function(http.Request)> signedIn = {
  'POST /auth/invite/$inviteToken/accept': reply(200, {
    'status': 'ok',
    'businessId': 'b1',
    'role': 'EMPLOYEE',
    'csrfToken': 'c',
  }),
  'POST /auth/device-token': reply(201, {
    'token': 'inv_${'a' * 48}',
    'tokenId': 't',
    'expiresAt': '2027-01-01T00:00:00Z',
  }),
  'GET /mobile/session': reply(200, {
    'userId': 'u',
    'email': invited,
    'displayName': 'עובד',
    'businesses': [],
  }),
};

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 500));
}

const strongPassword = 'Strong-Pass-2026!';

/// The Apple button sits below the password form (ListView builds lazily).
Future<void> showApple(WidgetTester tester) => tester.scrollUntilVisible(
  find.byKey(const Key('invite-apple')),
  200,
  scrollable: find.byType(Scrollable).first,
);

void main() {
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('invite_reset_test');
    AppCache.directoryProvider = () async => tmp;
  });

  setUp(() {
    sent.clear();
    supabaseAuth = SupabaseAuthApi(settings: settings);
    ApiClient.instance.clearCredentials();
    FlutterSecureStorage.setMockInitialValues({});
    session
      ..status = SessionStatus.signedOut
      ..account = null
      ..business = null
      ..me = null
      ..profile = null;
  });

  tearDown(() {
    supabaseAuth = SupabaseAuthApi();
    appleCredential = requestAppleCredential;
  });

  group('invitation links', () {
    test(
      'tevel:// and the universal link (full URL or path) carry the token',
      () {
        expect(inviteTokenOf('tevel://invite/$inviteToken'), inviteToken);
        expect(
          inviteTokenOf(
            'https://invoice.crm.tevel.space/m/invite/$inviteToken',
          ),
          inviteToken,
        );
        expect(inviteTokenOf('/m/invite/$inviteToken'), inviteToken);
        for (final bad in [
          'tevel://invite/short',
          'tevel://doc/$inviteToken',
          'http://invoice.crm.tevel.space/m/invite/$inviteToken',
          'https://x/m/invite/$inviteToken/extra',
          'tevel://invite/..%2F$inviteToken',
          '/invite/$inviteToken',
        ]) {
          expect(inviteTokenOf(bad), isNull, reason: bad);
        }
      },
    );
  });

  group('Supabase Auth REST', () {
    test('error codes for sign-up, codes and new passwords', () {
      expect(
        supabaseErrorCode(422, '{"error_code":"user_already_exists"}'),
        'SUPABASE_ACCOUNT_EXISTS',
      );
      expect(
        supabaseErrorCode(422, '{"error_code":"weak_password"}'),
        'SUPABASE_WEAK_PASSWORD',
      );
      expect(
        supabaseErrorCode(403, '{"error_code":"otp_expired"}'),
        'SUPABASE_CODE_INVALID',
      );
      expect(
        supabaseErrorCode(400, '{}', fallback: 'SUPABASE_CODE_INVALID'),
        'SUPABASE_CODE_INVALID',
      );
      expect(
        supabaseErrorCode(422, '{"error_code":"same_password"}'),
        'SUPABASE_SAME_PASSWORD',
      );
      expect(
        supabaseErrorCode(422, '{"error_code":"signup_disabled"}'),
        'SUPABASE_SIGNUP_DISABLED',
      );
      expect(supabaseErrorCode(500, '{}'), 'SUPABASE_AUTH_UNAVAILABLE');
    });

    test(
      'sign-up: a session, a pending e-mail code, or an existing account',
      () async {
        final api = SupabaseAuthApi(
          settings: settings,
          httpClient: MockClient((request) async {
            expect(
              request.url.toString(),
              'https://example.supabase.co/auth/v1/signup',
            );
            expect(request.headers['apikey'], settings.publishableKey);
            final email = (jsonDecode(request.body) as Map)['email'];
            return switch (email) {
              'now@example.test' => http.Response(
                jsonEncode({
                  'access_token': 'jwt',
                  'user': {'id': 'u'},
                }),
                200,
              ),
              'code@example.test' => http.Response(
                jsonEncode({
                  'id': 'u',
                  'identities': [
                    {'id': 'i'},
                  ],
                }),
                200,
              ),
              _ => http.Response(
                jsonEncode({'id': 'u', 'identities': []}),
                200,
              ),
            };
          }),
        );
        expect((await api.signUp('now@example.test', 'pw')).accessToken, 'jwt');
        expect(
          (await api.signUp('code@example.test', 'pw')).needsEmailCode,
          isTrue,
        );
        await expectLater(
          api.signUp('taken@example.test', 'pw'),
          throwsA(
            isA<ApiException>().having(
              (e) => e.code,
              'code',
              'SUPABASE_ACCOUNT_EXISTS',
            ),
          ),
        );
      },
    );

    test(
      'recovery: code request, code check and the new password with its session',
      () async {
        final calls = <http.Request>[];
        final api = SupabaseAuthApi(
          settings: settings,
          httpClient: MockClient((request) async {
            calls.add(request);
            return switch (request.url.path) {
              '/auth/v1/recover' => http.Response('{}', 200),
              '/auth/v1/verify' =>
                (jsonDecode(request.body) as Map)['token'] == '123456'
                    ? http.Response(
                        jsonEncode({'access_token': 'recovery-jwt'}),
                        200,
                      )
                    : http.Response(
                        jsonEncode({'error_code': 'otp_expired'}),
                        403,
                      ),
              _ => http.Response(jsonEncode({'id': 'u'}), 200),
            };
          }),
        );
        await api.sendRecoveryCode(' a@example.test ');
        expect(jsonDecode(calls.last.body), {'email': 'a@example.test'});
        await expectLater(
          api.verifyCode('a@example.test', '000000', recovery: true),
          throwsA(
            isA<ApiException>().having(
              (e) => e.code,
              'code',
              'SUPABASE_CODE_INVALID',
            ),
          ),
        );
        expect(
          await api.verifyCode('a@example.test', '123456', recovery: true),
          'recovery-jwt',
        );
        expect(jsonDecode(calls.last.body), {
          'type': 'recovery',
          'email': 'a@example.test',
          'token': '123456',
        });
        await api.updatePassword('recovery-jwt', strongPassword);
        expect(calls.last.method, 'PUT');
        expect(calls.last.url.path, '/auth/v1/user');
        expect(calls.last.headers['Authorization'], 'Bearer recovery-jwt');
        expect(jsonDecode(calls.last.body), {'password': strongPassword});
      },
    );
  });

  group('invite screen', () {
    testWidgets(
      'shows business and role; new account: Supabase sign-up with the invited e-mail → accept → signed in',
      (tester) async {
        phone(tester);
        serve({
          ...preview(),
          'POST /auth/v1/token': reply(400, {
            'error_code': 'invalid_credentials',
          }),
          'POST /auth/v1/signup': reply(200, {
            'access_token': 'signup-jwt',
            'user': {'id': 'u'},
          }),
          ...signedIn,
        });
        await tester.pumpWidget(app(const InviteScreen(token: inviteToken)));
        await settle(tester);
        expect(find.text('הוזמנת ל-סטודיו תבל כעובד'), findsOneWidget);
        expect(find.textContaining(invited), findsOneWidget);
        await showApple(tester);
        expect(find.text('המשך עם Apple'), findsOneWidget);

        // Local policy first: nothing is sent.
        await tester.enterText(
          find.byKey(const Key('invite-password')),
          'short',
        );
        await tester.tap(find.byKey(const Key('invite-join')));
        await tester.pump();
        expect(
          find.text('לפחות 12 תווים ולפחות 4 תווים שונים. לא סיסמה נפוצה.'),
          findsWidgets,
        );
        expect(sent.where((r) => r.method == 'POST'), isEmpty);

        await tester.enterText(
          find.byKey(const Key('invite-name')),
          'עובד חדש',
        );
        await tester.enterText(
          find.byKey(const Key('invite-password')),
          strongPassword,
        );
        await tester.tap(find.byKey(const Key('invite-join')));
        await settle(tester);
        expect(bodyOf('/auth/v1/signup'), {
          'email': invited,
          'password': strongPassword,
        });
        expect(bodyOf('/auth/invite/$inviteToken/accept'), {
          'password': strongPassword,
          'supabaseAccessToken': 'signup-jwt',
          'displayName': 'עובד חדש',
        });
        expect(ApiClient.instance.deviceToken, startsWith('inv_'));
        expect(session.status, SessionStatus.signedIn);
      },
    );

    testWidgets(
      '"Confirm email" on: asks for the e-mailed code, then accepts',
      (tester) async {
        phone(tester);
        serve({
          ...preview(),
          'POST /auth/v1/token': reply(400, {
            'error_code': 'invalid_credentials',
          }),
          'POST /auth/v1/signup': reply(200, {
            'id': 'u',
            'identities': [
              {'id': 'i'},
            ],
          }),
          'POST /auth/v1/resend': reply(200, {}),
          'POST /auth/v1/verify': (request) =>
              (jsonDecode(request.body) as Map)['token'] == '654321'
              ? (200, {'access_token': 'confirmed-jwt'})
              : (403, {'error_code': 'otp_expired'}),
          ...signedIn,
        });
        await tester.pumpWidget(app(const InviteScreen(token: inviteToken)));
        await settle(tester);
        await tester.enterText(
          find.byKey(const Key('invite-password')),
          strongPassword,
        );
        await tester.tap(find.byKey(const Key('invite-join')));
        await settle(tester);
        expect(find.text('אישור כתובת האימייל'), findsOneWidget);
        expect(sent.any((r) => r.url.path.endsWith('/accept')), isFalse);

        await tester.enterText(find.byKey(const Key('invite-code')), '111111');
        await tester.tap(find.byKey(const Key('invite-verify')));
        await settle(tester);
        expect(
          find.text(
            'הקוד שגוי או שפג תוקפו. בדקו את המייל האחרון, או בקשו קוד חדש.',
          ),
          findsOneWidget,
        );

        await tester.tap(find.text('שלח קוד חדש'));
        await settle(tester);
        expect(bodyOf('/auth/v1/resend'), {'type': 'signup', 'email': invited});
        expect(find.text('נשלח קוד חדש'), findsOneWidget);

        await tester.enterText(find.byKey(const Key('invite-code')), '654321');
        await tester.tap(find.byKey(const Key('invite-verify')));
        await settle(tester);
        expect(bodyOf('/auth/v1/verify'), {
          'type': 'signup',
          'email': invited,
          'token': '654321',
        });
        expect(bodyOf('/auth/invite/$inviteToken/accept'), {
          'password': strongPassword,
          'supabaseAccessToken': 'confirmed-jwt',
        });
        expect(session.status, SessionStatus.signedIn);
      },
    );

    testWidgets(
      'existing account without an app password: its Tevel password accepts',
      (tester) async {
        phone(tester);
        serve({
          ...preview(accountExists: true),
          'POST /auth/v1/token': reply(400, {
            'error_code': 'invalid_credentials',
          }),
          ...signedIn,
        });
        await tester.pumpWidget(app(const InviteScreen(token: inviteToken)));
        await settle(tester);
        expect(find.byKey(const Key('invite-name')), findsNothing);
        expect(find.text('שכחתי סיסמה'), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('invite-password')),
          'tevel-web-password',
        );
        await tester.tap(find.byKey(const Key('invite-join')));
        await settle(tester);
        expect(sent.any((r) => r.url.path == '/auth/v1/signup'), isFalse);
        expect(bodyOf('/auth/invite/$inviteToken/accept'), {
          'password': 'tevel-web-password',
        });
        expect(session.status, SessionStatus.signedIn);
      },
    );

    testWidgets(
      'e-mail mismatch says both addresses; the invitation stays open',
      (tester) async {
        phone(tester);
        appleCredential = () async =>
            (identityToken: 'apple-jwt', fullName: '');
        serve({
          ...preview(),
          'POST /auth/invite/$inviteToken/accept': reply(403, {
            'error': 'INVITATION_EMAIL_MISMATCH',
            'signedInEmail': 'x1@privaterelay.appleid.com',
          }),
        });
        await tester.pumpWidget(app(const InviteScreen(token: inviteToken)));
        await settle(tester);
        await showApple(tester);
        await tester.tap(find.byKey(const Key('invite-apple')));
        await settle(tester);
        expect(bodyOf('/auth/invite/$inviteToken/accept'), {
          'appleIdentityToken': 'apple-jwt',
        });
        expect(
          find.textContaining(
            'ההזמנה נשלחה ל-${ltrIsolate(invited)}, התחברת כ-${ltrIsolate('x1@privaterelay.appleid.com')}',
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('invite-join')), findsOneWidget);
      },
    );

    testWidgets('already a member → "אתה כבר חבר"', (tester) async {
      phone(tester);
      serve({
        ...preview(),
        'POST /auth/v1/token': reply(200, {'access_token': 'old-jwt'}),
        'POST /auth/invite/$inviteToken/accept': reply(409, {
          'error': 'MEMBER_EXISTS',
        }),
      });
      await tester.pumpWidget(app(const InviteScreen(token: inviteToken)));
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('invite-password')),
        strongPassword,
      );
      await tester.tap(find.byKey(const Key('invite-join')));
      await settle(tester);
      expect(find.text('אתה כבר חבר ב-סטודיו תבל'), findsOneWidget);
    });

    testWidgets('expired or revoked invitation → ask for a new one', (
      tester,
    ) async {
      for (final code in ['INVITATION_EXPIRED', 'INVITATION_REVOKED']) {
        phone(tester);
        serve({
          'GET /auth/invite/$inviteToken': reply(410, {'error': code}),
        });
        await tester.pumpWidget(
          app(InviteScreen(key: ValueKey(code), token: inviteToken)),
        );
        await settle(tester);
        expect(
          find.text('ההזמנה כבר לא בתוקף. בקש מ-המזמין לשלוח שוב'),
          findsOneWidget,
        );
      }
    });
  });

  group('forgot password (Supabase, 6-digit code)', () {
    Map<String, (int, Object) Function(http.Request)> recovery({
      Object? exchange,
    }) => {
      'POST /auth/v1/recover': reply(200, {}),
      'POST /auth/v1/verify': (request) =>
          (jsonDecode(request.body) as Map)['token'] == '123456'
          ? (200, {'access_token': 'recovery-jwt'})
          : (403, {'error_code': 'otp_expired'}),
      'PUT /auth/v1/user': (request) =>
          (jsonDecode(request.body) as Map)['password'] == 'Old-Password-2026'
          ? (422, {'error_code': 'same_password'})
          : (200, {'id': 'u'}),
      'POST /auth/supabase': reply(
        200,
        exchange ??
            {'status': 'PASSWORD_OK', 'csrfToken': 'c', 'businesses': []},
      ),
    };

    Future<Object?> openSheet(WidgetTester tester, {bool signIn = true}) async {
      Object? popped = 'not yet';
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => popped = await showForgotPasswordSheet(
                  context,
                  '',
                  signIn: signIn,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return popped;
    }

    testWidgets('request → neutral answer → code → new password → signed in', (
      tester,
    ) async {
      phone(tester);
      serve(recovery());
      Object? result;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    result = await showForgotPasswordSheet(context, ''),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('איפוס סיסמה'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('recovery-email')), 'nobody');
      await tester.tap(find.byKey(const Key('recovery-send')));
      await tester.pump();
      expect(find.text('נא להזין כתובת מייל תקינה'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('recovery-email')), invited);
      await tester.tap(find.byKey(const Key('recovery-send')));
      await settle(tester);
      // The same words for any address: nothing tells whether it exists.
      expect(find.textContaining('רשומה, נשלח אליה קוד'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('recovery-code')), '999999');
      await tester.tap(find.byKey(const Key('recovery-verify')));
      await settle(tester);
      expect(
        find.text(
          'הקוד שגוי או שפג תוקפו. בדקו את המייל האחרון, או בקשו קוד חדש.',
        ),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const Key('recovery-code')), '123456');
      await tester.tap(find.byKey(const Key('recovery-verify')));
      await settle(tester);
      expect(find.text('סיסמה חדשה'), findsWidgets);

      await tester.enterText(
        find.byKey(const Key('recovery-password')),
        'aaaaaaaaaaaaaa',
      );
      await tester.tap(find.byKey(const Key('recovery-save')));
      await tester.pump();
      expect(sent.any((r) => r.url.path == '/auth/v1/user'), isFalse);

      await tester.enterText(
        find.byKey(const Key('recovery-password')),
        'Old-Password-2026',
      );
      await tester.tap(find.byKey(const Key('recovery-save')));
      await settle(tester);
      expect(find.text('זו הסיסמה הנוכחית. בחרו סיסמה חדשה.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('recovery-password')),
        strongPassword,
      );
      await tester.tap(find.byKey(const Key('recovery-save')));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(result, isA<SignInResult>());
      expect(bodyOf('/auth/supabase'), {'accessToken': 'recovery-jwt'});
      expect(sent.any((r) => r.url.path == '/auth/password/forgot'), isFalse);
    });

    testWidgets(
      'password changed but no linked Tevel account: says so instead of failing silently',
      (tester) async {
        phone(tester);
        serve({
          ...recovery(),
          'POST /auth/supabase': reply(403, {'error': 'NO_LINKED_ACCOUNT'}),
        });
        await openSheet(tester);
        await tester.enterText(
          find.byKey(const Key('recovery-email')),
          invited,
        );
        await tester.tap(find.byKey(const Key('recovery-send')));
        await settle(tester);
        await tester.enterText(
          find.byKey(const Key('recovery-code')),
          '123456',
        );
        await tester.tap(find.byKey(const Key('recovery-verify')));
        await settle(tester);
        await tester.enterText(
          find.byKey(const Key('recovery-password')),
          strongPassword,
        );
        await tester.tap(find.byKey(const Key('recovery-save')));
        await settle(tester);
        expect(find.text('הסיסמה עודכנה'), findsOneWidget);
        expect(
          find.textContaining('לא מצאנו חשבון לכתובת הזו'),
          findsOneWidget,
        );
      },
    );

    testWidgets('inside an invitation: only the password changes', (
      tester,
    ) async {
      phone(tester);
      serve(recovery());
      await openSheet(tester, signIn: false);
      await tester.enterText(find.byKey(const Key('recovery-email')), invited);
      await tester.tap(find.byKey(const Key('recovery-send')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('recovery-code')), '123456');
      await tester.tap(find.byKey(const Key('recovery-verify')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('recovery-password')),
        strongPassword,
      );
      await tester.tap(find.byKey(const Key('recovery-save')));
      await settle(tester);
      expect(
        find.text('עכשיו הזינו את הסיסמה החדשה כדי להצטרף לעסק.'),
        findsOneWidget,
      );
      expect(sent.any((r) => r.url.path == '/auth/supabase'), isFalse);
    });
  });

  test('without Supabase, recovery stays on the Tevel reset link', () async {
    supabaseAuth = SupabaseAuthApi(
      settings: const SupabaseAuthSettings(url: '', publishableKey: ''),
    );
    serve({
      'POST /auth/password/forgot': reply(202, {'status': 'ok'}),
    });
    await requestPasswordReset(' a@example.test ');
    expect(sent.single.url.path, '/auth/password/forgot');
    expect(passwordPolicyErrorHe(strongPassword), isNull);
  });
}
