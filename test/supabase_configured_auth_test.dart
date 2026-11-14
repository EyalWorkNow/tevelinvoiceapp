import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invoice/api/auth_api.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/api/environment.dart';

void main() {
  final api = ApiClient.instance;
  final settings = SupabaseAuthSettings.configured;

  setUp(() => api.clearCredentials());

  test(
    'configured login uses Supabase and exchanges into the existing MFA flow',
    () async {
      final previous = api.httpClient;
      addTearDown(() {
        api.clearCredentials();
        api.httpClient = previous;
      });
      final paths = <String>[];
      api.httpClient = MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.host == settings.origin.host) {
          expect(request.headers.containsKey('Authorization'), isFalse);
          expect(jsonDecode(request.body), {
            'email': 'owner@example.test',
            'password': 'private',
          });
          return http.Response(jsonEncode({'access_token': 'test-jwt'}), 200);
        }
        expect(request.url.path, '/auth/supabase');
        expect(jsonDecode(request.body), {'accessToken': 'test-jwt'});
        return http.Response(
          jsonEncode({'status': 'MFA_REQUIRED', 'businesses': []}),
          200,
        );
      });
      expect(
        (await signInWithPassword('owner@example.test', 'private')).mfaRequired,
        isTrue,
      );
      expect(paths, ['/auth/v1/token', '/auth/supabase']);
    },
    skip: !settings.enabled,
  );

  test(
    'configured recovery never resets an unrelated legacy password',
    () async {
      final previous = api.httpClient;
      addTearDown(() => api.httpClient = previous);
      api.httpClient = MockClient((_) async {
        fail('must not contact legacy password recovery');
      });
      await expectLater(
        requestPasswordReset('owner@example.test'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'SUPABASE_RECOVERY_SUPPORT_REQUIRED',
          ),
        ),
      );
    },
    skip: !settings.enabled,
  );
}
