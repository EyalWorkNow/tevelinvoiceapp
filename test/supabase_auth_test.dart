import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invoice/api/auth_api.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/api/environment.dart';
import 'package:invoice/api/supabase_auth.dart';

const settings = SupabaseAuthSettings(
  url: 'https://example.supabase.co',
  publishableKey: 'sb_publishable_test',
);

void main() {
  test('configuration refuses partial, insecure and secret-key settings', () {
    for (final config in [
      const SupabaseAuthSettings(
        url: '',
        publishableKey: 'sb_publishable_test',
      ),
      const SupabaseAuthSettings(
        url: 'http://example.supabase.co',
        publishableKey: 'sb_publishable_test',
      ),
      const SupabaseAuthSettings(
        url: 'https://example.supabase.co',
        publishableKey: 'sb_secret_test',
      ),
      const SupabaseAuthSettings(
        url: 'https://example.supabase.co/elsewhere',
        publishableKey: 'sb_publishable_test',
      ),
      const SupabaseAuthSettings(
        url: 'https://elsewhere.example',
        publishableKey: 'sb_publishable_test',
      ),
    ]) {
      expect(() => config.origin, throwsFormatException);
    }
    expect(settings.origin.host, 'example.supabase.co');
  });

  test(
    'password is sent only to the configured Auth origin without Tevel credentials',
    () async {
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://example.supabase.co/auth/v1/token?grant_type=password',
        );
        expect(request.followRedirects, isFalse);
        expect(request.headers['apikey'], settings.publishableKey);
        expect(request.headers.containsKey('Authorization'), isFalse);
        expect(request.headers.containsKey('Cookie'), isFalse);
        expect(jsonDecode(request.body), {
          'email': 'a@example.test',
          'password': 'private',
        });
        return http.Response(
          jsonEncode({'access_token': 'jwt-for-exchange'}),
          200,
        );
      });
      expect(
        await supabasePasswordToken(
          ' a@example.test ',
          'private',
          client: client,
          settings: settings,
        ),
        'jwt-for-exchange',
      );
    },
  );

  test(
    'invalid credentials, throttling and malformed responses fail explicitly',
    () async {
      for (final sample in [
        (400, '{}', 'INVALID_CREDENTIALS'),
        (429, '{}', 'RATE_LIMITED'),
        (503, '{}', 'SUPABASE_AUTH_UNAVAILABLE'),
        (200, 'not-json', 'BAD_RESPONSE'),
        (200, '{}', 'BAD_RESPONSE'),
      ]) {
        await expectLater(
          supabasePasswordToken(
            'a@example.test',
            'pw',
            settings: settings,
            client: MockClient(
              (_) async => http.Response(sample.$2, sample.$1),
            ),
          ),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', sample.$3)),
        );
      }
    },
  );

  test(
    'exchange starts a clean cookie phase and preserves the existing MFA gate',
    () async {
      final api = ApiClient.instance;
      final previous = api.httpClient;
      addTearDown(() {
        api.clearCredentials();
        api.httpClient = previous;
      });
      api.deviceToken = 'old-token';
      api.businessId = 'old-business';
      api.httpClient = MockClient((request) async {
        expect(request.url.path, '/auth/supabase');
        expect(jsonDecode(request.body), {'accessToken': 'supabase-jwt'});
        expect(request.headers.containsKey('Authorization'), isFalse);
        expect(request.headers.containsKey('X-Business-Id'), isFalse);
        return http.Response(
          jsonEncode({
            'status': 'MFA_REQUIRED',
            'csrfToken': 'csrf',
            'businesses': [],
          }),
          200,
          headers: {'set-cookie': 'tvl_session=fresh; HttpOnly; Path=/'},
        );
      });
      expect((await signInWithSupabase('supabase-jwt')).mfaRequired, isTrue);
      expect(api.sessionCookie, 'fresh');
      expect(api.csrfToken, 'csrf');
    },
  );
}
