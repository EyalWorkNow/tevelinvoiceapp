// QA (qa-perms) helpers for integration_test/v2_qa-perms_test.dart.
//
// * [QaApi]: an independent HTTP client per role preset (own cookie / CSRF /
//   device token), so one test can hold the owner AND the employee at the
//   same time without touching the app's ApiClient singleton.
// * [presets]: the dev role presets of docs/API-MOBILE.md "Role presets" with
//   the SPEC-v2 §4.4 hidden-not-disabled expectations for each one.
// * UI helpers: put the real app session on a preset's device token, pump
//   the shell, collect a textual "golden" of what the preset sees, and the
//   AT-49 check (no disabled button, no "אין הרשאה" while online).
//
// Dev only: talks to the local dev API (default http://127.0.0.1:3031) and
// reads the dev e-mail folder for MFA codes. Never point it at prod.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:invoice/api/client.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/app_shell.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/session.dart';
import 'package:invoice/ui/widgets/primary_button.dart';

/// Same base the app uses (dart-define API_BASE; dev default :3031).
String get qaApiBase => ApiClient.baseUrl;

/// Dev outgoing e-mail folder (MFA codes). The simulator reads the host FS.
const String qaMailDir = String.fromEnvironment(
  'MAILDIR',
  defaultValue:
      '/Users/eyalatiya/invoiceproject-mobile-dev-storage/outgoing-emails',
);

const String qaPassword = 'Mobile12345678';
const String murshe = '3b773037-e71d-49bd-a951-76845e4abe07';
const String patur = 'c934a7a8-df74-433d-a5e2-e342c16142b1';

/// One HTTP answer, never thrown: tests assert on status + error code.
class QaResponse {
  QaResponse(this.status, this.json);

  final int status;
  final Map<String, dynamic> json;

  String? get error => json['error'] as String?;

  @override
  String toString() => 'QaResponse($status ${jsonEncode(json)})';
}

/// A signed-in preset: device token + business, plain HTTP.
class QaApi {
  QaApi._(this.email, this.businessId);

  final String email;
  final String businessId;
  String? _cookie;
  String? _csrf;
  String? token;
  final http.Client _http = http.Client();

  /// Password → (e-mail MFA code from the dev mail folder) → device token.
  static Future<QaApi> signIn(String email, String businessId) async {
    final api = QaApi._(email, businessId);
    final login = await api.send(
      'POST',
      '/auth/login',
      body: {'email': email, 'password': qaPassword},
    );
    if (login.status != 200) throw StateError('login $email → $login');
    Future<void> mfa(String purpose) async {
      final since = DateTime.now().subtract(const Duration(seconds: 2));
      final sent = await api.send(
        'POST',
        '/auth/mfa/email/send',
        body: {'purpose': purpose},
      );
      if (sent.status >= 300) throw StateError('mfa send $email → $sent');
      String? code;
      for (var i = 0; i < 40 && code == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        code = latestMfaCode(email, since);
      }
      if (code == null)
        throw StateError('no MFA e-mail for $email in $qaMailDir');
      final ok = await api.send(
        'POST',
        '/auth/mfa/email/verify',
        body: {'code': code, if (purpose == 'ENROLL') 'purpose': purpose},
      );
      if (ok.status != 200) throw StateError('mfa verify $email → $ok');
    }

    if (login.json['mfaRequired'] == true ||
        login.json['status'] == 'MFA_REQUIRED')
      await mfa('LOGIN');
    var dt = await api.send(
      'POST',
      '/auth/device-token',
      body: {'deviceName': 'qa-perms'},
    );
    if (dt.status == 403 && dt.error == 'MFA_REQUIRED') {
      // Privileged role without an enrolled method (P0 accountant moved to
      // ACCOUNTANT_REP by the owner's B·צוות visit): enrol e-mail first.
      await mfa('ENROLL');
      dt = await api.send(
        'POST',
        '/auth/device-token',
        body: {'deviceName': 'qa-perms'},
      );
    }
    final t = dt.json['token'];
    if (dt.status != 201 && dt.status != 200 || t is! String) {
      throw StateError('device-token $email → $dt');
    }
    api
      ..token = t
      .._cookie = null
      .._csrf = null;
    return api;
  }

  Future<QaResponse> get(String path) => send('GET', path);
  Future<QaResponse> post(
    String path, [
    Object? body,
    bool idempotent = false,
  ]) => send(
    'POST',
    path,
    body: body ?? const {},
    idempotencyKey: idempotent ? ApiClient.newIdempotencyKey() : null,
  );
  Future<QaResponse> put(String path, Object? body) =>
      send('PUT', path, body: body ?? const {});
  Future<QaResponse> patch(String path, Object? body) =>
      send('PATCH', path, body: body ?? const {});
  Future<QaResponse> delete(String path) => send('DELETE', path);

  Future<QaResponse> send(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
  }) async {
    final req = http.Request(method, Uri.parse('$qaApiBase$path'));
    final h = req.headers..['Accept'] = 'application/json';
    if (token != null) {
      h['Authorization'] = 'Bearer $token';
    } else {
      if (_cookie != null) h['Cookie'] = 'tvl_session=$_cookie';
      if (method != 'GET' && _csrf != null) h['X-CSRF-Token'] = _csrf!;
    }
    if (sendsBusinessHeader(path)) h['X-Business-Id'] = businessId;
    if (idempotencyKey != null) h['Idempotency-Key'] = idempotencyKey;
    if (body != null) {
      h['Content-Type'] = 'application/json';
      req.bodyBytes = utf8.encode(jsonEncode(body));
    }
    final res = await http.Response.fromStream(
      await _http.send(req).timeout(const Duration(seconds: 30)),
    );
    final setCookie = res.headers['set-cookie'];
    if (setCookie != null) {
      final m = RegExp(
        r'(?:^|[,\s])tvl_session=([^;,]*)',
      ).firstMatch(setCookie);
      if (m != null) _cookie = m.group(1)!.isEmpty ? null : m.group(1);
    }
    Map<String, dynamic> json = const {};
    final ct = res.headers['content-type'] ?? '';
    if (res.bodyBytes.isNotEmpty && ct.contains('json')) {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) json = decoded;
    }
    final csrf = json['csrfToken'];
    if (csrf is String && csrf.isNotEmpty) _csrf = csrf;
    return QaResponse(res.statusCode, json);
  }

  /// Revoke the dev device token (best effort).
  Future<void> logout() async {
    if (token == null) return;
    try {
      await send('POST', '/mobile/logout');
    } on Object {
      // already revoked / server gone
    }
    token = null;
    _http.close();
  }
}

/// Newest 6-digit login code e-mailed to [to] after [since].
String? latestMfaCode(String to, DateTime since) {
  final dir = Directory(qaMailDir);
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
      if (m['to'] == to && RegExp(r'^\d{6}').hasMatch(subject))
        return subject.substring(0, 6);
    } on Object {
      // a file still being written
    }
  }
  return null;
}

// ---- presets + SPEC-v2 §4.4 expectations ------------------------------------

/// One dev role preset and what §4.4 says it sees. Business rows use the B
/// row keys of lib/screens/business/business_screen.dart (`brow-<key>`).
class PresetSpec {
  const PresetSpec({
    required this.key,
    required this.email,
    required this.preset,
    required this.label,
    this.businessId = murshe,
    required this.createTab,
    required this.homeIsReports,
    required this.moneyCard,
    required this.intents,
    required this.businessRows,
    required this.cancelCredit,
    required this.approve,
    required this.recordPayment,
    required this.shareOnly,
    required this.composerSubmits,
    required this.permissions,
    this.s1Tiles = const {},
  });

  final String key;
  final String email;
  final Preset preset;

  /// Column name of §4.4.
  final String label;
  final String businessId;

  /// ＋ in the tab bar.
  final bool createTab;

  /// Home tab = R (reports) instead of H.
  final bool homeIsReports;

  /// "מגיע לך" money card on H (n/a when [homeIsReports]).
  final bool moneyCard;

  /// "בקש תשלום" on H.
  final bool intents;

  /// "קיבלתי תשלום" on H (§19 q7: hidden without document:finalize).
  bool get paidIntent => intents && recordPayment;

  /// Exactly the rows of B.
  final Set<String> businessRows;

  /// D ⋯ "בטל / זכה" on an open 305 of someone else.
  final bool cancelCredit;

  /// D "אשר והפק" + ⋯ "דחה" on another member's PENDING_APPROVAL document.
  final bool approve;

  /// "קיבלתי תשלום" anywhere on D of an open 305.
  final bool recordPayment;

  /// D primary is "שתף" (local PDF) on an issued 305.
  final bool shareOnly;

  /// Composer primary = "שלח לאישור" (policy NONE in the dev business).
  final bool composerSubmits;

  /// The exact /me.permissions the server must return (docs/API-MOBILE.md).
  final Set<String> permissions;

  /// §4.4 "אריחי ＋" (S1 tile keys without the `s1-` prefix).
  final Set<String> s1Tiles;

  bool get mfa => !{'staff', 'accountant', 'viewer'}.contains(key);
}

const Set<String> _ownerPerms = {
  'document:read',
  'document:draft:write',
  'document:finalize',
  'document:send',
  'payment:record',
  'expense:record',
  'expense:approve',
  'business:configure',
  'membership:manage',
  'document:cancel',
  'approval:decide',
  'money:read',
  'report:read',
  'export:run',
  'customer:manage',
  'supplier:manage',
  'item:manage',
  'payment:refund',
  'allocation:request',
};

const List<PresetSpec> presets = [
  PresetSpec(
    key: 'owner',
    email: 'mobile-owner@tevel.test',
    preset: Preset.owner,
    label: 'בעלים',
    createTab: true,
    homeIsReports: false,
    moneyCard: true,
    intents: true,
    businessRows: {
      'reports',
      'expenses',
      'team',
      'profile',
      'branding',
      'approvals',
      'reminders',
      'shaam',
      'account',
      'desktop',
    },
    cancelCredit: true,
    approve: true,
    recordPayment: true,
    shareOnly: false,
    composerSubmits: false,
    s1Tiles: {'quote', 'expense', 'customer', 'more'},
    permissions: _ownerPerms,
  ),
  PresetSpec(
    key: 'partner',
    email: 'mobile-partner@tevel.test',
    preset: Preset.partner,
    label: 'שותף',
    createTab: true,
    homeIsReports: false,
    moneyCard: true,
    intents: true,
    businessRows: {
      'reports',
      'expenses',
      'team',
      'profile',
      'branding',
      'approvals',
      'reminders',
      'shaam',
      'account',
      'desktop',
    },
    cancelCredit: true,
    approve: true,
    recordPayment: true,
    shareOnly: false,
    composerSubmits: false,
    s1Tiles: {'quote', 'expense', 'customer', 'more'},
    permissions: _ownerPerms,
  ),
  PresetSpec(
    key: 'staff',
    email: 'mobile-staff@tevel.test',
    preset: Preset.employee,
    label: 'עובד',
    createTab: true,
    homeIsReports: false,
    moneyCard: false,
    intents: true,
    businessRows: {'expenses', 'account'},
    cancelCredit: false,
    approve: false,
    recordPayment: false,
    shareOnly: false,
    composerSubmits: true,
    s1Tiles: {'quote', 'expense', 'customer'},
    permissions: {
      'document:read',
      'document:draft:write',
      'document:send',
      'expense:record',
    },
  ),
  PresetSpec(
    key: 'employee',
    email: 'mobile-employee@tevel.test',
    preset: Preset.employeeIssuer,
    label: 'עובד + מפיק בעצמו',
    createTab: true,
    homeIsReports: false,
    moneyCard: false,
    intents: true,
    businessRows: {'expenses', 'account'},
    cancelCredit: false,
    approve: false,
    recordPayment: true,
    shareOnly: false,
    composerSubmits: false,
    s1Tiles: {'quote', 'expense', 'customer'},
    permissions: {
      'document:read',
      'document:draft:write',
      'document:finalize',
      'document:send',
      'payment:record',
      'expense:record',
      'allocation:request',
    },
  ),
  PresetSpec(
    key: 'accountant',
    email: 'mobile-accountant@tevel.test',
    preset: Preset.accountantRep,
    label: 'רו״ח (P0)',
    createTab: false,
    homeIsReports: true,
    moneyCard: false,
    intents: false,
    // P0 preset has no report:read on a read-gated server → no shaam/desktop rows.
    businessRows: {'expenses', 'account'},
    cancelCredit: false,
    approve: false,
    recordPayment: false,
    shareOnly: true,
    composerSubmits: false,
    permissions: {
      'document:read',
      'expense:record',
      'expense:approve',
      'money:read',
    },
  ),
  PresetSpec(
    key: 'cpaRep',
    email: 'mobile-cpa-rep@tevel.test',
    preset: Preset.accountantRep,
    label: 'רו״ח (מייצג)',
    createTab: false,
    homeIsReports: true,
    moneyCard: false,
    intents: false,
    businessRows: {'expenses', 'shaam', 'numbering', 'account', 'desktop'},
    cancelCredit: false,
    approve: false,
    recordPayment: false,
    shareOnly: true,
    composerSubmits: false,
    permissions: {
      'document:read',
      'expense:record',
      'expense:approve',
      'money:read',
      'report:read',
      'export:run',
      'allocation:request',
      'settings:numbering',
      'customer:accountKey',
    },
  ),
  PresetSpec(
    key: 'cpaFull',
    email: 'mobile-cpa-full@tevel.test',
    preset: Preset.accountantFull,
    label: 'רו״ח – מלא',
    createTab: true,
    homeIsReports: true,
    moneyCard: false,
    intents: false,
    businessRows: {'expenses', 'shaam', 'account', 'desktop'},
    cancelCredit: true,
    approve: true,
    recordPayment: true,
    shareOnly: false,
    composerSubmits: false,
    s1Tiles: {'quote', 'expense', 'customer', 'more'},
    permissions: {
      'document:read',
      'document:draft:write',
      'document:finalize',
      'document:send',
      'payment:record',
      'expense:record',
      'expense:approve',
      'document:cancel',
      'approval:decide',
      'money:read',
      'report:read',
      'export:run',
      'customer:manage',
      'supplier:manage',
      'item:manage',
      'allocation:request',
    },
  ),
  PresetSpec(
    key: 'viewer',
    email: 'mobile-viewer@tevel.test',
    preset: Preset.viewer,
    label: 'צפייה',
    createTab: false,
    homeIsReports: false,
    moneyCard: true,
    intents: false,
    businessRows: {'account'},
    cancelCredit: false,
    approve: false,
    recordPayment: false,
    shareOnly: true,
    composerSubmits: false,
    permissions: {'document:read', 'money:read'},
  ),
  PresetSpec(
    key: 'patur',
    email: 'mobile-patur@tevel.test',
    preset: Preset.owner,
    label: 'בעלים × פטור',
    businessId: patur,
    createTab: true,
    homeIsReports: false,
    moneyCard: true,
    intents: true,
    // Sole member → no approvals row (§13.6).
    businessRows: {
      'reports',
      'expenses',
      'team',
      'profile',
      'branding',
      'reminders',
      'shaam',
      'account',
      'desktop',
    },
    cancelCredit: true,
    approve: true,
    recordPayment: true,
    shareOnly: false,
    composerSubmits: false,
    s1Tiles: {'quote', 'expense', 'customer', 'more'},
    permissions: _ownerPerms,
  ),
];

PresetSpec presetSpec(String key) => presets.firstWhere((p) => p.key == key);

/// Device tokens, one sign-in per preset per run (MFA mail is slow).
final Map<String, QaApi> _signedIn = {};

Future<QaApi> qaApi(String key) async {
  final existing = _signedIn[key];
  if (existing != null) return existing;
  final spec = presetSpec(key);
  final api = await QaApi.signIn(spec.email, spec.businessId);
  return _signedIn[key] = api;
}

/// The owner's B·צוות visit moves P0 accountants (READ_ONLY + expense
/// grants) to ACCOUNTANT_REP (area E, §12.1). Other suites visit B·צוות, so
/// put the dev P0 accountant back into the seeded P0 shape before the matrix.
Future<void> restoreP0Accountant() async {
  final owner = await qaApi('owner');
  final team = await owner.get('/business/members');
  for (final m in (team.json['members'] as List? ?? const [])) {
    final row = m as Map<String, dynamic>;
    if (row['email'] != presetSpec('accountant').email ||
        row['revokedAt'] != null)
      continue;
    final uid = row['userId'];
    final r1 = await owner.put('/business/members/$uid/role', {
      'role': 'READ_ONLY',
    });
    final r2 = await owner.put('/business/members/$uid/permissions', {
      'permissions': ['expense:record', 'expense:approve'],
    });
    if (r1.status != 200 || r2.status != 200)
      throw StateError('restore P0 accountant → $r1 / $r2');
  }
}

Future<void> qaLogoutAll() async {
  for (final api in _signedIn.values) {
    await api.logout();
  }
  _signedIn.clear();
}

// ---- the real app on a preset ----------------------------------------------

/// Puts the app's session + ApiClient on [key]'s device token (no Keychain,
/// no splash) and loads /me + /business/profile from the dev server.
Future<void> enterAppAs(String key) async {
  final api = await qaApi(key);
  leaveApp();
  final client = ApiClient.instance
    ..deviceToken = api.token
    ..businessId = api.businessId;
  final account = MobileAccount.fromJson(await client.get('/mobile/session'));
  session
    ..account = account
    ..business = account.businesses.firstWhere(
      (b) => b.businessId == api.businessId,
    )
    ..offline = false
    ..expired = false
    ..status = SessionStatus.signedIn;
  await session.refreshBusiness();
}

/// Back to a signed-out app (does NOT revoke the preset's token).
void leaveApp() {
  ApiClient.instance.clearCredentials();
  session
    ..status = SessionStatus.signedOut
    ..account = null
    ..business = null
    ..me = null
    ..profile = null
    ..meFetchedAt = null
    ..offline = false
    ..expired = false;
  currentTab.value = AppTab.home;
}

/// Real-time pumping (network answers arrive between frames).
Future<void> pumpFor(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps until [finder] matches (or [timeout]); returns whether it did.
Future<bool> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return true;
  }
  return false;
}

/// AT-49 / F5: online, nothing is disabled and nothing says "no permission".
void expectHiddenNotDisabled(WidgetTester tester, String where) {
  final disabled = <String>[];
  for (final e
      in find
          .byWidgetPredicate(
            (w) => w is ButtonStyleButton && w.onPressed == null,
          )
          .evaluate()) {
    disabled.add('${e.widget.runtimeType}${e.widget.key ?? ''}');
  }
  // Exact type: BackButton / CloseButton extend IconButton with a null
  // `onPressed` field and pop in their own build (enabled).
  for (final e
      in find
          .byWidgetPredicate(
            (w) =>
                w.runtimeType == IconButton &&
                (w as IconButton).onPressed == null,
          )
          .evaluate()) {
    final b = e.widget as IconButton;
    disabled.add('IconButton(${b.tooltip ?? ''})${b.key ?? ''}');
  }
  for (final e
      in find
          .byWidgetPredicate((w) => w is PrimaryButton && w.offline)
          .evaluate()) {
    disabled.add('PrimaryButton(offline)${e.widget.key ?? ''}');
  }
  expect(disabled, isEmpty, reason: '$where: disabled controls while online');
  expect(
    find.textContaining('אין הרשאה'),
    findsNothing,
    reason: '$where: "אין הרשאה" shown',
  );
  expect(
    find.textContaining('אין לך הרשאה'),
    findsNothing,
    reason: '$where: "אין לך הרשאה" shown',
  );
}

/// Keys of every widget whose key starts with [prefix] (string keys only).
Set<String> keysWithPrefix(String prefix) => {
  for (final e
      in find
          .byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith(prefix),
          )
          .evaluate())
    (e.widget.key! as ValueKey<String>).value.substring(prefix.length),
};

/// [keysWithPrefix] over the whole lazily built list inside [scope]: scrolls
/// down until no new key appears, then back to the top.
Future<Set<String>> keysWithPrefixScrolling(
  WidgetTester tester,
  Finder scope,
  String prefix,
) async {
  final seen = <String>{...keysWithPrefix(prefix)};
  final scrollable = find
      .descendant(of: scope, matching: find.byType(Scrollable))
      .first;
  for (var i = 0, still = 0; i < 20 && still < 2; i++) {
    await tester.drag(scrollable, const Offset(0, -300), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    final before = seen.length;
    seen.addAll(keysWithPrefix(prefix));
    still = seen.length == before ? still + 1 : 0;
  }
  await tester.drag(scrollable, const Offset(0, 3000), warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 300));
  return seen;
}

/// Labels of the PrimaryButtons on screen.
List<String> primaryLabels() => [
  for (final e in find.byType(PrimaryButton).evaluate())
    (e.widget as PrimaryButton).label,
];

/// Text of every row in an open "⋯" sheet (MoreMenu rows are Semantics labels).
Set<String> openMenuLabels(WidgetTester tester, Iterable<String> candidates) =>
    {
      for (final c in candidates)
        if (find
            .descendant(of: find.byType(BottomSheet), matching: find.text(c))
            .evaluate()
            .isNotEmpty)
          c,
    };

/// A finalized 305 with an open balance, created by the member [email]
/// (listed through [owner], who sees every amount). Null when none exists.
Future<String?> findOpenTaxInvoiceBy(QaApi owner, String email) async {
  final team = await owner.get('/business/members');
  final userId =
      ((team.json['members'] as List? ?? const []).cast<Map<String, dynamic>>())
          .where((m) => m['email'] == email)
          .firstOrNull?['userId'];
  if (userId == null) return null;
  final res = await owner.get('/documents?limit=500');
  final docs = (res.json['documents'] as List? ?? const [])
      .cast<Map<String, dynamic>>();
  for (final d in docs) {
    final open = BigInt.tryParse('${d['openMinor']}') ?? BigInt.zero;
    if (d['documentType'] == 'TAX_INVOICE' &&
        const {'FINALIZED', 'ARCHIVED', 'SENT'}.contains(d['status']) &&
        d['createdBy'] == userId &&
        d['voidedAt'] == null &&
        open > BigInt.zero) {
      return d['id'] as String;
    }
  }
  return null;
}

/// First document of [type] in an issued status (any creator).
Future<Map<String, dynamic>?> findIssued(QaApi api, String type) async {
  final res = await api.get('/documents?limit=500');
  for (final d
      in (res.json['documents'] as List? ?? const [])
          .cast<Map<String, dynamic>>()) {
    if (d['documentType'] == type &&
        const {'FINALIZED', 'ARCHIVED', 'SENT'}.contains(d['status']))
      return d;
  }
  return null;
}

/// Lines of [docId] in the create/credit body shape.
Future<List<Map<String, dynamic>>> creditLinesOf(
  QaApi api,
  String docId,
) async {
  final res = await api.get('/documents/$docId');
  return [
    for (final l
        in (res.json['lines'] as List? ?? const [])
            .cast<Map<String, dynamic>>())
      {
        'description': l['description'],
        'quantityMicros': '${l['quantity_micros']}',
        'unitPriceMinor': '${l['unit_price_minor']}',
        'taxRateBasisPoints': l['tax_rate_basis_points'],
      },
  ];
}

/// A small 305 draft body for [customerId] (₪100 + 18% VAT).
Map<String, dynamic> draftBody(String customerId, {String? issueDate}) => {
  'documentType': 'TAX_INVOICE',
  'customerId': customerId,
  'currency': 'ILS',
  'fiscalContext': 'default',
  'issueDate': ?issueDate,
  'lines': [
    {
      'description': 'QA הרשאות',
      'quantityMicros': '1000000',
      'unitPriceMinor': '10000',
      'taxRateBasisPoints': 1800,
    },
  ],
};

/// Israel calendar date [days] from today, YYYY-MM-DD (device clock).
String qaDay(int days) {
  final d = DateTime.now().add(Duration(days: days));
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
