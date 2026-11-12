import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invoice/api/actions_api.dart'
    show
        defaultWhatsAppTemplate,
        loadWhatsAppTemplate,
        waTemplateKey,
        waTemplateStorage;
import 'package:invoice/api/client.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/api/settings_api.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/session.dart';
import 'package:invoice/ui/theme.dart';

Widget app(
  Widget child, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => MaterialApp(
  locale: const Locale('he', 'IL'),
  supportedLocales: const [Locale('he', 'IL')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: buildTheme(brightness),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: child,
);

void main() {
  final api = ApiClient.instance;
  late List<http.Request> sent;
  late Directory tmp;

  void respond(int status, Object? body) {
    api.httpClient = MockClient((request) async {
      sent.add(request);
      return http.Response(
        body == null ? '' : jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
  }

  void signIn({
    String? paymentLink,
    bool canConfigure = true,
    String role = 'OWNER',
  }) {
    const business = Business(
      businessId: 'biz-1',
      legalName: 'סטודיו תבל',
      role: 'OWNER',
    );
    session
      ..status = SessionStatus.signedIn
      ..offline = false
      ..account = const MobileAccount(
        userId: 'u1',
        email: 'owner@tevel.test',
        businesses: [business],
      )
      ..business = business
      ..me = Me(
        userId: 'u1',
        role: role,
        mfaEnrolled: false,
        onboardingCompleted: true,
        canFinalize: true,
        canConfigure: canConfigure,
      )
      ..profile = BusinessProfile.fromJson({
        'legalName': 'סטודיו תבל',
        'businessType': 'OSEK_MURSHE',
        'taxId': '000000042',
        'paymentLinkUrl': paymentLink,
        'identityLocked': true,
        'onboarding': {'completed': true},
      });
    api.deviceToken = 'inv_${'a' * 48}';
    api.businessId = 'biz-1';
  }

  setUp(() async {
    sent = [];
    api.clearCredentials();
    tmp = await Directory.systemTemp.createTemp('settings_test');
    AppCache.directoryProvider = () async => tmp;
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('payment link validation (server isHttpsLink rule)', () {
    test('accepts https, rejects http / spaces / too long', () {
      expect(paymentLinkError(''), isNull);
      expect(paymentLinkError('https://payme.io/s/tevel'), isNull);
      expect(paymentLinkError('  https://payme.io/s/tevel  '), isNull);
      expect(paymentLinkError('http://payme.io/s/tevel'), isNotNull);
      expect(paymentLinkError('https://pay me.io'), isNotNull);
      expect(paymentLinkError('payme.io'), isNotNull);
      expect(paymentLinkError('https://${'a' * 2000}.io'), isNotNull);
    });

    test('phone + email match the server validators', () {
      expect(isValidIsraeliPhone('050-123-4567'), isTrue);
      expect(isValidIsraeliPhone('+972501234567'), isTrue);
      expect(isValidIsraeliPhone('03-1234567'), isTrue);
      expect(isValidIsraeliPhone('12345'), isFalse);
      expect(isValidEmail('a@b.co'), isTrue);
      expect(isValidEmail('a@b'), isFalse);
    });
  });

  group('account API', () {
    test(
      'delete sends confirm + exactly one proof, bearer, no business header',
      () async {
        signIn();
        respond(200, {'status': 'deleted'});
        await deleteAccount(
          password: 'Mobile12345678',
          appleIdentityToken: 'ignored',
        );
        expect(sent.last.url.path, '/mobile/account/delete');
        expect(jsonDecode(sent.last.body), {
          'confirm': 'DELETE',
          'password': 'Mobile12345678',
        });
        expect(sent.last.headers['Authorization'], startsWith('Bearer inv_'));
        expect(sent.last.headers.containsKey('X-Business-Id'), isFalse);

        await deleteAccount(appleIdentityToken: 'eyJapple');
        expect(jsonDecode(sent.last.body), {
          'confirm': 'DELETE',
          'appleIdentityToken': 'eyJapple',
        });

        // 5.1.1(v): the Apple code rides along with either proof (server revokes the grant).
        await deleteAccount(
          appleIdentityToken: 'eyJapple',
          appleAuthorizationCode: 'c0de',
        );
        expect(jsonDecode(sent.last.body), {
          'confirm': 'DELETE',
          'appleIdentityToken': 'eyJapple',
          'appleAuthorizationCode': 'c0de',
        });
        await deleteAccount(
          password: 'Mobile12345678',
          appleAuthorizationCode: 'c0de',
        );
        expect(jsonDecode(sent.last.body), {
          'confirm': 'DELETE',
          'password': 'Mobile12345678',
          'appleAuthorizationCode': 'c0de',
        });
      },
    );

    test(
      'REAUTH_FAILED maps to Hebrew and does not expire the session',
      () async {
        signIn();
        final events = <ApiEvent>[];
        final sub = api.events.listen(events.add);
        respond(403, {
          'error': 'REAUTH_FAILED',
          'message': 'identity could not be confirmed',
        });
        try {
          await deleteAccount(password: 'wrong');
          fail('should throw');
        } on ApiException catch (e) {
          expect(e.code, 'REAUTH_FAILED');
          expect(deleteAccountErrorHe(e), contains('לאמת את הזהות'));
        }
        await Future<void>.delayed(Duration.zero);
        expect(events, isEmpty);
        await sub.cancel();
        expect(api.hasDeviceToken, isTrue);
      },
    );

    test(
      'logout-all is a bearer POST /mobile/logout-all without a business header',
      () async {
        signIn();
        respond(200, {'status': 'ok', 'revoked': 2});
        await logoutAllDevices();
        expect(sent.last.method, 'POST');
        expect(sent.last.url.path, '/mobile/logout-all');
        expect(sent.last.headers['Authorization'], startsWith('Bearer inv_'));
        expect(sent.last.headers.containsKey('X-Business-Id'), isFalse);
      },
    );

    test(
      'account deletion removes a V1 custom WhatsApp wording from the Keychain',
      () async {
        signIn();
        await waTemplateStorage.write(
          key: waTemplateKey,
          value: 'היי {שם} {קישור}',
        );
        expect(await loadWhatsAppTemplate(), 'היי {שם} {קישור}');
        respond(200, {'status': 'deleted'});
        await deleteAccount(password: 'Mobile12345678');
        expect(await loadWhatsAppTemplate(), defaultWhatsAppTemplate);
      },
    );

    test(
      'saveBusinessProfile PUTs only the changes then reloads me + profile',
      () async {
        signIn();
        api.httpClient = MockClient((request) async {
          sent.add(request);
          final body = switch (request.url.path) {
            '/me' => {
              'userId': 'u1',
              'role': 'OWNER',
              'canConfigure': true,
              'canFinalize': true,
              'onboarding': {'completed': true},
            },
            _ => {
              'profile': {
                'legalName': 'סטודיו תבל',
                'businessType': 'OSEK_MURSHE',
                'paymentLinkUrl': 'https://pay.test/x',
                'identityLocked': true,
                'onboarding': {'completed': true},
              },
            },
          };
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });
        await saveBusinessProfile({'paymentLinkUrl': 'https://pay.test/x'});
        expect(sent.first.method, 'PUT');
        expect(jsonDecode(sent.first.body), {
          'paymentLinkUrl': 'https://pay.test/x',
        });
        expect(sent.first.headers['X-Business-Id'], 'biz-1');
        expect(session.profile!.paymentLinkUrl, 'https://pay.test/x');
      },
    );
  });
}
