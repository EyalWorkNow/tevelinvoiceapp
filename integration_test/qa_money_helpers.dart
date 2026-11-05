// QA (qa-money) helpers for integration_test/v2_qa-money_test.dart.
//
// * [DevApi]: a SEPARATE http client (not ApiClient.instance) that signs in a
//   dev preset (password + e-mail MFA code read from MAILDIR) and sets up /
//   verifies server state on the dev API (:3031, never prod).
// * Fixtures: customer, issued 300/305/320, receipt, quote.
// * App side: [openDocAs] signs the real app in with a device token of the
//   same preset and shows D (DocumentScreen) for a document id.
// * [TapCounter] counts taps (SPEC-v2 §1 F3.1).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:invoice/api/client.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/document/document_screen.dart';
import 'package:invoice/screens/document/sheets/s6_share.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/session.dart';
import 'package:invoice/ui/theme.dart';
import 'package:invoice/util/biometric.dart';

const apiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://127.0.0.1:3031');
const _mailDirDefine = String.fromEnvironment('MAILDIR');
const devPassword = 'Mobile12345678';
const murshe = '3b773037-e71d-49bd-a951-76845e4abe07';
const paturBusiness = 'c934a7a8-df74-433d-a5e2-e342c16142b1';

/// The dev role presets (docs/API-MOBILE.md "Role presets").
enum QaPreset {
  owner('mobile-owner@tevel.test', murshe, mfa: true),
  partner('mobile-partner@tevel.test', murshe, mfa: true),
  employeeSelf('mobile-employee@tevel.test', murshe, mfa: true),
  staff('mobile-staff@tevel.test', murshe),
  accountant('mobile-accountant@tevel.test', murshe),
  cpaFull('mobile-cpa-full@tevel.test', murshe, mfa: true),
  cpaRep('mobile-cpa-rep@tevel.test', murshe, mfa: true),
  viewer('mobile-viewer@tevel.test', murshe),
  patur('mobile-patur@tevel.test', paturBusiness, mfa: true);

  const QaPreset(this.email, this.businessId, {this.mfa = false});
  final String email;
  final String businessId;
  final bool mfa;
}

String get mailDir {
  if (_mailDirDefine.isNotEmpty) return _mailDirDefine;
  return '${Platform.environment['HOME']}/invoiceproject-mobile-dev-storage/outgoing-emails';
}

/// One HTTP answer: status + decoded JSON (or {} / {'_text': body}).
class Res {
  Res(this.status, this.json, this.body);
  final int status;
  final Map<String, dynamic> json;
  final String body;
  String? get error => json['error'] as String?;

  @override
  String toString() => 'Res($status ${body.length > 300 ? body.substring(0, 300) : body})';
}

/// The newest dev mail JSON files (newest first) written after [since].
List<Map<String, dynamic>> mailsSince(DateTime since) {
  final dir = Directory(mailDir);
  if (!dir.existsSync()) return const [];
  final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
    ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
  final out = <Map<String, dynamic>>[];
  for (final f in files) {
    if (f.statSync().modified.isBefore(since)) break;
    try {
      out.add(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
    } on Object {
      // a file still being written
    }
  }
  return out;
}

/// A fresh Idempotency-Key (UUID v4).
String idemKey() => ApiClient.newIdempotencyKey();

String today() {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

/// Signed-in dev account for setup and checks. One sign-in (one MFA code)
/// per preset per run: [apiToken] for this helper, [appToken] for the app.
class DevApi {
  DevApi._(this.preset);

  final QaPreset preset;
  final http.Client _http = http.Client();
  late String apiToken;
  late String appToken;
  String get businessId => preset.businessId;

  static final Map<QaPreset, DevApi> _signedIn = {};

  static Future<DevApi> as(QaPreset preset) async {
    final known = _signedIn[preset];
    if (known != null) return known;
    final api = DevApi._(preset);
    await api._signIn();
    return _signedIn[preset] = api;
  }

  /// Revoke every token this run minted (tearDownAll).
  static Future<void> signOutAll() async {
    for (final api in _signedIn.values) {
      for (final t in [api.apiToken, api.appToken]) {
        try {
          await api._http.post(Uri.parse('$apiBase/mobile/logout'),
              headers: {'authorization': 'Bearer $t', 'content-type': 'application/json'}, body: '{}');
        } on Object {
          // best effort
        }
      }
    }
    _signedIn.clear();
  }

  // ---- sign-in (cookie + CSRF → MFA → two device tokens) --------------------

  String? _cookie;
  String? _csrf;

  Future<Res> _cookiePost(String path, Object body) async {
    final r = await _http.post(Uri.parse('$apiBase$path'),
        headers: {
          'content-type': 'application/json',
          'accept': 'application/json',
          'cookie': ?(_cookie == null ? null : 'tvl_session=$_cookie'),
          'x-csrf-token': ?_csrf,
        },
        body: jsonEncode(body));
    final set = r.headers['set-cookie'];
    final m = set == null ? null : RegExp(r'tvl_session=([^;]+)').firstMatch(set);
    if (m != null) _cookie = m.group(1);
    final res = _res(r);
    final csrf = res.json['csrfToken'];
    if (csrf is String && csrf.isNotEmpty) _csrf = csrf;
    return res;
  }

  Future<void> _signIn() async {
    final login = await _cookiePost('/auth/login', {'email': preset.email, 'password': devPassword});
    if (login.status != 200) throw StateError('login ${preset.email}: $login');
    Future<void> mfa(String purpose) async {
      final since = DateTime.now().subtract(const Duration(seconds: 2));
      final send = await _cookiePost('/auth/mfa/email/send', {'purpose': purpose});
      if (send.status != 200) throw StateError('mfa send ${preset.email}: $send');
      String? code;
      for (var i = 0; i < 40 && code == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        for (final m in mailsSince(since)) {
          final subject = '${m['subject']}';
          if (m['to'] == preset.email && RegExp(r'^\d{6}').hasMatch(subject)) {
            code = subject.substring(0, 6);
            break;
          }
        }
      }
      if (code == null) throw StateError('no MFA mail for ${preset.email} in $mailDir');
      final verify =
          await _cookiePost('/auth/mfa/email/verify', {'code': code, if (purpose == 'ENROLL') 'purpose': purpose});
      if (verify.status != 200) throw StateError('mfa verify ${preset.email}: $verify');
    }

    if (login.json['status'] == 'MFA_REQUIRED') await mfa('LOGIN');
    var a = await _cookiePost('/auth/device-token', {'deviceName': 'qa-money api'});
    if (a.status == 403 && a.json['error'] == 'MFA_REQUIRED') {
      // Privileged role without an enrolled method (P0 accountant moved to ACCOUNTANT_REP).
      await mfa('ENROLL');
      a = await _cookiePost('/auth/device-token', {'deviceName': 'qa-money api'});
    }
    final b = await _cookiePost('/auth/device-token', {'deviceName': 'qa-money app'});
    if (a.status != 201 || b.status != 201) throw StateError('device-token ${preset.email}: $a / $b');
    apiToken = a.json['token'] as String;
    appToken = b.json['token'] as String;
    _cookie = null;
    _csrf = null;
  }

  // ---- bearer calls -----------------------------------------------------------

  Map<String, String> _headers({String? idem, bool business = true}) => {
        'authorization': 'Bearer $apiToken',
        'accept': 'application/json',
        'content-type': 'application/json',
        'x-business-id': ?(business ? businessId : null),
        'idempotency-key': ?idem,
      };

  Res _res(http.Response r) {
    final body = utf8.decode(r.bodyBytes);
    Map<String, dynamic> json = const {};
    try {
      final d = jsonDecode(body);
      if (d is Map<String, dynamic>) json = d;
    } on FormatException {
      json = const {};
    }
    return Res(r.statusCode, json, body);
  }

  Future<Res> get(String path, {Map<String, String>? query}) async => _res(await _http.get(
      Uri.parse('$apiBase$path').replace(queryParameters: query), headers: _headers()));

  Future<Res> post(String path, [Object body = const {}, String? idem]) async => _res(
      await _http.post(Uri.parse('$apiBase$path'), headers: _headers(idem: idem), body: jsonEncode(body)));

  Future<Res> put(String path, Object body) async =>
      _res(await _http.put(Uri.parse('$apiBase$path'), headers: _headers(), body: jsonEncode(body)));

  Future<Res> delete(String path) async =>
      _res(await _http.delete(Uri.parse('$apiBase$path'), headers: _headers()));

  /// Fails the test unless [r] has [status].
  static Res expectStatus(Res r, int status, [String? what]) {
    expect(r.status, status, reason: '${what ?? ''} $r');
    return r;
  }

  // ---- reads ----------------------------------------------------------------------

  /// GET /documents/:id → `document` (lines under `_lines`).
  Future<Map<String, dynamic>> document(String id) async {
    final r = expectStatus(await get('/documents/$id'), 200, 'GET /documents/$id');
    return {...r.json['document'] as Map<String, dynamic>, '_lines': r.json['lines']};
  }

  /// GET /documents row (camelCase, BE-10a fields) for [id].
  Future<Map<String, dynamic>?> listRow(String id, {Map<String, String> query = const {}}) async {
    final r = expectStatus(await get('/documents', query: {'limit': '500', ...query}), 200, 'GET /documents');
    for (final d in r.json['documents'] as List) {
      if ((d as Map)['id'] == id) return d.cast<String, dynamic>();
    }
    return null;
  }

  // ---- fixtures -------------------------------------------------------------------

  /// A fresh customer (own data per run, so consent / balances are known).
  Future<String> newCustomer({String? phone = '0501234567', String? email, String type = 'INDIVIDUAL'}) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final r = expectStatus(
        await post('/customers', {
          'name': 'QA כסף $stamp',
          'customerType': type,
          'phone': ?phone,
          'email': ?email,
        }),
        201,
        'POST /customers');
    return r.json['id'] as String;
  }

  /// Draft → finalize → original PDF. [netMinor] per line before VAT.
  /// [shared] = a share link was made (sentAt set → D row 9, not 8).
  Future<String> issue({
    required String type,
    required String customerId,
    int netMinor = 100000,
    int? rate,
    bool shared = false,
    String description = 'בדיקת QA כסף',
  }) async {
    final vat = rate ?? (type == 'TRANSACTION_INVOICE' || type == 'RECEIPT' ? 0 : 1800);
    final draft = expectStatus(
        await post('/documents', {
          'documentType': type,
          'customerId': customerId,
          'currency': 'ILS',
          'fiscalContext': 'default',
          'lines': [
            {
              'description': description,
              'quantityMicros': '1000000',
              'unitPriceMinor': '$netMinor',
              'taxRateBasisPoints': vat,
            }
          ],
        }),
        201,
        'POST /documents $type');
    final id = draft.json['id'] as String;
    final fin = expectStatus(await post('/documents/$id/finalize', {'scopeKey': 'default'}, idemKey()), 200,
        'finalize $type');
    expect(fin.json['status'], 'FINALIZED', reason: 'finalize $type: $fin');
    expectStatus(await post('/documents/$id/artifact'), 201, 'artifact $type');
    if (shared) expectStatus(await post('/documents/$id/share-link'), 201, 'share-link');
    return id;
  }

  /// POST /payments [key] → id.
  Future<String> payment(int amountMinor, {String method = 'CASH'}) async {
    final r = expectStatus(
        await post('/payments',
            {'method': method, 'amountMinor': '$amountMinor', 'currency': 'ILS', 'paymentDate': today()}, idemKey()),
        201,
        'POST /payments');
    return r.json['paymentId'] as String;
  }

  /// A 320 with its whole total paid in cash (J1 result).
  Future<String> paid320(String customerId, {int netMinor = 100000}) async {
    final id = await issue(type: 'TAX_INVOICE_RECEIPT', customerId: customerId, netMinor: netMinor);
    final total = BigInt.parse('${(await document(id))['total_minor']}').toInt();
    final pay = await payment(total);
    expectStatus(await post('/documents/$id/payments', {'paymentId': pay, 'amountMinor': '$total'}), 200,
        'allocate 320');
    return id;
  }

  /// Pays [amountMinor] on a 300/305 and issues the receipt (400) for it.
  /// Returns the receipt id.
  Future<String> payWithReceipt(String documentId, int amountMinor, String customerId) async {
    final pay = await payment(amountMinor);
    expectStatus(await post('/documents/$documentId/payments', {'paymentId': pay, 'amountMinor': '$amountMinor'}),
        200, 'allocate');
    final r = expectStatus(
        await post(
            '/receipts',
            {
              'paymentIds': [
                {'id': pay}
              ],
              'scopeKey': 'default',
              'forDocumentId': documentId,
              'customerId': customerId,
            },
            idemKey()),
        201,
        'POST /receipts');
    final receipt = r.json['receiptDocumentId'] as String;
    expectStatus(await post('/documents/$receipt/artifact'), 201, 'receipt artifact');
    return receipt;
  }

  /// A quote (net lines) in [status] (DRAFT or SENT).
  Future<String> quote(String customerId, {int netMinor = 100000, String status = 'DRAFT'}) async {
    final valid = DateTime.now().add(const Duration(days: 14));
    final r = expectStatus(
        await post('/quotes', {
          'customerId': customerId,
          'currency': 'ILS',
          'validUntil': valid.toIso8601String().substring(0, 10),
          'lines': [
            {
              'description': 'הצעת QA כסף',
              'quantityMicros': '1000000',
              'unitPriceMinor': '$netMinor',
              'taxRateBasisPoints': 1800,
            }
          ],
        }),
        201,
        'POST /quotes');
    final id = r.json['id'] as String;
    if (status != 'DRAFT') expectStatus(await post('/quotes/$id/status', {'to': status}), 200, 'quote status');
    return id;
  }
}

/// Public page (no auth): GET [url] → HTML text.
Future<Res> publicPage(String url) async {
  final r = await http.get(Uri.parse(url));
  return Res(r.statusCode, const {}, utf8.decode(r.bodyBytes));
}

/// The /d/ link inside a wa.me URL's text.
String? shareLinkIn(Uri waUri) {
  final text = waUri.queryParameters['text'] ?? '';
  return RegExp(r'https?://\S+/d/[A-Za-z0-9_-]+').firstMatch(text)?.group(0);
}

BigInt minor(Object? v) => BigInt.parse('$v');

// ---- app side ---------------------------------------------------------------------

/// PDFs / texts handed to the iOS share sheet (no share sheet in automation).
final sharedPdfs = <String>[];
final sharedTexts = <String>[];

const _keychain = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device));

/// Signs the app in as [preset] (device token in the Keychain → session.restore
/// → /me), then shows D for [docId] on its own MaterialApp root.
Future<void> openDocAs(WidgetTester tester, QaPreset preset, String docId, {bool quote = false}) async {
  final api = await DevApi.as(preset);
  await AppCache.isFirstLaunch(); // consume the marker: restore must not revoke our token
  await Biometric.instance.setEnabled(false);
  pdfSharer = (bytes, name, {text}) async => sharedPdfs.add(name);
  textSharer = (text) async => sharedTexts.add(text);
  ApiClient.instance.clearCredentials();
  await _keychain.write(key: 'device_token', value: api.appToken);
  await _keychain.write(key: 'business_id', value: preset.businessId);
  await session.restore();
  expect(session.status, SessionStatus.signedIn, reason: 'app sign-in as ${preset.email}');
  expect(session.business?.businessId, preset.businessId);
  expect(session.me, isNotNull, reason: '/me for ${preset.email}');

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MaterialApp(
    navigatorKey: navigatorKey,
    scaffoldMessengerKey: messengerKey,
    locale: const Locale('he', 'IL'),
    supportedLocales: const [Locale('he', 'IL')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: buildTheme(Brightness.light),
    home: DocumentScreen(id: docId, isQuote: quote),
  ));
  await pumpUntil(tester, find.byKey(const Key('doc-status-line')).hitTestable(),
      orElse: find.byKey(const Key('doc-primary')));
  await settleNetwork(tester);
}

/// Pumps until [finder] (or [orElse]) shows, up to [timeout].
Future<void> pumpUntil(WidgetTester tester, Finder finder,
    {Finder? orElse, Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
    if (orElse != null && orElse.evaluate().isNotEmpty) return;
  }
  fail('timed out waiting for $finder');
}

/// Lets in-flight HTTP finish (real network on the simulator).
Future<void> settleNetwork(WidgetTester tester, {Duration d = const Duration(seconds: 2)}) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Counts every tap (F3.1) and waits for the network after it.
class TapCounter {
  int taps = 0;

  Future<void> tap(WidgetTester tester, Finder f, {Duration settle = const Duration(seconds: 2)}) async {
    taps++;
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await settleNetwork(tester, d: settle);
  }
}

Finder primaryButton() => find.byKey(const Key('doc-primary'));

/// The label of D's one PrimaryButton.
String primaryLabel(WidgetTester tester) {
  final texts = find.descendant(of: primaryButton(), matching: find.byType(Text));
  return [for (final e in texts.evaluate()) (e.widget as Text).data ?? ''].join(' ').trim();
}

/// The ⋯ menu labels of D (opens and closes the menu; not counted as taps).
Future<List<String>> menuLabels(WidgetTester tester) async {
  final more = find.byTooltip('עוד');
  if (more.evaluate().isEmpty) return const [];
  await tester.tap(more);
  await settleNetwork(tester, d: const Duration(milliseconds: 800));
  final sheet = find.byType(BottomSheet);
  final labels = [
    for (final e in find.descendant(of: sheet, matching: find.byType(Text)).evaluate())
      (e.widget as Text).data ?? ''
  ];
  navigatorKey.currentState!.pop();
  await settleNetwork(tester, d: const Duration(milliseconds: 800));
  return labels;
}

/// Text of D's status line (status pill + amount + words); scrolls it into
/// view first (the PDF preview takes 60% of the height).
Future<String> statusLineText(WidgetTester tester) async {
  final line = find.byKey(const Key('doc-status-line'));
  if (line.evaluate().isEmpty) {
    final list = find.descendant(of: find.byType(DocumentScreen).last, matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(line, 200, scrollable: list.first);
    await tester.pump(const Duration(milliseconds: 300));
  }
  return [
    for (final e in find.descendant(of: line, matching: find.byType(RichText)).evaluate())
      (e.widget as RichText).text.toPlainText()
  ].join(' ');
}
