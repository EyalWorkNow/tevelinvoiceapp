// QA (qa-people) helpers for integration_test/v2_qa-people_test.dart.
//
// * DevApi: a second, independent HTTP client that signs in through the real
//   auth flow (cookie → e-mail MFA from the dev mail folder → device token)
//   and sets up / verifies state on the dev API. The app gets the SAME device
//   token through the Keychain, so UI and API act as one member.
// * launchAppAs: cold-starts the real app (splash → restore → AppShell) as a
//   given member, without typing the login form (covered by the login smoke).
// * TapCounter (SPEC-v2 §1 F3.1), camera mock (image_picker_ios pigeon
//   channel), OCR fixture (AT-19: "OCR מצליח (fixture)"), unique JPEGs.
//
// Dev only: never point API_BASE at prod.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:invoice/api/customers_api.dart' show resetStatementProbe;
import 'package:invoice/app_shell.dart';
import 'package:invoice/main.dart' show TevelApp;
import 'package:invoice/router.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/session.dart';
import 'package:path_provider/path_provider.dart';
import 'qa_plans_guard.dart';

const apiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://127.0.0.1:3031',
);

/// Host folder the dev server writes e-mails to (EMAIL_MODE=file). The
/// simulator app can read the host file system.
const mailDir = String.fromEnvironment('MAILDIR');
const devPassword = 'Mobile12345678';

/// "סטודיו תבל לדוגמה" (OSEK_MURSHE) — docs/API-MOBILE.md "Role presets".
const devBusinessId = '3b773037-e71d-49bd-a951-76845e4abe07';

const ownerEmail = 'mobile-owner@tevel.test';
const staffEmail = 'mobile-staff@tevel.test';
const employeeEmail = 'mobile-employee@tevel.test';
const viewerEmail = 'mobile-viewer@tevel.test';

/// Unique per run, so data from earlier runs never matches.
final String runTag = DateTime.now().millisecondsSinceEpoch.toString();

String todayIso() {
  final n = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${n.year}-${two(n.month)}-${two(n.day)}';
}

// ---- HTTP ---------------------------------------------------------------------

class ApiResult {
  ApiResult(this.status, this.bytes, this.contentType);

  final int status;
  final Uint8List bytes;
  final String contentType;

  dynamic get json => bytes.isEmpty ? null : jsonDecode(utf8.decode(bytes));
  Map<String, dynamic> get map =>
      json is Map<String, dynamic> ? json as Map<String, dynamic> : const {};
  String? get error => map['error'] as String?;
  List<Map<String, dynamic>> list(String key) => [
    for (final e in (map[key] as List? ?? const []))
      Map<String, dynamic>.from(e as Map),
  ];

  @override
  String toString() =>
      'HTTP $status ${contentType.startsWith('application/json') ? utf8.decode(bytes) : '<${bytes.length} bytes>'}';
}

/// One signed-in member on the dev API (bearer + X-Business-Id).
class DevApi {
  DevApi(this.email, this.token, {this.businessId = devBusinessId});

  final String email;
  final String token;
  final String businessId;
  final http.Client _http = http.Client();
  String? _userId;

  Future<ApiResult> send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Uint8List? bytes,
    String? contentType,
    String? idem,
  }) async {
    final uri = Uri.parse('$apiBase$path').replace(queryParameters: query);
    final req = http.Request(method, uri)
      ..headers['authorization'] = 'Bearer $token'
      ..headers['x-business-id'] = businessId;
    if (idem != null) req.headers['idempotency-key'] = idem;
    if (bytes != null) {
      req.headers['content-type'] = contentType ?? 'application/octet-stream';
      req.bodyBytes = bytes;
    } else if (method != 'GET' && method != 'DELETE' || body != null) {
      req.headers['content-type'] = 'application/json';
      req.body = jsonEncode(body ?? const {});
    }
    final res = await http.Response.fromStream(await _http.send(req));
    return ApiResult(
      res.statusCode,
      res.bodyBytes,
      res.headers['content-type'] ?? '',
    );
  }

  Future<ApiResult> get(String path, [Map<String, String>? query]) =>
      send('GET', path, query: query);
  Future<ApiResult> post(String path, [Object? body, String? idem]) =>
      send('POST', path, body: body, idem: idem);
  Future<ApiResult> patch(String path, Object body) =>
      send('PATCH', path, body: body);
  Future<ApiResult> delete(String path) => send('DELETE', path);

  /// [r] must have [status] (or any 2xx when null); otherwise the test fails with the body.
  static ApiResult expectOk(ApiResult r, [int? status]) {
    final ok = status == null
        ? r.status >= 200 && r.status < 300
        : r.status == status;
    if (!ok) fail('expected ${status ?? '2xx'}, got $r');
    return r;
  }

  Future<String> userId() async =>
      _userId ??= expectOk(await get('/me')).map['userId'] as String;

  Future<void> logout() async {
    try {
      await post('/mobile/logout');
    } on Object {
      // best effort
    }
    _http.close();
  }

  // ---- setup shortcuts ---------------------------------------------------------

  Future<String> createCustomer(
    String name, {
    String? email,
    String? phone,
    bool consent = false,
  }) async {
    final r = expectOk(
      await post('/customers', {
        'name': name,
        'customerType': 'INDIVIDUAL',
        'email': email,
        'phone': phone,
      }),
    );
    final id = r.map['id'] as String;
    if (consent)
      expectOk(
        await post('/customers/$id/consent', {'method': 'VERBAL_IN_APP'}),
      );
    return id;
  }

  /// Finalized 305 (TAX_INVOICE) of [netMinor] + 18% VAT, with its original PDF.
  Future<String> issueTaxInvoice(
    String customerId, {
    int netMinor = 10000,
  }) async {
    final draft = expectOk(
      await post('/documents', {
        'documentType': 'TAX_INVOICE',
        'customerId': customerId,
        'currency': 'ILS',
        'fiscalContext': 'default',
        'lines': [
          {
            'description': 'בדיקת QA $runTag',
            'quantityMicros': '1000000',
            'unitPriceMinor': '$netMinor',
            'taxRateBasisPoints': 1800,
          },
        ],
      }),
      201,
    );
    final id = draft.map['id'] as String;
    final fin = expectOk(
      await post('/documents/$id/finalize', {'scopeKey': 'default'}, newUuid()),
    );
    expect(fin.map['status'], 'FINALIZED', reason: '$fin');
    expectOk(await post('/documents/$id/artifact'));
    return id;
  }

  /// Upload [jpeg] like the app does (initiate → bytes → complete → poll).
  /// Returns the final upload JSON (`status`, `expenseId`).
  Future<Map<String, dynamic>> uploadExpense(
    Uint8List jpeg, {
    String contentType = 'image/jpeg',
  }) async {
    final init = expectOk(
      await post('/expenses/uploads/initiate', {
        'filename': 'qa-$runTag.jpg',
        'contentType': contentType,
        'sizeBytes': jpeg.length,
        'sha256': sha256.convert(jpeg).toString(),
      }),
    );
    final uploadId = init.map['uploadId'] as String;
    final target = init.map['upload'] as Map<String, dynamic>;
    expect(target['kind'], 'api', reason: 'dev stores uploads through the API');
    expectOk(
      await send(
        'PUT',
        target['url'] as String,
        bytes: jpeg,
        contentType: contentType,
      ),
    );
    var r = await post('/expenses/uploads/$uploadId/complete');
    var json = r.map;
    if (r.status >= 300)
      return {'status': 'REFUSED', 'error': r.error, 'uploadId': uploadId};
    final end = DateTime.now().add(const Duration(seconds: 30));
    while (json['status'] == 'SCAN_PENDING' && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(seconds: 1));
      json = expectOk(await get('/expenses/uploads/$uploadId')).map;
    }
    return {...json, 'uploadId': uploadId};
  }

  Future<String> firstExpenseCategoryId() async =>
      expectOk(await get('/expense-categories')).list('categories').first['id']
          as String;

  /// The "OCR read it" fixture: what a successful extraction would store.
  Future<void> applyOcrFixture(String expenseId, OcrValues v) async {
    // Runs inside the app's HTTP call while the test is pumping: flutter_test's
    // expect() would throw "Guarded function conflict" there, so plain checks.
    final r = await patch('/expenses/$expenseId/draft', v.draftJson());
    if (r.status != 200 || r.map['status'] != 'READY_TO_APPROVE') {
      throw StateError('OCR fixture PATCH draft → $r');
    }
  }

  /// GET /expenses?q= rows (BE-44); [status] e.g. DELETED.
  Future<Map<String, dynamic>?> findExpense(
    String id, {
    String? q,
    String? status,
  }) async {
    final r = expectOk(
      await get('/expenses', {'limit': '200', 'q': ?q, 'status': ?status}),
    );
    for (final e in r.list('expenses')) {
      if (e['id'] == id) return e;
    }
    return null;
  }
}

/// Values the OCR fixture "reads" (subtotal + VAT = total, like a real receipt).
class OcrValues {
  OcrValues({
    required this.supplierName,
    required this.categoryId,
    this.totalMinor = 23600,
    this.vatMinor = 3600,
  }) : documentNumber = 'QA-$runTag-${Random().nextInt(1 << 20)}';

  final String supplierName;
  final String categoryId;
  final int totalMinor;
  final int vatMinor;
  final String documentNumber;

  Map<String, dynamic> draftJson() {
    Map<String, String> money(int v) => {
      'amountMinor': '$v',
      'currency': 'ILS',
    };
    return {
      'supplierName': supplierName,
      'documentNumber': documentNumber,
      'documentDate': todayIso(),
      'subtotal': money(totalMinor - vatMinor),
      'vat': money(vatMinor),
      'total': money(totalMinor),
      'categoryId': categoryId,
    };
  }
}

String newUuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

// ---- sign-in (real auth flow) -----------------------------------------------

/// E-mails the dev server wrote to [to] after [since] (newest first).
List<Map<String, dynamic>> mailsTo(String to, DateTime since) {
  final dir = Directory(mailDir);
  if (mailDir.isEmpty || !dir.existsSync()) return const [];
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where(
            (f) =>
                f.path.endsWith('.json') &&
                !f.statSync().modified.isBefore(since),
          )
          .toList()
        ..sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
        );
  return [
    for (final f in files)
      if (jsonDecode(f.readAsStringSync()) case final Map<String, dynamic> m
          when m['to'] == to)
        m,
  ];
}

/// Signs [email] in like the app (login → e-mail MFA when asked → device token).
Future<DevApi> signInApi(String email) async {
  final c = http.Client();
  String? cookie;
  String? csrf;
  Future<ApiResult> post(String path, Object body) async {
    final r = await c.post(
      Uri.parse('$apiBase$path'),
      headers: {
        'content-type': 'application/json',
        'cookie': ?cookie,
        'x-csrf-token': ?csrf,
      },
      body: jsonEncode(body),
    );
    final setCookie = r.headers['set-cookie'];
    final m = setCookie == null
        ? null
        : RegExp(r'tvl_session=([^;,]+)').firstMatch(setCookie);
    if (m != null) cookie = 'tvl_session=${m[1]}';
    final res = ApiResult(
      r.statusCode,
      r.bodyBytes,
      r.headers['content-type'] ?? '',
    );
    final token = res.map['csrfToken'];
    if (token is String) csrf = token;
    return res;
  }

  try {
    final login = DevApi.expectOk(
      await post('/auth/login', {'email': email, 'password': devPassword}),
    );
    Future<void> mfa(String purpose) async {
      final since = DateTime.now().subtract(const Duration(seconds: 2));
      if (mailDir.isEmpty)
        fail(
          '$email needs MFA: run with --dart-define=MAILDIR=<dev outgoing-emails>',
        );
      var sent = await post('/auth/mfa/email/send', {'purpose': purpose});
      if (sent.error == 'MFA_EMAIL_THROTTLED') {
        await Future<void>.delayed(const Duration(seconds: 46));
        sent = await post('/auth/mfa/email/send', {'purpose': purpose});
      }
      DevApi.expectOk(sent);
      String? code;
      for (var i = 0; i < 40 && code == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        for (final mail in mailsTo(email, since)) {
          final subject = '${mail['subject']}';
          if (RegExp(r'^\d{6}').hasMatch(subject)) {
            code = subject.substring(0, 6);
            break;
          }
        }
      }
      if (code == null) fail('no MFA e-mail for $email in $mailDir');
      DevApi.expectOk(
        await post('/auth/mfa/email/verify', {
          'code': code,
          if (purpose == 'ENROLL') 'purpose': purpose,
        }),
      );
    }

    if (login.map['status'] == 'MFA_REQUIRED') await mfa('LOGIN');
    var dt = await post('/auth/device-token', {'deviceName': 'QA qa-people'});
    if (dt.error == 'MFA_REQUIRED') {
      // Privileged role without an enrolled method (P0 accountant moved to ACCOUNTANT_REP).
      await mfa('ENROLL');
      dt = await post('/auth/device-token', {'deviceName': 'QA qa-people'});
    }
    final t = DevApi.expectOk(dt, 201);
    return DevApi(email, t.map['token'] as String);
  } finally {
    c.close();
  }
}

// ---- the app ------------------------------------------------------------------

const _storage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);

/// Cold-starts the real app signed in as [who] (Keychain token → splash →
/// GET /mobile/session + /me → AppShell on "בית").
Future<void> launchAppAs(WidgetTester tester, DevApi who) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await session.signOutLocally(); // local only: the token stays valid for [who]
  await AppCache.isFirstLaunch(); // the install marker exists → restore keeps our token
  await _storage.deleteAll(); // no Face ID lock left by an earlier run
  // …and none offered now: without the key the app treats Face ID as on and a
  // real (unanswerable) system prompt blocks the simulator.
  await _storage.write(key: 'biometric_enabled', value: '0');
  await _storage.write(key: 'device_token', value: who.token);
  await _storage.write(key: 'business_id', value: who.businessId);
  currentTab.value = AppTab.home;
  peopleChip.value = null;
  resetStatementProbe();
  AppRouter.instance.install();
  await tester.pumpWidget(const TevelApp());
  await pumpUntil(
    tester,
    find.byType(AppShell),
    timeout: const Duration(seconds: 40),
    what: 'AppShell as ${who.email}',
  );
  await pumpFor(tester, const Duration(seconds: 1));
}

/// Leaves the app without revoking anything (tokens are revoked in tearDownAll).
Future<void> closeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await session.signOutLocally();
}

/// Runs [open] (a router helper) on the root navigator's context.
void atRoot(void Function(BuildContext context) open) =>
    open(navigatorKey.currentContext!);

Future<void> pumpFor(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps (real time) until [finder] finds something.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  String? what,
}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end))
      fail('timed out waiting for ${what ?? finder}');
    await tester.pump(const Duration(milliseconds: 150));
  }
}

/// Pumps until [finder] finds nothing (a sheet / dialog closed).
Future<void> pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  String? what,
}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(end)) fail('still showing ${what ?? finder}');
    await tester.pump(const Duration(milliseconds: 150));
  }
}

/// Polls [check] (API) until it returns non-null.
Future<T> eventually<T extends Object>(
  Future<T?> Function() check, {
  Duration timeout = const Duration(seconds: 20),
  required String what,
}) async {
  final end = DateTime.now().add(timeout);
  while (true) {
    final v = await check();
    if (v != null) return v;
    if (DateTime.now().isAfter(end)) fail('timed out: $what');
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}

String fieldText(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)).first,
    )
    .controller
    .text;

/// SPEC-v2 §1 F3.1: counts taps on buttons / rows / chips (typing, scrolling
/// and auto-focused fields are free). [virtual] records a tap the test cannot
/// make itself (the camera shutter in the mocked camera).
class TapCounter {
  int count = 0;
  final List<String> log = [];

  Future<void> tap(WidgetTester tester, Finder finder, String what) async {
    await tester.ensureVisible(finder.first);
    await tester.pump(const Duration(milliseconds: 100));
    await uncover(tester, finder.first);
    await tester.tap(finder.first);
    count++;
    log.add(what);
    await tester.pump(const Duration(milliseconds: 150));
  }

  void virtual(String what) {
    count++;
    log.add('$what (virtual)');
  }

  @override
  String toString() => '$count taps: ${log.join(' → ')}';
}

// ---- camera + OCR fixtures ------------------------------------------------------

/// A JPEG no earlier run uploaded (the server dedupes uploads by sha256).
Uint8List uniqueJpeg() {
  final seed = DateTime.now().microsecondsSinceEpoch;
  final r = Random(seed);
  final im = img.Image(width: 360, height: 480);
  img.fill(im, color: img.ColorRgb8(240, 240, 235));
  for (var i = 0; i < 24; i++) {
    final x = r.nextInt(320), y = r.nextInt(440);
    img.fillRect(
      im,
      x1: x,
      y1: y,
      x2: x + 8 + r.nextInt(60),
      y2: y + 4 + r.nextInt(12),
      color: img.ColorRgb8(r.nextInt(120), r.nextInt(120), r.nextInt(120)),
    );
  }
  return img.encodeJpg(im, quality: 90);
}

const _pickImageChannel =
    'dev.flutter.pigeon.image_picker_ios.ImagePickerApi.pickImage';

/// The camera (image_picker_ios) answers with [jpeg] instead of opening.
Future<void> mockCamera(WidgetTester tester, Uint8List jpeg) async {
  final dir = await getTemporaryDirectory();
  final file = File(
    '${dir.path}/qa-people-$runTag-${Random().nextInt(1 << 30)}.jpg',
  );
  await file.writeAsBytes(jpeg, flush: true);
  tester.binding.defaultBinaryMessenger.setMockMessageHandler(
    _pickImageChannel,
    (_) async =>
        const StandardMessageCodec().encodeMessage(<Object?>[file.path]),
  );
}

void unmockCamera(WidgetTester tester) => tester.binding.defaultBinaryMessenger
    .setMockMessageHandler(_pickImageChannel, null);

/// Wraps the app's HTTP client: `POST /expenses/:id/extract` (no OCR provider
/// on dev → 503) becomes a successful read whose values [fixture] stores on
/// the real server. Every other request goes to the dev API unchanged.
class OcrFixtureClient extends http.BaseClient {
  OcrFixtureClient(this.inner, this.fixture);

  final http.Client inner;
  final Future<void> Function(String expenseId) fixture;
  final List<String> extracted = [];

  static final _extract = RegExp(r'^/expenses/([0-9a-fA-F-]{36})/extract$');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final m = _extract.firstMatch(request.url.path);
    if (request.method == 'POST' && m != null) {
      extracted.add(m[1]!);
      await fixture(m[1]!);
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"status":"EXTRACTED"}')),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return inner.send(request);
  }
}
