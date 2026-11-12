// QA (qa-compose) helpers for integration_test/v2_qa-compose_test.dart.
// Real app + real dev API (:3031, never prod). Server state is set up and
// verified with plain HTTP as the preset users of docs/API-MOBILE.md
// ("V2 · שילוב ובדיקות"); the app itself is signed in by writing a device
// token to the Keychain and running session.restore() (no login UI — that is
// v2_login_smoke_test.dart's job).
//
// Taps are counted per SPEC-v2 §1 F3.1 with [TapCounter]: every tap on a
// button / row / chip / cell, plus [TapCounter.system] for a tap the test
// cannot drive (a cell in CNContactPicker, a Face ID confirm). Typing on the
// keypad and in auto-focused fields is not counted.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/customers_api.dart' show rememberRecentCustomer;
import 'package:invoice/app_shell.dart';
import 'package:invoice/main.dart' as app;
import 'package:invoice/router.dart';
import 'package:invoice/screens/home/home_screen.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/api/client.dart' show ApiClient;
import 'package:invoice/state/session.dart';
import 'package:invoice/ui/ds.dart';
import 'qa_plans_guard.dart';

const String apiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://127.0.0.1:3031');

/// Dev MFA mails (JSON files; the code is the first 6 chars of `subject`).
/// The simulator can read the host file system; pass
/// `--dart-define=MAILDIR=$HOME/invoiceproject-mobile-dev-storage/outgoing-emails`.
const String mailDir = String.fromEnvironment('MAILDIR');

const String devPassword = 'Mobile12345678';

/// "סטודיו תבל לדוגמה" (OSEK_MURSHE) and "דנה כהן – עיצוב" (OSEK_PATUR).
const String murshe = '3b773037-e71d-49bd-a951-76845e4abe07';
const String patur = 'c934a7a8-df74-433d-a5e2-e342c16142b1';

/// Preset accounts (docs/API-MOBILE.md "Role presets").
const String ownerEmail = 'mobile-owner@tevel.test';
const String partnerEmail = 'mobile-partner@tevel.test';
const String employeeSelfEmail = 'mobile-employee@tevel.test'; // עובד + מפיק בעצמו
const String staffEmail = 'mobile-staff@tevel.test'; // עובד
const String paturEmail = 'mobile-patur@tevel.test';

final Random _rnd = Random();
String uniq() => '${DateTime.now().millisecondsSinceEpoch % 100000000}${_rnd.nextInt(90) + 10}';
String today() {
  final d = DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

String yesterday() {
  final d = DateTime.now().subtract(const Duration(days: 1));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ---- HTTP ---------------------------------------------------------------------

class ApiRes {
  ApiRes(this.status, this.json, this.raw);
  final int status;
  final Map<String, dynamic> json;
  final String raw;

  String? get error => json['error'] as String?;
  bool get ok => status >= 200 && status < 300;

  @override
  String toString() => 'HTTP $status $raw';
}

final HttpClient _http = HttpClient()..connectionTimeout = const Duration(seconds: 10);

Future<ApiRes> _send(String method, String path,
    {Object? body, Map<String, String> headers = const {}, List<Cookie>? jar}) async {
  final req = await _http.openUrl(method, Uri.parse('$apiBase$path'));
  headers.forEach(req.headers.set);
  if (jar != null && jar.isNotEmpty) req.cookies.addAll(jar);
  if (body != null) {
    req.headers.contentType = ContentType.json;
    req.add(utf8.encode(jsonEncode(body)));
  }
  final res = await req.close();
  final text = await utf8.decodeStream(res);
  if (jar != null) {
    for (final c in res.cookies) {
      jar
        ..removeWhere((e) => e.name == c.name)
        ..add(Cookie(c.name, c.value));
    }
  }
  Map<String, dynamic> json = const {};
  try {
    final v = jsonDecode(text);
    if (v is Map<String, dynamic>) json = v;
  } on FormatException {
    // PDF / HTML
  }
  return ApiRes(res.statusCode, json, text);
}

/// Plain GET of a public page (`/d/<token>`, `/q/<token>`).
Future<ApiRes> getPublic(String url) async {
  final req = await _http.getUrl(Uri.parse(url));
  final res = await req.close();
  return ApiRes(res.statusCode, const {}, await utf8.decodeStream(res));
}

/// One preset user holding a device token for one business.
class DevUser {
  DevUser(this.email, this.businessId, this.token);
  final String email;
  final String businessId;
  final String token;

  Future<ApiRes> call(String method, String path, {Object? body, bool idempotent = false}) => _send(
        method,
        path,
        body: body,
        headers: {
          'authorization': 'Bearer $token',
          'x-business-id': businessId,
          if (idempotent) 'idempotency-key': 'qa-compose-${uniq()}-${_rnd.nextInt(1 << 30)}',
        },
      );

  Future<ApiRes> get(String path) => call('GET', path);
  Future<ApiRes> post(String path, [Object? body = const {}, bool idem = false]) =>
      call('POST', path, body: body, idempotent: idem);

  /// Like [post] but fails the test on a non-2xx answer.
  Future<Map<String, dynamic>> must(String method, String path, [Object? body, bool idem = false]) async {
    final r = await call(method, path, body: body ?? (method == 'GET' ? null : const {}), idempotent: idem);
    expect(r.ok, isTrue, reason: '$email $method $path → $r');
    return r.json;
  }
}

final Map<String, DevUser> _users = {};

/// Signs [email] in once per run (cookie → MFA e-mail code → device token).
Future<DevUser> devUser(String email, {String businessId = murshe}) async {
  final key = '$email|$businessId';
  final cached = _users[key];
  if (cached != null) return cached;
  final jar = <Cookie>[];
  final login = await _send('POST', '/auth/login', body: {'email': email, 'password': devPassword}, jar: jar);
  expect(login.ok, isTrue, reason: 'login $email → $login');
  var csrf = login.json['csrfToken'] as String;
  Future<void> mfa(String purpose) async {
    expect(mailDir, isNotEmpty, reason: 'MFA user $email needs --dart-define=MAILDIR=…');
    final since = DateTime.now().subtract(const Duration(seconds: 2));
    var sent = await _send('POST', '/auth/mfa/email/send',
        body: {'purpose': purpose}, headers: {'x-csrf-token': csrf}, jar: jar);
    if (sent.error == 'MFA_EMAIL_THROTTLED') {
      await Future<void>.delayed(const Duration(seconds: 46));
      sent = await _send('POST', '/auth/mfa/email/send',
          body: {'purpose': purpose}, headers: {'x-csrf-token': csrf}, jar: jar);
    }
    expect(sent.ok, isTrue, reason: 'mfa send $email → $sent');
    String? code;
    for (var i = 0; i < 40 && code == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      code = _latestCode(email, since);
    }
    expect(code, isNotNull, reason: 'no MFA e-mail for $email in $mailDir');
    final verified = await _send('POST', '/auth/mfa/email/verify',
        body: {'code': code, if (purpose == 'ENROLL') 'purpose': purpose}, headers: {'x-csrf-token': csrf}, jar: jar);
    expect(verified.ok, isTrue, reason: 'mfa verify $email → $verified');
    csrf = verified.json['csrfToken'] as String? ?? csrf;
  }

  if (login.json['status'] == 'MFA_REQUIRED') await mfa('LOGIN');
  var dt = await _send('POST', '/auth/device-token',
      body: {'deviceName': 'qa-compose'}, headers: {'x-csrf-token': csrf}, jar: jar);
  if (dt.error == 'MFA_REQUIRED') {
    // Privileged role without an enrolled method (e.g. a P0 accountant moved
    // to ACCOUNTANT_REP by the owner's B·צוות visit): enrol e-mail first.
    await mfa('ENROLL');
    dt = await _send('POST', '/auth/device-token',
        body: {'deviceName': 'qa-compose'}, headers: {'x-csrf-token': csrf}, jar: jar);
  }
  expect(dt.ok, isTrue, reason: 'device-token $email → $dt');
  return _users[key] = DevUser(email, businessId, dt.json['token'] as String);
}

String? _latestCode(String to, DateTime since) {
  final dir = Directory(mailDir);
  if (!dir.existsSync()) return null;
  final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
    ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
  for (final f in files.take(50)) {
    if (f.statSync().modified.isBefore(since)) break;
    final m = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final subject = '${m['subject']}';
    if (m['to'] == to && RegExp(r'^\d{6}').hasMatch(subject)) return subject.substring(0, 6);
  }
  return null;
}

/// Revokes every device token this run minted.
Future<void> revokeDevUsers() async {
  for (final u in _users.values) {
    await _send('POST', '/mobile/logout', body: const {}, headers: {'authorization': 'Bearer ${u.token}'});
  }
  _users.clear();
}

// ---- server fixtures --------------------------------------------------------------

/// A fresh customer (unique name) — tests never depend on seed rows.
Future<String> createCustomer(DevUser u,
    {String? name, String? phone, String? email, String? taxId, String? vatDealerStatus}) async {
  final json = await u.must('POST', '/customers', {
    'name': name ?? 'QA-C ${uniq()}',
    'customerType': taxId == null ? 'INDIVIDUAL' : 'BUSINESS',
    'phone': ?phone,
    'email': ?email,
    'taxId': ?taxId,
    'vatDealerStatus': ?vatDealerStatus,
  });
  return json['id'] as String;
}

String randomPhone() => '05${_rnd.nextInt(9) + 1}${(_rnd.nextInt(9000000) + 1000000)}';

Map<String, dynamic> line(String description, int unitPriceMinor, {int vatBp = 1800}) => {
      'description': description,
      'quantityMicros': '1000000',
      'unitPriceMinor': '$unitPriceMinor',
      'taxRateBasisPoints': vatBp,
    };

/// POST /documents (+ finalize, artifact, share-link). Returns the id.
Future<String> createDocument(
  DevUser u, {
  required String type,
  required String customerId,
  required int unitPriceMinor,
  int vatBp = 1800,
  String description = 'QA שורה',
  bool finalize = true,
  bool shareLink = false,
}) async {
  final created = await u.must('POST', '/documents', {
    'documentType': type,
    'customerId': customerId,
    'currency': 'ILS',
    'fiscalContext': 'default',
    'lines': [line(description, unitPriceMinor, vatBp: vatBp)],
  });
  final id = created['id'] as String;
  if (!finalize) return id;
  final fin = await u.must('POST', '/documents/$id/finalize', {'scopeKey': 'default'}, true);
  expect(fin['status'], 'FINALIZED', reason: 'finalize $type → $fin');
  await u.must('POST', '/documents/$id/artifact');
  if (shareLink) await u.must('POST', '/documents/$id/share-link');
  return id;
}

/// GET /documents/:id → `document` (with `lines` added).
Future<Map<String, dynamic>> docDetail(DevUser u, String id) async {
  final j = await u.must('GET', '/documents/$id');
  return {...(j['document'] as Map<String, dynamic>), 'lines': j['lines']};
}

/// GET /documents?customerId= (newest first).
Future<List<Map<String, dynamic>>> docsOf(DevUser u, String customerId) async {
  final j = await u.must('GET', '/documents?customerId=$customerId&limit=20');
  return (j['documents'] as List).cast<Map<String, dynamic>>();
}

/// GET /quotes/:id → `quote`.
Future<Map<String, dynamic>> quoteDetail(DevUser u, String id) async =>
    (await u.must('GET', '/quotes/$id'))['quote'] as Map<String, dynamic>;

/// POST /quotes (lines at 18%) [+ status SENT]. Returns the id.
Future<String> createQuote(DevUser u, String customerId, int unitPriceMinor, {bool sent = false}) async {
  final j = await u.must('POST', '/quotes', {
    'customerId': customerId,
    'currency': 'ILS',
    'validUntil': DateTime.now().add(const Duration(days: 14)).toIso8601String().substring(0, 10),
    'lines': [line('QA הצעה', unitPriceMinor)],
  });
  final id = j['id'] as String;
  if (sent) await u.must('POST', '/quotes/$id/status', {'to': 'SENT'});
  return id;
}

/// PUT /settings/approval (owner). [thresholdMinor] is incl. VAT (§4.8).
Future<ApiRes> setApproval(DevUser owner, {required String mode, int thresholdMinor = 0, bool self = false}) =>
    owner.call('PUT', '/settings/approval',
        body: {'mode': mode, 'thresholdMinor': '$thresholdMinor', 'selfApprovalAllowed': self});

int minor(Object? v) => v == null ? -1 : int.parse('$v');

// ---- app ------------------------------------------------------------------------------

/// Counts taps per F3.1.
class TapCounter {
  TapCounter(this.tester);
  final WidgetTester tester;
  int taps = 0;

  /// A counted tap on [f] (must exist), then a short settle.
  Future<void> tap(Finder f, {String? why}) async {
    expect(f, findsWidgets, reason: 'tap target missing${why == null ? '' : ' ($why)'}: $f');
    await tester.ensureVisible(f.first);
    await tester.pump(const Duration(milliseconds: 100));
    await uncover(tester, f.first);
    taps++;
    await tester.tap(f.first, warnIfMissed: false);
    await pumpFor(tester, const Duration(milliseconds: 600));
  }

  /// A tap the test cannot perform (system picker cell, Face ID confirm).
  void system() => taps++;
}

Future<void> pumpFor(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps until [f] finds something (real network: up to [timeout]).
Future<void> pumpUntil(WidgetTester tester, Finder f,
    {Duration timeout = const Duration(seconds: 45), String? reason}) async {
  final end = DateTime.now().add(timeout);
  while (f.evaluate().isEmpty && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(f, findsWidgets, reason: reason ?? 'timed out waiting for $f');
}

/// Pumps until [cond] holds (e.g. a server state polled elsewhere).
Future<void> pumpWhile(WidgetTester tester, bool Function() cond,
    {Duration timeout = const Duration(seconds: 45)}) async {
  final end = DateTime.now().add(timeout);
  while (cond() && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

const FlutterSecureStorage _keychain = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device));

/// Puts the app in front of [u] on H the way a returning user opens it:
/// Keychain token + business (Face ID lock off) → app.main() → splash →
/// session.restore() → H. Calling it again switches the user.
Future<void> signInApp(WidgetTester tester, DevUser u) async {
  await tester.runAsync(() async {
    await AppCache.isFirstLaunch(); // install marker, so restore keeps the token
    await AppCache.clearAll();
    await _keychain.write(key: 'biometric_enabled', value: '0');
    await _keychain.write(key: 'device_token', value: u.token);
    await _keychain.write(key: 'business_id', value: u.businessId);
  });
  // A cold start: drop the previous tree (app.main() alone would re-use the
  // global navigatorKey and keep the previous user's routes and H).
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 300));
  // A real cold start has no in-memory session; without this the previous
  // user's /me (userId, caps) survives the switch.
  ApiClient.instance.clearCredentials();
  session
    ..status = SessionStatus.unknown
    ..expired = false
    ..offline = false
    ..account = null
    ..business = null
    ..me = null
    ..profile = null
    ..meFetchedAt = null;
  app.main();
  // The previous user's H can still be the first route for a moment: wait for
  // the restore itself, then for H.
  await pumpWhile(tester,
      () => session.status != SessionStatus.signedIn || session.business?.businessId != u.businessId,
      timeout: const Duration(seconds: 45));
  await pumpUntil(tester, find.byType(HomeScreen), reason: 'H after restore as ${u.email}');
  expect(session.status, SessionStatus.signedIn);
  expect(session.business?.businessId, u.businessId);
  await pumpFor(tester, const Duration(seconds: 2)); // H: cache → network
}

/// Keypad digits ("1180", "4999.99"). Typing is not counted (F3.1).
Future<void> typeAmount(WidgetTester tester, String text) async {
  for (final ch in text.split('')) {
    await tester.tap(find.descendant(of: find.byType(Keypad), matching: find.text(ch)).first);
    await tester.pump(const Duration(milliseconds: 60));
  }
  await pumpFor(tester, const Duration(milliseconds: 400));
}

/// Clears the keypad amount (long press on "מחק").
Future<void> clearAmount(WidgetTester tester) async {
  await tester.longPress(
      find.descendant(of: find.byType(Keypad), matching: find.byIcon(Icons.backspace_outlined)).first);
  await pumpFor(tester, const Duration(milliseconds: 300));
}

/// The label of the PrimaryButton with [key] (null when absent).
String? primaryLabel(WidgetTester tester, Key key) {
  final f = find.byKey(key);
  if (f.evaluate().isEmpty) return null;
  return (tester.widget(f) as PrimaryButton).label;
}

/// AT-90: 0 or 1 PrimaryButton on the visible route.
void expectAtMostOnePrimary(String where) {
  // Per screen/sheet (AT-90): when a sheet is open, D's own primary below it
  // is still on stage — count only the top route's buttons.
  final all = find.byType(PrimaryButton, skipOffstage: true).evaluate().toList();
  final top = all.where((e) => ModalRoute.of(e)?.isCurrent ?? true).toList();
  final found = top.isEmpty ? all : top;
  final labels = [
    for (final e in found)
      '${(e.widget as PrimaryButton).label}@${ModalRoute.of(e)?.settings.name ?? ModalRoute.of(e).runtimeType}'
  ];
  expect(found.length, lessThanOrEqualTo(1),
      reason: 'AT-90 F2: more than one PrimaryButton on $where: $labels');
}

/// The "⋯" of the top route.
Finder moreButton() => find.byTooltip('עוד').last;

/// Labels currently listed in an open ⋯ sheet / anywhere on screen.
bool onScreen(String text) => find.text(text).evaluate().isNotEmpty;

/// The navigator context (to open D / a quote like a row in L would).
BuildContext navContext() => navigatorKey.currentContext!;

/// AppShell present (signed in, tabs mounted).
Finder shell() => find.byType(AppShell);

/// A customer used on this device before (S2 shows it as a recent circle).
Future<void> rememberRecentForTest(String customerId) => rememberRecentCustomer(customerId);

/// D of a document / quote, pushed like a row in L would.
Future<void> openDocumentForTest(String id) => openDocument(navContext(), id);
Future<void> openQuoteForTest(String id) => openQuote(navContext(), id);

/// Back to H (tabs) without signing in again (keeps the Composer memory).
void resetHomeForTest() => resetToHome();

/// Closes the top route (C has a ✕, so `tester.pageBack()` finds no back button).
void closeTopForTest() => navigatorKey.currentState!.pop();
