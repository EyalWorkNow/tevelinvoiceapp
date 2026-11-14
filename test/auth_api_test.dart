import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invoice/api/auth_api.dart';
import 'package:invoice/api/client.dart';

void main() {
  final api = ApiClient.instance;
  late List<http.Request> sent;

  void respond(
    int status,
    Object? body, {
    Map<String, String> headers = const {},
  }) {
    api.httpClient = MockClient((request) async {
      sent.add(request);
      return http.Response(
        body == null ? '' : jsonEncode(body),
        status,
        headers: {
          'content-type': 'application/json; charset=utf-8',
          ...headers,
        },
      );
    });
  }

  setUp(() {
    sent = [];
    api.clearCredentials();
  });

  test(
    'password sign-in starts a clean cookie phase and parses MFA_REQUIRED',
    () async {
      api.deviceToken = 'inv_stale';
      api.businessId = 'b-old';
      respond(
        200,
        {
          'status': 'MFA_REQUIRED',
          'mfaRequired': true,
          'csrfToken': 'c1',
          'businesses': [],
        },
        headers: {'set-cookie': 'tvl_session=s1; HttpOnly; Path=/'},
      );
      final r = await signInWithPassword('  owner@tevel.test ', 'pw');
      expect(r.mfaRequired, isTrue);
      expect(r.businesses, isEmpty);
      final req = sent.single;
      expect(req.url.path, '/auth/login');
      expect(req.headers.containsKey('Authorization'), isFalse);
      expect(req.headers.containsKey('X-Business-Id'), isFalse);
      expect(jsonDecode(req.body), {
        'email': 'owner@tevel.test',
        'password': 'pw',
      });
      expect(api.sessionCookie, 's1');
      expect(api.csrfToken, 'c1');
    },
  );

  test('PASSWORD_OK lists businesses', () async {
    respond(200, {
      'status': 'PASSWORD_OK',
      'mfaRequired': false,
      'csrfToken': 'c',
      'businesses': [
        {'businessId': 'b1', 'legalName': 'סטודיו', 'role': 'EMPLOYEE'},
      ],
    });
    final r = await signInWithPassword('e@tevel.test', 'pw');
    expect(r.mfaRequired, isFalse);
    expect(r.businesses.single.legalName, 'סטודיו');
  });

  test('Apple sends identityToken, fullName only when present', () async {
    respond(200, {
      'status': 'PASSWORD_OK',
      'mfaRequired': false,
      'csrfToken': 'c',
      'businesses': [],
    });
    await signInWithApple('jwt', fullName: ' דנה כהן ');
    expect(jsonDecode(sent.last.body), {
      'identityToken': 'jwt',
      'fullName': 'דנה כהן',
    });
    await signInWithApple('jwt', fullName: '  ');
    expect(jsonDecode(sent.last.body), {'identityToken': 'jwt'});
    expect(sent.last.url.path, '/auth/apple');
  });

  test('Apple errors map to Hebrew', () async {
    respond(401, {'error': 'APPLE_TOKEN_INVALID', 'message': 'x'});
    await expectLater(
      signInWithApple('bad'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'APPLE_TOKEN_INVALID')
            .having((e) => e.messageHe, 'he', contains('Apple')),
      ),
    );
  });

  test('MFA methods: e-mail preferred, TOTP fallback', () async {
    respond(200, {
      'totp': false,
      'passkeys': [],
      'email': {'enabled': true, 'address': 'x'},
      'recoveryCodesRemaining': 0,
      'emailAvailable': true,
    });
    final m = await fetchMfaMethods();
    expect(m.useEmail, isTrue);
    expect(m.totp, isFalse);
    expect(
      MfaMethods.fromJson({
        'totp': true,
        'email': {'enabled': true},
        'emailAvailable': false,
        'recoveryCodesRemaining': 8,
      }).useEmail,
      isFalse,
    );
  });

  test('e-mail code send/verify payloads + recovery codes', () async {
    api.sessionCookie = 's';
    api.csrfToken = 'c0';
    respond(200, {'sentTo': 'mo***@tevel.test', 'resendAfterSeconds': 45});
    final s = await sendEmailCode(MfaPurpose.enroll);
    expect(s.sentTo, 'mo***@tevel.test');
    expect(s.resendAfterSeconds, 45);
    expect(jsonDecode(sent.last.body), {'purpose': 'ENROLL'});
    expect(sent.last.headers['X-CSRF-Token'], 'c0');

    respond(
      200,
      {'status': 'ok', 'recoveryCodes': null, 'csrfToken': 'c1'},
      headers: {'set-cookie': 'tvl_session=s2; Path=/'},
    );
    expect(await verifyEmailCode('123456', MfaPurpose.login), isNull);
    expect(jsonDecode(sent.last.body), {'code': '123456'});
    expect(api.csrfToken, 'c1');
    expect(api.sessionCookie, 's2');

    respond(200, {
      'status': 'ok',
      'recoveryCodes': ['aaaa-bbbb', 'cccc-dddd'],
      'csrfToken': 'c2',
    });
    expect(await verifyEmailCode('654321', MfaPurpose.enroll), [
      'aaaa-bbbb',
      'cccc-dddd',
    ]);
    expect(jsonDecode(sent.last.body), {'code': '654321', 'purpose': 'ENROLL'});
  });

  test(
    'onboarding profile body: digits-only tax id, description when given, locked identity',
    () async {
      api.deviceToken = 'inv_x';
      api.businessId = 'b1';
      final profile = {
        'profile': {
          'legalName': 'דנה',
          'businessType': 'OSEK_PATUR',
          'identityLocked': false,
        },
      };
      respond(200, profile);
      await saveOnboardingProfile(
        legalName: ' דנה ',
        businessType: 'OSEK_PATUR',
        taxId: '12345678-2',
        defaultLineDescription: ' ',
      );
      expect(sent.last.method, 'PUT');
      expect(sent.last.headers['X-Business-Id'], 'b1');
      expect(jsonDecode(sent.last.body), {
        'legalName': 'דנה',
        'businessType': 'OSEK_PATUR',
        'taxId': '123456782',
      });

      await saveOnboardingProfile(
        legalName: 'דנה',
        businessType: 'OSEK_PATUR',
        taxId: '123456782',
        defaultLineDescription: 'עיצוב גרפי',
        includeIdentity: false,
      );
      expect(jsonDecode(sent.last.body), {
        'legalName': 'דנה',
        'defaultLineDescription': 'עיצוב גרפי',
      });

      respond(200, {
        'onboarding': {'completed': true},
      });
      await completeOnboarding();
      expect(sent.last.url.path, '/business/onboarding');
      expect(jsonDecode(sent.last.body), {'completed': true});
    },
  );

  test('Israeli id checksum (same rule as packages/shared israel.ts)', () {
    expect(isValidIsraeliId('123456782'), isTrue);
    expect(isValidIsraeliId('000000042'), isTrue);
    expect(isValidIsraeliId('42'), isTrue); // left-padded
    expect(isValidIsraeliId('18'), isTrue);
    expect(isValidIsraeliId('123456789'), isFalse);
    expect(isValidIsraeliId(''), isFalse);
    expect(isValidIsraeliId('1234567890'), isFalse);
  });

  test('phone + email validation', () {
    expect(isValidIsraeliPhone('050-1234567'), isTrue);
    expect(isValidIsraeliPhone('+972501234567'), isTrue);
    expect(isValidIsraeliPhone('03-1234567'), isTrue);
    expect(isValidIsraeliPhone('12345'), isFalse);
    expect(isValidEmail('a@b.co'), isTrue);
    expect(isValidEmail('a@b'), isFalse);
  });
}
