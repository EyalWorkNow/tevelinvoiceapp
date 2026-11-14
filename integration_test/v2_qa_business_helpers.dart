// QA (qa-business) helpers for integration_test/v2_qa-business_test.dart:
// sign-in over HTTP (e-mail MFA read from the dev mail folder, enrolment
// included), a tiny JSON client for test set-up / verification against the
// LOCAL dev API (:3031, never prod), and app launching as a given user.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:invoice/api/client.dart';
import 'package:invoice/app_shell.dart';
import 'package:invoice/main.dart' as app;
import 'package:invoice/router.dart' show navigatorKey;
import 'package:invoice/screens/billing/billing_screen.dart'
    show BillingCheckoutScreen, PlansSheet, RequiredSubscriptionScreen;
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/session.dart';
import 'package:invoice/ui/widgets/primary_button.dart';
import 'package:invoice/util/labels/labels.dart' show BusinessHe;
import 'package:local_auth/local_auth.dart';
import 'qa_plans_guard.dart';

const apiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://127.0.0.1:3031',
);
const mailDir = String.fromEnvironment(
  'MAILDIR',
  defaultValue: String.fromEnvironment(
    'MFA_MAIL_DIR',
    defaultValue:
        '/Users/eyalatiya/invoiceproject-mobile-dev-storage/outgoing-emails',
  ),
);
const devPassword = 'Mobile12345678';

/// "סטודיו תבל לדוגמה" (OSEK_MURSHE), docs/API-MOBILE.md §2.
const studioId = '3b773037-e71d-49bd-a951-76845e4abe07';

const keychain = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);

/// Face ID always succeeds (the simulator has no enrolled face).
class AlwaysUnlock implements LocalAuthentication {
  @override
  dynamic noSuchMethod(Invocation i) => switch (i.memberName) {
    #authenticate ||
    #isDeviceSupported ||
    #canCheckBiometrics => Future.value(true),
    #getAvailableBiometrics => Future.value(const [BiometricType.face]),
    _ => Future.value(false),
  };
}

class Res {
  Res(this.status, this.body);

  final int status;
  final dynamic body;

  Map<String, dynamic> get map =>
      body is Map<String, dynamic> ? body as Map<String, dynamic> : const {};
  String? get error => map['error'] as String?;

  @override
  String toString() => '$status ${jsonEncode(body)}';
}

/// One signed-in dev account: a device token + the business it acts in.
class QaUser {
  QaUser(this.email, this.token, {this.businessId = studioId});

  final String email;
  final String token;
  String businessId;

  Future<Res> call(
    String method,
    String path, {
    Object? body,
    String? business,
    Map<String, String> headers = const {},
  }) async {
    final req = http.Request(method, Uri.parse('$apiBase$path'))
      ..headers.addAll({
        'authorization': 'Bearer $token',
        'x-business-id': business ?? businessId,
        if (body != null || method != 'GET') 'content-type': 'application/json',
        ...headers,
      });
    if (body != null || method != 'GET') {
      req.body = jsonEncode(body ?? const {});
    }
    for (var attempt = 0; ; attempt++) {
      final res = await http.Response.fromStream(await req.send());
      if (res.statusCode == 429 && attempt < 3) {
        await Future<void>.delayed(const Duration(seconds: 3));
        continue;
      }
      final text = utf8.decode(res.bodyBytes);
      Object? json;
      try {
        json = text.isEmpty ? null : jsonDecode(text);
      } on FormatException {
        json = text;
      }
      return Res(res.statusCode, json);
    }
  }

  Future<Res> get(String path, {String? business}) =>
      call('GET', path, business: business);
  Future<Res> post(
    String path, [
    Object? body = const {},
    Map<String, String> headers = const {},
  ]) => call('POST', path, body: body, headers: headers);
  Future<Res> put(String path, Object body) => call('PUT', path, body: body);
  Future<Res> delete(String path) => call('DELETE', path, body: const {});

  /// GET that must answer 200; returns the JSON object.
  Future<Map<String, dynamic>> ok(String path) async {
    final r = await get(path);
    expect(r.status, 200, reason: '$email GET $path → $r');
    return r.map;
  }

  /// Revoke this device token (best effort).
  Future<void> logout() async {
    try {
      await http.post(
        Uri.parse('$apiBase/mobile/logout'),
        headers: {
          'authorization': 'Bearer $token',
          'content-type': 'application/json',
        },
        body: '{}',
      );
    } on Object {
      // already gone
    }
  }
}

final _rnd = Random.secure();

/// UUID v4 for `Idempotency-Key`.
String idemKey() {
  final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Sign in over HTTP like the app does: login → (MFA LOGIN | ENROLL) → device token.
Future<QaUser> signIn(String email, {String businessId = studioId}) async {
  String? cookie;
  String? csrf;
  Future<Res> authPost(String path, Map<String, Object?> body) async {
    for (var attempt = 0; ; attempt++) {
      final res = await http.post(
        Uri.parse('$apiBase$path'),
        headers: {
          'content-type': 'application/json',
          if (cookie != null) 'cookie': 'tvl_session=$cookie',
          if (csrf != null) 'x-csrf-token': csrf!,
        },
        body: jsonEncode(body),
      );
      final set = RegExp(
        r'tvl_session=([^;]+)',
      ).firstMatch(res.headers['set-cookie'] ?? '');
      if (set != null) cookie = set[1];
      final json = res.body.isEmpty ? null : jsonDecode(res.body);
      if (json is Map && json['csrfToken'] is String) {
        csrf = json['csrfToken'] as String;
      }
      final r = Res(res.statusCode, json);
      // 429: rate limit, or MFA_EMAIL_THROTTLED (another run e-mailed a code < 45 s ago).
      if (res.statusCode == 429 && attempt < 4) {
        await Future<void>.delayed(
          Duration(seconds: r.error == 'MFA_EMAIL_THROTTLED' ? 46 : 10),
        );
        continue;
      }
      return r;
    }
  }

  Future<void> mfa(String purpose) async {
    final since = DateTime.now().millisecondsSinceEpoch - 2000;
    final sent = await authPost('/auth/mfa/email/send', {'purpose': purpose});
    expect(sent.status, 200, reason: '$email mfa send → $sent');
    final code = await waitForMailCode(email, since);
    final v = await authPost('/auth/mfa/email/verify', {
      'code': code,
      if (purpose == 'ENROLL') 'purpose': purpose,
    });
    expect(v.status, 200, reason: '$email mfa verify → $v');
  }

  final login = await authPost('/auth/login', {
    'email': email,
    'password': devPassword,
  });
  expect(login.status, 200, reason: '$email login → $login');
  if (login.map['status'] == 'MFA_REQUIRED') await mfa('LOGIN');
  var dt = await authPost('/auth/device-token', {'deviceName': 'qa-business'});
  if (dt.status == 403 && dt.error == 'MFA_REQUIRED') {
    await mfa('ENROLL');
    dt = await authPost('/auth/device-token', {'deviceName': 'qa-business'});
  }
  expect(dt.status, 201, reason: '$email device-token → $dt');
  return QaUser(email, dt.map['token'] as String, businessId: businessId);
}

/// Newest dev e-mail to [to] written after [sinceMs] whose subject starts
/// with a 6-digit code (docs/API-MOBILE.md §3).
Future<String> waitForMailCode(
  String to,
  int sinceMs, {
  int seconds = 20,
}) async {
  for (var i = 0; i < seconds * 2; i++) {
    final m = newestMail(to, sinceMs, (s) => RegExp(r'^\d{6}').hasMatch(s));
    if (m != null) return '${m['subject']}'.substring(0, 6);
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw TestFailure('no MFA e-mail for $to in $mailDir');
}

/// Newest dev mail JSON to [to] (any recipient when null) after [sinceMs]
/// whose subject matches [subject].
Map<String, dynamic>? newestMail(
  String? to,
  int sinceMs,
  bool Function(String subject) subject,
) {
  final dir = Directory(mailDir);
  if (!dir.existsSync()) return null;
  final files = dir.listSync().whereType<File>().where((f) {
    final m = RegExp(r'file-(\d+)-\d+\.json$').firstMatch(f.path);
    return m != null && int.parse(m[1]!) >= sinceMs;
  }).toList()..sort((a, b) => b.path.compareTo(a.path));
  for (final f in files) {
    final mail = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final rcpt = '${mail['to']}';
    if ((to == null || rcpt.contains(to)) && subject('${mail['subject']}')) {
      return mail;
    }
  }
  return null;
}

/// Find-or-create a password member of the studio (owner's API), with [role].
Future<String> ensureMember(
  QaUser owner,
  String email,
  String name,
  String role,
) async {
  final team = await owner.ok('/business/members');
  for (final m in (team['members'] as List).cast<Map<String, dynamic>>()) {
    if (m['email'] == email && m['revokedAt'] == null) {
      if (m['role'] != role) {
        final r = await owner.put('/business/members/${m['userId']}/role', {
          'role': role,
        });
        expect(r.status, 200, reason: 'reset role of $email → $r');
      }
      return m['userId'] as String;
    }
  }
  final r = await owner.post('/business/members/create', {
    'email': email,
    'displayName': name,
    'role': role,
    'password': devPassword,
  });
  expect(r.status, 201, reason: 'create $email → $r');
  return r.map['userId'] as String;
}

String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

BigInt minor(Object? v) => v == null ? BigInt.zero : BigInt.parse('$v');

// ---------------------------------------------------------------- app side

/// Wait (real time) until [f] finds something.
Future<void> waitFor(WidgetTester tester, Finder f, {int seconds = 30}) =>
    waitUntil(tester, () => f.evaluate().isNotEmpty, '$f', seconds: seconds);

Future<void> waitUntil(
  WidgetTester tester,
  bool Function() ok,
  String what, {
  int seconds = 30,
}) async {
  for (var i = 0; i < seconds * 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    if (ok()) return;
  }
  throw TestFailure('timed out waiting for $what');
}

Future<void> pumpFor(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Counts taps of a journey (SPEC-v2 §1 F3.1).
class TapCounter {
  int taps = 0;

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f.first);
    await tester.pump(const Duration(milliseconds: 200));
    await uncover(tester, f.first);
    await tester.tap(f.first);
    taps++;
    await pumpFor(tester, const Duration(milliseconds: 900));
  }
}

/// Cold-start the app signed in as [u] in [businessId] (Keychain primed the
/// way `session.completeSignIn` leaves it), then wait for the tab shell.
Future<void> launchAs(
  WidgetTester tester,
  QaUser u, {
  String? businessId,
}) async {
  await AppCache.isFirstLaunch(); // consume the install marker so restore keeps our token
  // AT-46: like a real device between two members — a local sign-out wipes the
  // previous user's cache (account, /me), so the cold start cannot open from
  // it. The server token of the previous user is not revoked.
  await session.signOutLocally();
  await keychain.write(key: 'device_token', value: u.token);
  await keychain.write(key: 'business_id', value: businessId ?? u.businessId);
  ApiClient.instance.clearCredentials();
  session
    ..status = SessionStatus.unknown
    ..expired = false;
  app.main();
  await waitFor(tester, find.byType(AppShell), seconds: 45);
  await waitUntil(
    tester,
    () =>
        session.business?.businessId == (businessId ?? u.businessId) &&
        session.account?.email == u.email &&
        session.freshMe != null,
    '${u.email} signed in to ${businessId ?? u.businessId} with a fresh /me',
  );
  await pumpFor(tester, const Duration(seconds: 3)); // cache → network
}

Finder byKeyPrefix(String prefix) => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith(prefix),
);

/// Keys (with [prefix]) of the on-stage widgets, top to bottom.
List<String> keysTopDown(WidgetTester tester, String prefix) {
  final els = byKeyPrefix(prefix).evaluate().toList()
    ..sort(
      (a, b) => tester
          .getTopLeft(find.byWidget(a.widget))
          .dy
          .compareTo(tester.getTopLeft(find.byWidget(b.widget)).dy),
    );
  return [for (final e in els) (e.widget.key! as ValueKey<String>).value];
}

/// AT-96 (2026-11-12 product decision): subscription words are allowed only
/// on the billing surfaces – the "המסלול של העסק" business row, the profile
/// plan row and the plans / checkout screens (sold via Apple IAP).
final List<Finder> billingSurfaces = [
  find.byKey(const Key('brow-subscription')),
  find.byKey(const Key('profile-plan-cta')),
  find.byType(PlansSheet),
  find.byType(RequiredSubscriptionScreen),
  find.byType(BillingCheckoutScreen),
];

bool _onBillingSurface(Element e) {
  for (final s in billingSurfaces) {
    final hosts = s.evaluate();
    if (hosts.isEmpty) continue;
    var inside = false;
    e.visitAncestorElements((a) {
      inside = hosts.contains(a);
      return !inside;
    });
    if (inside || hosts.contains(e)) return true;
  }
  return false;
}

/// AT-90 + AT-49 + AT-96 on whatever is on stage now: ≤1 PrimaryButton, none
/// disabled while online, no "אין הרשאה", no subscription words.
/// [scope] limits the PrimaryButton count to one sheet (the page under a modal
/// sheet keeps its own primary on stage; AT-90 counts per screen/sheet).
void expectScreenRules(String where, {Finder? scope}) {
  final pf = scope == null
      ? find.byType(PrimaryButton)
      : find.descendant(of: scope, matching: find.byType(PrimaryButton));
  final primaries = pf
      .evaluate()
      .map((e) => e.widget as PrimaryButton)
      .toList();
  expect(
    primaries.length,
    lessThanOrEqualTo(1),
    reason: 'AT-90 $where: ${primaries.length} PrimaryButtons',
  );
  if (!session.offline) {
    expect(
      primaries.where((p) => p.offline),
      isEmpty,
      reason: 'AT-49 $where: disabled primary while online',
    );
  }
  expect(
    find.textContaining('אין הרשאה'),
    findsNothing,
    reason: 'AT-49 $where',
  );
  for (final w in const ['מנוי', 'מסלול', 'שדרג']) {
    final hits = find
        .textContaining(w)
        .evaluate()
        .where((e) => !_onBillingSurface(e));
    expect(hits, isEmpty, reason: 'AT-96 $where: "$w"');
  }
}

/// True once [finder] is built, scrolling the screen's main lazy list down
/// step by step (rows below the fold of a ListView are not built).
Future<bool> scrollToFind(
  WidgetTester tester,
  Finder finder, {
  int steps = 8,
}) async {
  for (var i = 0; i <= steps; i++) {
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder.first);
      await tester.pump(const Duration(milliseconds: 200));
      return true;
    }
    final lists = find.byType(Scrollable);
    if (lists.evaluate().isEmpty) return false;
    await tester.drag(lists.first, const Offset(0, -300), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
  }
  return finder.evaluate().isNotEmpty;
}

/// The main vertical list on screen (B is lazy: rows below the fold are not
/// built until scrolled to).
Finder _mainList() => find
    .byWidgetPredicate(
      (w) =>
          w is Scrollable &&
          axisDirectionToAxis(w.axisDirection) == Axis.vertical,
    )
    .hitTestable();

/// Scrolls the main list until [f] is built, then into view.
Future<void> scrollUntilBuilt(
  WidgetTester tester,
  Finder f, {
  int steps = 30,
}) async {
  var down = true;
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 150));
    if (f.evaluate().isNotEmpty) {
      await tester.ensureVisible(f.first);
      await tester.pump(const Duration(milliseconds: 200));
      return;
    }
    final lists = _mainList();
    if (lists.evaluate().isEmpty) continue;
    final pos = tester.state<ScrollableState>(lists.last).position;
    if (down && pos.pixels >= pos.maxScrollExtent) down = false;
    if (!down && pos.pixels <= pos.minScrollExtent) down = true;
    await tester.drag(
      lists.last,
      Offset(0, down ? -300 : 300),
      warnIfMissed: false,
    );
  }
  throw TestFailure('never built: $f');
}

/// The rows of B's "עוד הגדרות" page (PM 2026-11-12, §6.B ≤ 10): opens it
/// from B, collects its `brow-` keys and goes back. Empty without the row.
Future<Set<String>> moreSettingsRowKeys(WidgetTester tester) async {
  final more = find.byKey(const Key('brow-more'));
  await scrollUntilBuilt(tester, more);
  await tester.ensureVisible(more);
  await tester.pump();
  await tester.tap(more);
  await waitFor(tester, find.text(BusinessHe.moreSettings));
  await pumpFor(tester, const Duration(milliseconds: 600));
  final out = {
    for (final e in byKeyPrefix('brow-').evaluate())
      (e.widget.key! as ValueKey<String>).value.substring(5),
  }..remove('more');
  navigatorKey.currentState!.pop();
  await pumpFor(tester, const Duration(milliseconds: 600));
  return out;
}

/// Every `brow-` row of B, scrolling the lazy list top to bottom.
Future<Set<String>> businessRowKeysScrolled(WidgetTester tester) async {
  final out = <String>{};
  void collect() {
    for (final e
        in find
            .byWidgetPredicate(
              (w) =>
                  w.key is ValueKey<String> &&
                  (w.key! as ValueKey<String>).value.startsWith('brow-'),
            )
            .evaluate()) {
      out.add((e.widget.key! as ValueKey<String>).value.substring(5));
    }
  }

  final lists = _mainList();
  if (lists.evaluate().isEmpty) {
    collect();
    return out;
  }
  final pos = tester.state<ScrollableState>(lists.last).position;
  pos.jumpTo(pos.minScrollExtent);
  await tester.pump(const Duration(milliseconds: 200));
  for (var i = 0; i < 30; i++) {
    collect();
    if (pos.pixels >= pos.maxScrollExtent) break;
    pos.jumpTo(
      (pos.pixels + 250).clamp(pos.minScrollExtent, pos.maxScrollExtent),
    );
    await tester.pump(const Duration(milliseconds: 150));
  }
  collect();
  pos.jumpTo(pos.minScrollExtent);
  await tester.pump(const Duration(milliseconds: 200));
  return out;
}
