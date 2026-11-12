// QA gate helpers (owner: QA, SPEC-v2 §18.1 `integration_test/**`).
//
// * DevApi: a tiny HTTP client of its own (not the app's ApiClient singleton)
//   that signs in to the LOCAL dev API like the app does (cookie + CSRF →
//   e-mail MFA from the dev mail folder → device token) to set up and verify
//   state. Never prod: the base URL defaults to http://127.0.0.1:3031.
// * Device reset / token injection so every testWidgets starts from a known
//   state, and UI helpers (pumpUntil, TapCounter for the §1 F3 tap budgets).
//
// Required for the MFA presets: --dart-define=MAILDIR=<host path to
// ~/invoiceproject-mobile-dev-storage/outgoing-emails> (the simulator app
// reads the host file system).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:invoice/api/client.dart';
import 'package:invoice/main.dart' as app;
import 'package:invoice/screens/auth/login_screen.dart';
import 'package:invoice/screens/auth/mfa_sheet.dart';
import 'package:invoice/screens/business/sheets/s14_switch.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/session.dart';
import 'package:invoice/ui/money_text.dart' show ltrIsolate;
import 'package:invoice/util/biometric.dart';
import 'package:invoice/util/errors_he.dart';
import 'package:invoice/util/labels/labels.dart';
import 'qa_plans_guard.dart';

const String apiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://127.0.0.1:3031',
);
const String mailDir = String.fromEnvironment('MAILDIR');

/// Seeded dev accounts (docs/API-MOBILE.md "Role presets").
const String devPassword = 'Mobile12345678';
const String devBusinessId = '3b773037-e71d-49bd-a951-76845e4abe07';
const String devBusinessName = 'סטודיו תבל לדוגמה';
const String ownerEmail = 'mobile-owner@tevel.test';
const String staffEmail = 'mobile-staff@tevel.test';
const String cpaRepEmail = 'mobile-cpa-rep@tevel.test';

/// Throwaway accounts created by this suite (deleted again at the end).
const String testerPassword = 'QaGate-12345678';

String uniqueEmail(String tag) =>
    'qa-gate-$tag-${DateTime.now().millisecondsSinceEpoch}@tevel.test';

// ---- dev API ------------------------------------------------------------------

class DevApiException implements Exception {
  DevApiException(this.status, this.code, this.path);

  final int status;
  final String code;
  final String path;

  @override
  String toString() => 'DevApiException($status $code on $path)';
}

/// One signed-in account on the dev API (bearer device token).
class DevSession {
  DevSession(this.email, this.token, {this.businessId = devBusinessId});

  final String email;
  final String token;
  String? businessId;

  Future<Map<String, dynamic>> get(String path) => _call('GET', path);
  Future<Map<String, dynamic>> post(String path, [Object? body]) =>
      _call('POST', path, body ?? const {});
  Future<Map<String, dynamic>> put(String path, Object? body) =>
      _call('PUT', path, body ?? const {});

  Future<Map<String, dynamic>> _call(
    String method,
    String path, [
    Object? body,
  ]) async {
    final scoped =
        !path.startsWith('/auth/') &&
        (!path.startsWith('/mobile/') || path == '/mobile/inbox');
    final res = await _send(
      method,
      path,
      body: body,
      headers: {
        'Authorization': 'Bearer $token',
        if (scoped && businessId != null) 'X-Business-Id': businessId!,
      },
    );
    return res.json;
  }

  /// Revokes this token only (best effort).
  Future<void> logout() async {
    try {
      await _call('POST', '/mobile/logout', const {});
    } on Object {
      // already revoked
    }
  }
}

class _Response {
  _Response(this.status, this.json, this.setCookie);

  final int status;
  final Map<String, dynamic> json;
  final String? setCookie;
}

Future<_Response> _send(
  String method,
  String path, {
  Object? body,
  Map<String, String> headers = const {},
}) async {
  final req = http.Request(method, Uri.parse('$apiBase$path'))
    ..headers.addAll({'Accept': 'application/json', ...headers});
  if (body != null) {
    req.headers['Content-Type'] = 'application/json';
    req.bodyBytes = utf8.encode(jsonEncode(body));
  }
  final res = await http.Response.fromStream(
    await req.send().timeout(const Duration(seconds: 30)),
  );
  Map<String, dynamic> json = const {};
  if (res.bodyBytes.isNotEmpty) {
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is Map<String, dynamic>) json = decoded;
  }
  if (res.statusCode >= 300) {
    throw DevApiException(
      res.statusCode,
      '${json['error'] ?? 'HTTP_${res.statusCode}'}',
      path,
    );
  }
  return _Response(res.statusCode, json, res.headers['set-cookie']);
}

/// Cookie phase of one sign-in (login → MFA → device token).
class _CookieSession {
  String? cookie;
  String? csrf;

  Future<Map<String, dynamic>> post(String path, Object body) async {
    final res = await _send(
      'POST',
      path,
      body: body,
      headers: {
        if (cookie != null) 'Cookie': 'tvl_session=$cookie',
        'X-CSRF-Token': ?csrf,
      },
    );
    final m = RegExp(
      r'(?:^|[,\s])tvl_session=([^;,]*)',
    ).firstMatch(res.setCookie ?? '');
    if (m != null && m.group(1)!.isNotEmpty) cookie = m.group(1);
    final c = res.json['csrfToken'];
    if (c is String && c.isNotEmpty) csrf = c;
    return res.json;
  }

  Future<void> emailCode(String email, {required bool enroll}) async {
    final since = DateTime.now().subtract(const Duration(seconds: 2));
    await post('/auth/mfa/email/send', {
      'purpose': enroll ? 'ENROLL' : 'LOGIN',
    });
    final code = await waitForMfaCode(email, since);
    await post('/auth/mfa/email/verify', {
      'code': code,
      if (enroll) 'purpose': 'ENROLL',
    });
  }
}

/// Signs [email] in on the dev API the way the app does; enrols the e-mail
/// method when the member needs MFA and has none yet (API-MOBILE §5).
Future<DevSession> devSignIn(
  String email, {
  String password = devPassword,
  String? businessId = devBusinessId,
}) async {
  final s = _CookieSession();
  final login = await s.post('/auth/login', {
    'email': email,
    'password': password,
  });
  if (login['status'] == 'MFA_REQUIRED' || login['mfaRequired'] == true) {
    await s.emailCode(email, enroll: false);
  }
  Map<String, dynamic> minted;
  try {
    minted = await s.post('/auth/device-token', {'deviceName': 'qa-gate'});
  } on DevApiException catch (e) {
    if (e.code != 'MFA_REQUIRED') rethrow;
    await s.emailCode(email, enroll: true);
    minted = await s.post('/auth/device-token', {'deviceName': 'qa-gate'});
  }
  return DevSession(email, minted['token'] as String, businessId: businessId);
}

/// Login answer only (no token): for "the account is gone" checks.
Future<String> devLoginStatus(String email, String password) async {
  try {
    final r = await _CookieSession().post('/auth/login', {
      'email': email,
      'password': password,
    });
    return '${r['status']}';
  } on DevApiException catch (e) {
    return e.code;
  }
}

/// Owner-side: invites [email] as [role] (+ [permissions]); returns
/// (invitationId, token).
Future<(String, String)> devInvite(
  DevSession owner,
  String email, {
  String role = 'EMPLOYEE',
  List<String> permissions = const [],
}) async {
  final r = await owner.post('/business/members/invite', {
    'email': email,
    'role': role,
    if (permissions.isNotEmpty) 'permissions': permissions,
  });
  final url = '${r['inviteUrl'] ?? r['link']}';
  final token = RegExp(
    r'(?:/m/invite/|token=)([A-Za-z0-9_-]+)',
  ).firstMatch(url)!.group(1)!;
  return ('${r['invitationId']}', token);
}

/// Pending invitation row for [email] in GET /business/members, or null.
Future<Map<String, dynamic>?> devFindInvitation(
  DevSession owner,
  String email,
) async {
  final team = await owner.get('/business/members');
  for (final i in (team['invitations'] as List? ?? const [])) {
    final row = i as Map<String, dynamic>;
    if ('${row['email']}'.toLowerCase() == email.toLowerCase()) return row;
  }
  return null;
}

/// Active member row for [email], or null.
Future<Map<String, dynamic>?> devFindMember(
  DevSession owner,
  String email,
) async {
  final team = await owner.get('/business/members');
  for (final m in (team['members'] as List? ?? const [])) {
    final row = m as Map<String, dynamic>;
    if ('${row['email']}'.toLowerCase() == email.toLowerCase() &&
        row['revokedAt'] == null) {
      return row;
    }
  }
  return null;
}

/// Accepts an invitation with a password (new or existing account) on the
/// dev API, the same call the app's invite screen makes.
Future<void> devAcceptInvite(
  String token,
  String password, {
  String displayName = 'בודק QA',
}) async {
  await _CookieSession().post('/auth/invite/$token/accept', {
    'password': password,
    'displayName': displayName,
  });
}

Future<void> devRevokeInvitation(DevSession owner, String invitationId) async {
  try {
    await owner.post('/business/invitations/$invitationId/revoke');
  } on DevApiException {
    // already accepted / revoked
  }
}

// ---- dev mail folder (MFA codes) ------------------------------------------------

/// Newest 6-digit code e-mailed to [to] after [since] (API-MOBILE §3), polled.
Future<String> waitForMfaCode(
  String to,
  DateTime since, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  if (mailDir.isEmpty) {
    throw StateError(
      'MFA needs --dart-define=MAILDIR=<host>/invoiceproject-mobile-dev-storage/outgoing-emails',
    );
  }
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    final code = _latestCode(to, since);
    if (code != null) return code;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  throw StateError('no MFA e-mail for $to in $mailDir');
}

String? _latestCode(String to, DateTime since) {
  final dir = Directory(mailDir);
  if (!dir.existsSync()) return null;
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
        );
  for (final f in files) {
    if (f.statSync().modified.isBefore(since)) break;
    try {
      final m = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final subject = '${m['subject']}';
      if ('${m['to']}'.toLowerCase() == to.toLowerCase() &&
          RegExp(r'^\d{6}').hasMatch(subject)) {
        return subject.substring(0, 6);
      }
    } on Object {
      // a file still being written
    }
  }
  return null;
}

// ---- device state ----------------------------------------------------------------

/// Same Keychain options as lib/state/session.dart.
const FlutterSecureStorage keychain = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);

/// Signed-out device: revokes a token left by an earlier run, wipes the
/// session (Keychain + cache), turns the Face ID lock off (no simulator
/// prompt) and consumes the first-launch marker (so an injected token is kept).
Future<void> resetDevice() async {
  final stale = await keychain.read(key: 'device_token');
  if (stale != null) await DevSession('', stale).logout();
  if (ApiClient.instance.deviceToken != null &&
      ApiClient.instance.deviceToken != stale) {
    await DevSession('', ApiClient.instance.deviceToken!).logout();
  }
  await session.signOutLocally();
  await Biometric.instance.setEnabled(false);
  await AppCache.isFirstLaunch();
}

/// Fresh app on the sign-in screen.
Future<void> launchSignedOut(WidgetTester tester) async {
  await resetDevice();
  app.main();
  await pumpUntil(tester, find.byType(LoginScreen), reason: 'login screen');
}

/// Fresh app restored from a device token minted on the dev API for
/// [email] (as if the user had signed in earlier on this phone).
Future<DevSession> launchSignedInAs(
  WidgetTester tester,
  String email, {
  String password = devPassword,
  String businessId = devBusinessId,
}) async {
  await resetDevice();
  final s = await devSignIn(email, password: password, businessId: businessId);
  await keychain.write(key: 'device_token', value: s.token);
  await keychain.write(key: 'business_id', value: businessId);
  app.main();
  return s;
}

// ---- UI helpers ------------------------------------------------------------------

/// Pumps 200 ms frames until [finder] matches (spinners make pumpAndSettle hang).
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
  String? reason,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail(
    'timed out waiting for ${reason ?? finder.describeMatch(Plurality.one)}',
  );
}

/// Like [pumpUntil] for a row of a lazy ListView that may be below the fold:
/// scrolls the screen's main list down step by step (then back to the top)
/// until [finder] is built.
Future<void> pumpUntilScrolled(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
  String? reason,
}) async {
  final end = DateTime.now().add(timeout);
  var down = true;
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder.first);
      await tester.pump(const Duration(milliseconds: 200));
      return;
    }
    // The screen's main list: a vertical one that is on screen and hit-testable
    // (the tab PageView and the quick-action strips scroll sideways; the
    // other tabs' lists are off screen).
    final lists = find
        .byWidgetPredicate(
          (w) =>
              w is Scrollable &&
              axisDirectionToAxis(w.axisDirection) == Axis.vertical,
        )
        .hitTestable();
    if (lists.evaluate().isEmpty) continue;
    final list = lists.last;
    final pos = tester.state<ScrollableState>(list).position;
    if (down && pos.pixels >= pos.maxScrollExtent) down = false;
    if (!down && pos.pixels <= pos.minScrollExtent) down = true;
    await tester.drag(list, Offset(0, down ? -300 : 300), warnIfMissed: false);
  }
  fail(
    'timed out waiting for ${reason ?? finder.describeMatch(Plurality.one)}',
  );
}

/// Pumps until [finder] no longer matches.
Future<void> pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
  String? reason,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isEmpty) return;
  }
  fail('timed out waiting for ${reason ?? 'a widget'} to disappear');
}

Future<void> pumpFor(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Counts taps for the §1 F3 budgets (F3.1 rules: typing and auto-focused
/// fields are not counted; only [tap] calls are).
class TapCounter {
  int count = 0;

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await pumpUntil(tester, finder);
    await tester.ensureVisible(finder.first);
    await tester.pump(const Duration(milliseconds: 100));
    await uncover(tester, finder.first);
    await tester.tap(finder.first);
    count++;
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// A tap that is not part of a counted journey.
Future<void> tapOn(WidgetTester tester, Finder finder) =>
    TapCounter().tap(tester, finder);

/// Signs in on the visible LoginScreen with e-mail + password and answers the
/// MFA step (login code or first-time enrolment) from the dev mail folder.
/// [wrongCodeFirst] types a wrong code once and checks the step stays with
/// "קוד האימות שגוי". [onPickBusiness] answers S14 when it is required. Returns
/// once [until] matches; the caller asserts where the app landed.
Future<void> signInThroughUi(
  WidgetTester tester,
  String email,
  String password, {
  required Finder until,
  bool wrongCodeFirst = false,
  String? expectSentTo,
  String? pickBusinessId,
  Duration timeout = const Duration(seconds: 90),
}) async {
  await tester.enterText(find.byType(TextField).at(0), email);
  await tester.enterText(find.byType(TextField).at(1), password);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 300));
  final since = DateTime.now().subtract(const Duration(seconds: 2));
  await tapOn(tester, find.text('כניסה'));
  var answered = false;
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (until.evaluate().isNotEmpty) return;
    final boxes = find.descendant(
      of: find.byType(CodeBoxes),
      matching: find.byType(TextField),
    );
    if (!answered && boxes.evaluate().isNotEmpty) {
      if (expectSentTo != null) {
        await pumpUntil(
          tester,
          find.text(AuthHe.mfaSentTo(ltrIsolate(expectSentTo))),
          reason: '"שלחנו קוד ל-…"',
        );
      }
      final code = await waitForMfaCode(email, since);
      if (wrongCodeFirst) {
        await tester.enterText(boxes, code == '000000' ? '111111' : '000000');
        await pumpUntil(
          tester,
          find.text(errorMessageHe('MFA_CODE_INVALID')),
          reason: 'wrong-code message',
        );
        expect(
          find.byType(MfaSheet),
          findsOneWidget,
          reason: 'a wrong code keeps the MFA step',
        );
      }
      await tester.enterText(boxes, code);
      answered = true;
    }
    if (pickBusinessId != null) {
      final row = find.byKey(Key('s14-$pickBusinessId'));
      if (find.byType(SwitchBusinessSheet).evaluate().isNotEmpty &&
          row.evaluate().isNotEmpty) {
        await tester.tap(row, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 300));
      }
    }
  }
  fail('sign-in of $email did not reach ${until.describeMatch(Plurality.one)}');
}
