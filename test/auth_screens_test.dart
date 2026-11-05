import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/auth/app_lock.dart';
import 'package:invoice/screens/auth/auth_flow.dart';
import 'package:invoice/screens/auth/login_screen.dart';
import 'package:invoice/screens/auth/mfa_sheet.dart';
import 'package:invoice/screens/auth/onboarding_screen.dart';
import 'package:invoice/screens/business/delete_account_screen.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/session.dart';
import 'package:invoice/ui/theme.dart';
import 'package:invoice/util/biometric.dart';
import 'package:local_auth/local_auth.dart';

Widget app(Widget home, {Brightness brightness = Brightness.light, TransitionBuilder? builder}) =>
    MaterialApp(
      navigatorKey: navigatorKey,
      locale: const Locale('he', 'IL'),
      supportedLocales: const [Locale('he', 'IL')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(brightness),
      builder: builder,
      home: home,
    );

/// Route-table mock: "METHOD /path" → (status, body). Records every request.
final List<http.Request> sent = [];
void serve(Map<String, (int, Object)> routes) {
  ApiClient.instance.httpClient = MockClient((request) async {
    sent.add(request);
    final hit = routes['${request.method} ${request.url.path}'];
    if (hit == null) return http.Response(jsonEncode({'error': 'NOT_FOUND'}), 404);
    return http.Response(jsonEncode(hit.$2), hit.$1,
        headers: {'content-type': 'application/json; charset=utf-8'});
  });
}

/// Every label in the live semantics tree (what VoiceOver can reach).
List<String> semanticLabels(WidgetTester tester) {
  final labels = <String>[];
  bool visit(SemanticsNode node) {
    if (node.label.isNotEmpty) labels.add(node.label);
    node.visitChildren(visit);
    return true;
  }

  visit(tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
  return labels;
}

/// iPhone-sized surface (390×844 pt).
void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

class _FakeAuth extends LocalAuthentication {
  bool supported = true;
  bool answer = true;
  int prompts = 0;

  @override
  Future<bool> isDeviceSupported() async => supported;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => [BiometricType.face];

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<Object> authMessages = const [],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    prompts++;
    return answer;
  }
}

void main() {
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('auth_test');
    AppCache.directoryProvider = () async => tmp;
  });

  setUp(() {
    sent.clear();
    ApiClient.instance.clearCredentials();
    FlutterSecureStorage.setMockInitialValues({});
    session
      ..status = SessionStatus.signedOut
      ..account = null
      ..business = null
      ..me = null
      ..profile = null;
  });

  testWidgets('login: Apple first, no Google (needs Firebase), local validation', (tester) async {
    phone(tester);
    for (final b in Brightness.values) {
      await tester.pumpWidget(app(const LoginScreen(sessionExpired: true), brightness: b));
      expect(find.text('המשך עם Apple'), findsOneWidget);
      expect(find.text('המשך עם Google'), findsNothing);
      expect(find.text('פג תוקף ההתחברות — נא להיכנס שוב'), findsOneWidget);
      expect(find.text('לתנאי השימוש'), findsOneWidget);
      expect(find.text('ולמדיניות הפרטיות'), findsOneWidget);
      expect(tester.getTopLeft(find.text('המשך עם Apple')).dy,
          lessThan(tester.getTopLeft(find.text('כניסה')).dy));
      expect(tester.takeException(), isNull);
    }
    await tester.enterText(find.byType(TextField).first, 'not-an-email');
    await tester.ensureVisible(find.text('כניסה'));
    await tester.tap(find.text('כניסה'));
    await tester.pump();
    expect(find.text('נא להזין כתובת מייל תקינה'), findsOneWidget);
    expect(sent, isEmpty);
  });

  testWidgets('login error shows Hebrew message inline', (tester) async {
    phone(tester);
    serve({'POST /auth/login': (401, {'error': 'INVALID_CREDENTIALS'})});
    await tester.pumpWidget(app(const LoginScreen()));
    await tester.enterText(find.byType(TextField).at(0), 'a@tevel.test');
    await tester.enterText(find.byType(TextField).at(1), 'wrong');
    await tester.ensureVisible(find.text('כניסה'));
    await tester.tap(find.text('כניסה'));
    await tester.pumpAndSettle();
    expect(find.text('האימייל או הסיסמה שגויים'), findsOneWidget);
  });

  testWidgets('password → device token → several businesses → required picker', (tester) async {
    phone(tester);
    serve({
      'POST /auth/login': (
        200,
        {'status': 'PASSWORD_OK', 'mfaRequired': false, 'csrfToken': 'c', 'businesses': []}
      ),
      'POST /auth/device-token': (
        201,
        {'token': 'inv_${'a' * 48}', 'tokenId': 't', 'expiresAt': '2027-01-01T00:00:00Z'}
      ),
      'GET /mobile/session': (
        200,
        {
          'userId': 'u',
          'email': 'e@tevel.test',
          'displayName': null,
          'businesses': [
            {'businessId': 'b1', 'legalName': 'סטודיו תבל', 'role': 'OWNER'},
            {'businessId': 'b2', 'legalName': 'דנה כהן – עיצוב', 'role': 'EMPLOYEE'},
          ]
        }
      ),
    });
    await tester.pumpWidget(app(const LoginScreen()));
    await tester.enterText(find.byType(TextField).at(0), 'e@tevel.test');
    await tester.enterText(find.byType(TextField).at(1), 'Mobile12345678');
    await tester.ensureVisible(find.text('כניסה'));
    await tester.tap(find.text('כניסה'));
    // AppCache writes real files: let real async I/O run.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pump(const Duration(seconds: 1)); // login spinner keeps running under the sheet
    expect(ApiClient.instance.deviceToken, startsWith('inv_'));
    expect(session.status, SessionStatus.signedIn);
    expect(find.text('החלפת עסק'), findsOneWidget); // S14, required
    expect(find.text('דנה כהן – עיצוב'), findsOneWidget);
    expect(find.text('עובד'), findsOneWidget);
    final paths = sent.map((r) => '${r.method} ${r.url.path}').toList();
    expect(paths, ['POST /auth/login', 'POST /auth/device-token', 'GET /mobile/session']);
    expect(sent[1].headers['X-CSRF-Token'], 'c');
  });

  testWidgets('MFA sheet: auto-sends e-mail code, wrong code clears, right code returns true',
      (tester) async {
    phone(tester);
    var verifyCalls = 0;
    ApiClient.instance.httpClient = MockClient((request) async {
      sent.add(request);
      final key = '${request.method} ${request.url.path}';
      final (int, Object) r = switch (key) {
        'GET /auth/mfa/methods' => (
            200,
            {
              'totp': false,
              'email': {'enabled': true},
              'emailAvailable': true,
              'recoveryCodesRemaining': 0
            }
          ),
        'POST /auth/mfa/email/send' => (200, {'sentTo': 'mo***@tevel.test', 'resendAfterSeconds': 45}),
        'POST /auth/mfa/email/verify' => ++verifyCalls == 1
            ? (401, {'error': 'MFA_CODE_INVALID'})
            : (200, {'status': 'ok', 'recoveryCodes': null, 'csrfToken': 'c2'}),
        _ => (404, {'error': 'NOT_FOUND'}),
      };
      return http.Response(jsonEncode(r.$2), r.$1,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    bool? result;
    await tester.pumpWidget(app(Builder(
      builder: (context) => Scaffold(
        body: TextButton(
            onPressed: () async => result = await showMfaStep(context), child: const Text('open')),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('mo***@tevel.test'), findsOneWidget);
    expect(find.textContaining('אפשר לשלוח קוד חדש בעוד'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '111111');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('קוד האימות שגוי'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);

    await tester.enterText(find.byType(TextField), '222222');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(result, isTrue);
    expect(ApiClient.instance.csrfToken, 'c2');
    expect(jsonDecode(sent.last.body), {'code': '222222'});
    await tester.pump(const Duration(seconds: 60)); // drain the resend ticker
  });

  testWidgets('MFA enroll shows recovery codes once, "שמרתי" returns true', (tester) async {
    phone(tester);
    serve({
      'POST /auth/mfa/email/send': (200, {'sentTo': 'ne***@tevel.test', 'resendAfterSeconds': 30}),
      'POST /auth/mfa/email/verify': (
        200,
        {'status': 'ok', 'recoveryCodes': ['abcd-efgh', 'ijkl-mnop'], 'csrfToken': 'c'}
      ),
    });
    bool? result;
    await tester.pumpWidget(app(Builder(
      builder: (context) => Scaffold(
        body: TextButton(
            onPressed: () async => result = await showMfaStep(context, enroll: true),
            child: const Text('open')),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('עוד שכבת הגנה'), findsOneWidget);
    expect(sent.any((r) => r.url.path == '/auth/mfa/methods'), isFalse);
    expect(jsonDecode(sent.first.body), {'purpose': 'ENROLL'});
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('abcd-efgh'), findsOneWidget);
    await tester.ensureVisible(find.text('שמרתי, המשך'));
    await tester.tap(find.text('שמרתי, המשך'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(result, isTrue);
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('onboarding (§6.A): type card → details → numbering → saves and pops', (tester) async {
    phone(tester);
    session.profile = BusinessProfile.fromJson({
      'legalName': 'העסק של דנה',
      'businessType': 'OSEK_MURSHE',
      'taxId': null,
      'identityLocked': false,
      'onboarding': {'completed': false},
    });
    session.business = const Business(businessId: 'b1', legalName: 'x', role: 'OWNER');
    ApiClient.instance
      ..deviceToken = 'inv_x'
      ..businessId = 'b1';
    serve({
      'PUT /business/profile': (
        200,
        {'profile': {'legalName': 'דנה כהן – עיצוב', 'businessType': 'OSEK_PATUR'}}
      ),
      'PUT /business/onboarding': (200, {'onboarding': {'completed': true}}),
      'GET /sequences': (
        200,
        {
          'sequences': [
            {'numbering_scope_key': 'default', 'next_number': '1'}
          ]
        }
      ),
      'PUT /sequences/default/start': (200, {'scopeKey': 'default', 'nextNumber': 1042}),
      'GET /me': (
        200,
        {'userId': 'u', 'role': 'OWNER', 'onboarding': {'completed': true}, 'canConfigure': true}
      ),
      'GET /business/profile': (
        200,
        {'profile': {'legalName': 'דנה כהן – עיצוב', 'businessType': 'OSEK_PATUR'}}
      ),
      'GET /mobile/session': (
        200,
        {
          'userId': 'u',
          'email': 'e',
          'businesses': [
            {'businessId': 'b1', 'legalName': 'דנה כהן – עיצוב', 'role': 'OWNER'}
          ]
        }
      ),
    });
    await tester.pumpWidget(app(Builder(
      builder: (context) => Scaffold(
        body: TextButton(onPressed: () => openSetup(context), child: const Text('go')),
      ),
    )));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('איזה עסק יש לך?'), findsOneWidget);
    expect(find.text('עמותה / מלכ"ר'), findsOneWidget); // 4 cards
    expect(find.text('שותפות'), findsNothing); // under "עוד ▾"
    await tester.tap(find.text('עוסק פטור'));
    await tester.pumpAndSettle();
    expect(find.text('פרטי העסק'), findsOneWidget);
    // Placeholder name is not prefilled.
    expect(find.text('העסק של דנה'), findsNothing);

    await tester.enterText(find.byType(TextField).at(0), 'דנה כהן – עיצוב');
    await tester.enterText(find.byType(TextField).at(1), '123456789');
    await tester.enterText(find.byType(TextField).at(2), 'עיצוב גרפי');
    await tester.tap(find.byKey(const Key('setup-next')));
    await tester.pump();
    expect(find.text('המספר לא תקין — בדוק את הספרות'), findsOneWidget);
    expect(sent, isEmpty);

    await tester.enterText(find.byType(TextField).at(1), '123456782');
    await tester.tap(find.byKey(const Key('setup-next')));
    await tester.pumpAndSettle();
    // Step 3: numbering.
    expect(find.text('כבר הפקת חשבוניות במקום אחר?'), findsOneWidget);
    await tester.tap(find.text('כן'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('setup-start-number')), '1042');
    await tester.tap(find.byKey(const Key('setup-next')));
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('go'), findsOneWidget); // popped back
    final put = sent.firstWhere((r) => r.url.path == '/business/profile' && r.method == 'PUT');
    expect(jsonDecode(put.body), {
      'legalName': 'דנה כהן – עיצוב',
      'businessType': 'OSEK_PATUR',
      'taxId': '123456782',
      'defaultLineDescription': 'עיצוב גרפי',
    });
    final start = sent.firstWhere((r) => r.url.path == '/sequences/default/start');
    expect(jsonDecode(start.body), {'nextNumber': 1042});
    expect(sent.any((r) => r.url.path == '/business/onboarding'), isTrue);
    expect(session.profile!.businessType, 'OSEK_PATUR');
  });

  testWidgets('app lock: privacy cover in background, Face ID after the lock delay',
      (tester) async {
    phone(tester);
    final fake = _FakeAuth();
    Biometric.instance.auth = fake;
    session.status = SessionStatus.signedIn;
    await tester.pumpWidget(app(
      const Scaffold(body: Text('₪1,180.00')),
      builder: (context, child) => AppLockGate(lockAfter: Duration.zero, child: child!),
    ));
    expect(find.byType(PrivacyCover), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byType(PrivacyCover), findsOneWidget);

    // Back without having been backgrounded → no prompt.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyCover), findsNothing);
    expect(fake.prompts, 0);

    // Backgrounded past the delay, Face ID fails → lock view stays.
    fake.answer = false;
    for (final s in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(fake.prompts, 1);
    expect(find.text('תבל נעולה'), findsOneWidget);
    // VoiceOver cannot reach the amounts behind the lock.
    final semantics = tester.ensureSemantics();
    await tester.pump();
    final labels = semanticLabels(tester).join('\n');
    expect(labels, contains('תבל נעולה'));
    expect(labels, isNot(contains('1,180')));
    semantics.dispose();
    expect(find.text('פתיחה עם Face ID'), findsOneWidget);

    fake.answer = true;
    await tester.tap(find.text('פתיחה עם Face ID'));
    await tester.pumpAndSettle();
    expect(find.text('תבל נעולה'), findsNothing);
    expect(find.text('₪1,180.00'), findsOneWidget);
  });

  testWidgets('no business: account deletion is reachable', (tester) async {
    phone(tester);
    session
      ..status = SessionStatus.signedIn
      ..account = null;
    await tester.pumpWidget(app(const NoBusinessScreen()));
    expect(find.text('פתיחה בדפדפן'), findsNothing); // F6: no browser for a business action
    await tester.ensureVisible(find.text('מחק חשבון'));
    await tester.tap(find.text('מחק חשבון'));
    await tester.pumpAndSettle();
    expect(find.byType(DeleteAccountScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dynamic Type XXL + dark mode: login, onboarding, lock view do not overflow',
      (tester) async {
    phone(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    Biometric.instance.auth = _FakeAuth();
    for (final b in Brightness.values) {
      for (final screen in <Widget>[
        const LoginScreen(sessionExpired: true),
        const OnboardingScreen(),
        LockView(onUnlock: () async {}, onSignOut: () async {}),
      ]) {
        await tester.pumpWidget(app(screen, brightness: b));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: '${screen.runtimeType} $b');
      }
    }
  });
}
