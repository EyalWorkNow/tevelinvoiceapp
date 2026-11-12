// Customers (squad D, SPEC-v2 §6.P, §6.P2, S2, §10). Server: API-MOBILE §6.7
// (V1) and BE-09 (`GET /customers?q=&sort=&limit=`, `GET /customers/:id`).
// Every BE-09 call falls back to the V1 shape when the route is missing
// (404 NOT_FOUND), so the app runs against either server.

import 'dart:typed_data';

import '../state/cache.dart';
import '../state/session.dart';
import '../util/errors_he.dart';
import '../util/status_map.dart';
import 'client.dart';
import 'models/models.dart';

final _api = ApiClient.instance;

/// GET /customers returns at most this many (V1 and BE-09 without paging).
const int customerListCap = 500;

/// GET /documents?unpaid=1 row cap the app asks for (BE-10a clamps to 500).
const int openDocumentsCap = 500;

String? get _bid => session.business?.businessId;
String _listKey(String? bid) => 'people_customers_$bid';
String _recentKey(String? bid) => 'people_recent_$bid';
String _recentPaymentKey(String? bid) => 'people_recent_payment_$bid';
String _walkInKey(String? bid) => 'people_walkin_$bid';

/// True when [e] means "this server has no such route" (BE-xx not deployed).
bool isMissingRoute(Object e) =>
    e is ApiException && e.status == 404 && e.code == 'NOT_FOUND';

/// The customer list as P / S2 show it.
class CustomerList {
  const CustomerList(this.customers, {this.capped = false, this.be09 = false});

  /// Active AND archived (archived appear only in search, §6.P).
  final List<Customer> customers;

  /// The server returned [customerListCap] rows: there may be more.
  final bool capped;

  /// Rows carry BE-09 fields (balance, lastDocumentAt, consent…).
  final bool be09;

  List<Customer> get active => [
    for (final c in customers)
      if (!c.isArchived) c,
  ];
}

List<Customer> _parse(Object? list) => [
  for (final c in (list as List? ?? const []))
    Customer.fromJson(Map<String, dynamic>.from(c as Map)),
];

CustomerList _listFrom(List raw, {int? total}) {
  final customers = _parse(raw);
  final be09 =
      raw.isNotEmpty &&
      raw.first is Map &&
      (raw.first as Map).containsKey('balanceMinor');
  final capped = total != null
      ? total > customers.length
      : customers.length >= customerListCap;
  return CustomerList(customers, capped: capped, be09: be09);
}

/// Last list of this business from the cache, or null.
Future<CustomerList?> readCachedCustomerList() async {
  try {
    final json = await AppCache.read(_listKey(_bid));
    return json is List ? _listFrom(json) : null;
  } on Object {
    return null;
  }
}

/// GET /customers?sort=recent&limit=500 (a V1 server ignores the query and
/// returns ≤500 by name). Refreshes the cache of the business it was sent for.
Future<CustomerList> fetchCustomerList() async {
  final bid = _bid;
  final json = await _api.get(
    '/customers',
    query: {'sort': 'recent', 'limit': '$customerListCap'},
  );
  final raw = json['customers'] as List? ?? const [];
  try {
    await AppCache.write(_listKey(bid), raw);
  } on Object {
    // The cache is a convenience; never fail the screen on it.
  }
  return _listFrom(raw, total: (json['total'] as num?)?.toInt());
}

/// Active customers (cache when offline is the caller's choice).
Future<List<Customer>> fetchCustomers() async =>
    (await fetchCustomerList()).active;

/// BE-09 server search (name / phone / tax id / e-mail), archived included.
Future<List<Customer>> searchCustomers(String q, {int limit = 50}) async {
  final json = await _api.get(
    '/customers',
    query: {'q': q.trim(), 'limit': '$limit'},
  );
  return _parse(json['customers']);
}

/// GET /customers/:id (BE-09); without BE-09 the list row (stats unknown).
/// Throws ApiException CUSTOMER_NOT_FOUND when it does not exist.
Future<CustomerDetail> fetchCustomerDetail(String id) async {
  try {
    return CustomerDetail.fromJson(await _api.get('/customers/$id'));
  } on ApiException catch (e) {
    if (!isMissingRoute(e)) rethrow;
  }
  final list = await fetchCustomerList();
  for (final c in list.customers) {
    if (c.id == id) return CustomerDetail(customer: c);
  }
  throw ApiException(
    404,
    'CUSTOMER_NOT_FOUND',
    errorMessageHe('CUSTOMER_NOT_FOUND', status: 404),
  );
}

/// INDIVIDUAL, or BUSINESS when a tax id is given (§10: derived, not asked).
String customerTypeFor(String? taxId) =>
    (taxId == null || taxId.trim().isEmpty) ? 'INDIVIDUAL' : 'BUSINESS';

/// POST /customers → the new customer (the server returns only the id).
/// vatDealerStatus is not asked for here (§4.9: asked only when the server
/// needs it); only the walk-in passes PRIVATE.
Future<Customer> createCustomer({
  required String name,
  String? customerType,
  String? phone,
  String? email,
  String? taxId,
  String? vatDealerStatus,
}) async {
  final type = customerType ?? customerTypeFor(taxId);
  final json = await _api.post('/customers', {
    'name': name,
    'customerType': type,
    'phone': phone,
    'email': email,
    'taxId': taxId,
    'vatDealerStatus': ?vatDealerStatus,
  });
  return Customer(
    id: json['id'] as String,
    name: name,
    phone: phone,
    email: email,
    taxId: taxId,
    vatDealerStatus: vatDealerStatus,
    customerType: type,
    consentGranted: false,
  );
}

/// POST /customers/:id/consent — the owner says the customer agreed to
/// digital documents (S2 switch; S6 CONSENT_REQUIRED dialog).
Future<void> grantConsent(String customerId) =>
    _api.post('/customers/$customerId/consent', {'method': 'VERBAL_IN_APP'});

/// PATCH /customers/:id with only the changed fields (null clears a field).
Future<void> updateCustomer(String id, Map<String, Object?> changes) async {
  if (changes.isEmpty) return;
  await _api.patch('/customers/$id', changes);
}

/// POST /customers/:id/archive (idempotent).
Future<void> archiveCustomer(String id) async {
  await _api.post('/customers/$id/archive');
}

/// GET /documents?customerId=&limit=100 (newest first).
Future<List<DocumentSummary>> fetchCustomerDocuments(String customerId) async {
  final json = await _api.get(
    '/documents',
    query: {'customerId': customerId, 'limit': '100'},
  );
  return _docs(json);
}

List<DocumentSummary> _docs(Map<String, dynamic> json) => [
  for (final d in (json['documents'] as List? ?? const []))
    DocumentSummary.fromJson(d as Map<String, dynamic>),
];

const Set<String> _notIssued = {
  'DRAFT',
  'VALIDATING',
  'READY_TO_FINALIZE',
  'PENDING_APPROVAL',
  'REJECTED',
  'WAITING_FOR_ALLOCATION',
};

/// Sum of what is still owed on issued 300/305 (openMinor, BE-10a, else
/// balance). Receipts / 320 / credits never count (§15.5).
BigInt openBalanceOf(Iterable<DocumentSummary> docs) {
  var total = BigInt.zero;
  for (final d in docs) {
    if (!isCollectionType(d.documentType) ||
        _notIssued.contains(d.status) ||
        d.voidedAt != null) {
      continue;
    }
    final open = d.openMinor;
    if (open != null && open > BigInt.zero) total += open;
  }
  return total;
}

/// One customer's exact open balance: GET /documents?customerId=&unpaid=1&limit=500.
Future<BigInt> fetchCustomerOpenMinor(String customerId) async {
  final json = await _api.get(
    '/documents',
    query: {
      'customerId': customerId,
      'unpaid': '1',
      'limit': '$openDocumentsCap',
    },
  );
  return openBalanceOf(_docs(json));
}

/// customerId → open balance, or null when the answer was capped (§6.P: a
/// partial number is never shown; balances then appear only on P2).
Future<Map<String, BigInt>?> fetchOpenBalances() async {
  final json = await _api.get(
    '/documents',
    query: {'unpaid': '1', 'limit': '$openDocumentsCap'},
  );
  final docs = _docs(json);
  final total = (json['total'] as num?)?.toInt() ?? docs.length;
  if (docs.length >= openDocumentsCap || total > docs.length) return null;
  final byCustomer = <String, List<DocumentSummary>>{};
  for (final d in docs) {
    final id = d.customerId;
    if (id != null) (byCustomer[id] ??= []).add(d);
  }
  return {
    for (final e in byCustomer.entries)
      if (openBalanceOf(e.value) > BigInt.zero) e.key: openBalanceOf(e.value),
  };
}

// ---- statement / כרטסת (BE-17, P2) -------------------------------------------

/// The statement period the card sends: from 1 January of this year to today.
({String from, String to}) statementPeriod([DateTime? now]) {
  final d = now ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return (
    from: '${d.year}-01-01',
    to: '${d.year}-${two(d.month)}-${two(d.day)}',
  );
}

final Map<String?, bool> _statementSupport = {};

/// True when this server has BE-17 (probed once per business per app run with
/// a one-day GET /customers/:id/statement; a missing route → false and the
/// "שלח כרטסת" row stays hidden, F5). Network errors are not cached.
Future<bool> statementAvailable(String customerId) async {
  final bid = _bid;
  final known = _statementSupport[bid];
  if (known != null) return known;
  final p = statementPeriod();
  try {
    await _api.get(
      '/customers/$customerId/statement',
      query: {'from': p.to, 'to': p.to},
    );
    return _statementSupport[bid] = true;
  } on ApiException catch (e) {
    if (e.isNetwork) return false;
    return _statementSupport[bid] = !isMissingRoute(e);
  }
}

/// Test hook: forget the probe results.
void resetStatementProbe() => _statementSupport.clear();

/// POST /customers/:id/statement/send {channel:'EMAIL', from, to} (BE-17).
Future<void> sendStatement(String customerId, {DateTime? now}) {
  final p = statementPeriod(now);
  return _api.post('/customers/$customerId/statement/send', {
    'channel': 'EMAIL',
    'from': p.from,
    'to': p.to,
  });
}

/// GET /customers/:id/statement.pdf?from=&to= (BE-17) → PDF bytes.
Future<Uint8List> fetchStatementPdf(String customerId, {DateTime? now}) {
  final p = statementPeriod(now);
  return _api.getBytes(
    '/customers/$customerId/statement.pdf',
    query: {'from': p.from, 'to': p.to},
  );
}

// ---- walk-in + recents (S2) ----------------------------------------------------

/// The one "לקוח מזדמן" record of the business: BE-09 isWalkIn, else the id
/// remembered on this device, else it is created. It is always PRIVATE (§4.9:
/// never an authorized dealer, never asks "עוסק מורשה?" nor needs an
/// allocation number): created with vatDealerStatus PRIVATE, and an existing
/// walk-in that is not PRIVATE (e.g. UNKNOWN from V1) is PATCHed to it.
/// With [be09] a new record is flagged on the server too (PATCH isWalkIn:true).
Future<Customer> walkInCustomer(
  List<Customer> loaded, {
  required String name,
  bool be09 = false,
}) async {
  for (final c in loaded) {
    if (c.isWalkIn && !c.isArchived) return _walkInPrivate(c);
  }
  final bid = _bid;
  Object? remembered;
  try {
    remembered = await AppCache.read(_walkInKey(bid));
  } on Object {
    remembered = null;
  }
  for (final c in loaded) {
    if (!c.isArchived && (c.id == remembered || c.name.trim() == name)) {
      return _walkInPrivate(c);
    }
  }
  final created = await createCustomer(
    name: name,
    customerType: 'INDIVIDUAL',
    vatDealerStatus: _private,
  );
  if (be09) {
    try {
      await updateCustomer(created.id, {'isWalkIn': true});
    } on ApiException catch (e) {
      if (e.isNetwork) rethrow; // the local id below still finds it next time
    }
  }
  try {
    await AppCache.write(_walkInKey(bid), created.id);
  } on Object {
    // best effort
  }
  return created;
}

const _private = 'PRIVATE';

Future<Customer> _walkInPrivate(Customer c) async {
  if (c.vatDealerStatus == _private) return c;
  try {
    await updateCustomer(c.id, {'vatDealerStatus': _private});
  } on ApiException catch (e) {
    if (e.isNetwork) rethrow;
    return c; // not fatal: the issue flow still asks if the server needs it
  }
  return c.copyWith(vatDealerStatus: _private);
}

/// Ids picked most recently in S2 on this device (newest first, ≤8).
Future<List<String>> readRecentCustomerIds() async {
  try {
    final v = await AppCache.read(_recentKey(_bid));
    return v is List ? [for (final e in v) '$e'] : const [];
  } on Object {
    return const [];
  }
}

Future<void> rememberRecentCustomer(String id) async {
  final ids = [
    id,
    ...(await readRecentCustomerIds()).where((e) => e != id),
  ].take(8).toList();
  try {
    await AppCache.write(_recentKey(_bid), ids);
  } on Object {
    // best effort
  }
}

/// Customers who received a payment most recently on this device (newest first, <=8).
Future<List<String>> readRecentPaymentCustomerIds() async {
  try {
    final value = await AppCache.read(_recentPaymentKey(_bid));
    return value is List ? [for (final item in value) '$item'] : const [];
  } on Object {
    return const [];
  }
}

Future<void> rememberRecentPaymentCustomer(String id) async {
  final ids = [
    id,
    ...(await readRecentPaymentCustomerIds()).where((value) => value != id),
  ].take(8).toList();
  try {
    await AppCache.write(_recentPaymentKey(_bid), ids);
  } on Object {
    // Recent recipients improve the picker but never block issuing a receipt.
  }
}

// ---- pure helpers (tested) -------------------------------------------------

String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

/// Search by name, e-mail, phone digits or tax id digits (≥3 digits).
bool customerMatches(Customer c, String query) => personMatches(
  query,
  name: c.name,
  email: c.email,
  phone: c.phone,
  taxId: c.taxId,
);

bool personMatches(
  String query, {
  required String name,
  String? email,
  String? phone,
  String? taxId,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  if (name.toLowerCase().contains(q)) return true;
  if ((email ?? '').toLowerCase().contains(q)) return true;
  final qd = _digits(q);
  return qd.length >= 3 &&
      (_digits(phone ?? '').contains(qd) || _digits(taxId ?? '').contains(qd));
}

/// §6.P order: customers with documents first (newest first), then א–ת.
List<Customer> sortForPeople(
  Iterable<Customer> customers, {
  List<String> recentIds = const [],
}) {
  int rank(Customer c) {
    final i = recentIds.indexOf(c.id);
    return i < 0 ? 1 << 20 : i;
  }

  final list = customers.toList();
  list.sort((a, b) {
    final la = a.lastDocumentAt, lb = b.lastDocumentAt;
    if (la != null || lb != null) {
      if (la == null) return 1;
      if (lb == null) return -1;
      final c = lb.compareTo(la);
      if (c != 0) return c;
    }
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    return a.name.trim().compareTo(b.name.trim());
  });
  return list;
}

/// S2 "5–8 עיגולי אחרונים" (§6 S2): picks made on this device first (most
/// recent first, even before the customer has a document), then [ordered]
/// rows that are [eligible] (e.g. have documents), at most [max].
List<T> recentCircles<T>(
  List<T> ordered,
  String Function(T) idOf,
  List<String> recentIds, {
  required bool Function(T) eligible,
  bool Function(T)? excluded,
  int max = 8,
}) {
  final byId = {for (final e in ordered) idOf(e): e};
  final out = <T>[];
  final seen = <String>{};
  for (final id in recentIds) {
    final e = byId[id];
    if (e == null || (excluded?.call(e) ?? false) || !seen.add(id)) continue;
    out.add(e);
  }
  for (final e in ordered) {
    if (!seen.contains(idOf(e)) && eligible(e)) {
      seen.add(idOf(e));
      out.add(e);
    }
  }
  return out.take(max).toList();
}

/// S2 duplicate check against the loaded list (best-effort, §6 S2): same
/// name, phone digits or tax id. Archived customers are skipped.
Customer? findDuplicateCustomer(
  Iterable<Customer> customers, {
  String? name,
  String? phone,
  String? taxId,
  String? exceptId,
}) {
  final n = (name ?? '').trim();
  final p = _digits(phone ?? '');
  final t = _digits(taxId ?? '');
  for (final c in customers) {
    if (c.isArchived || c.id == exceptId) {
      continue;
    }
    if (n.isNotEmpty && c.name.trim() == n) return c;
    if (p.length >= 9 &&
        _digits(c.phone ?? '').endsWith(p.substring(p.length - 9))) {
      return c;
    }
    if (t.isNotEmpty && _digits(c.taxId ?? '') == t) {
      return c;
    }
  }
  return null;
}

/// Up to two initials for an avatar ("דנה כהן" → "דכ"). Mixed Hebrew/Latin
/// ("QA חייב") → the first only: a mixed pair would render reversed in RTL.
String initialsOf(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  final a = parts.first.characters0;
  if (parts.length == 1) return a;
  final b = parts[1].characters0;
  return _isRtl(a) == _isRtl(b) ? a + b : a;
}

bool _isRtl(String ch) {
  if (ch.isEmpty) return false;
  final c = ch.runes.first;
  return (c >= 0x0590 && c <= 0x08FF) ||
      (c >= 0xFB1D && c <= 0xFDFF) ||
      (c >= 0xFE70 && c <= 0xFEFF);
}

/// Phone as typed / from contacts → what we store: digits, keeping a leading '+'.
/// "050-123 4567" → "0501234567"; "+972 50-123-4567" → "+972501234567".
String? normalizePhoneInput(String input) {
  final t = input.trim();
  if (t.isEmpty) return null;
  final d = _digits(t);
  if (d.isEmpty) return null;
  return t.startsWith('+') ? '+$d' : d;
}

/// Prefer an Israeli mobile (WhatsApp works on it) among a contact's numbers.
String? preferredPhone(List<String> phones) {
  if (phones.isEmpty) return null;
  final mobile = phones.firstWhere(
    (p) =>
        RegExp(r'^(\+?972|0)5').hasMatch(p.replaceAll(RegExp(r'[^\d+]'), '')),
    orElse: () => phones.first,
  );
  return normalizePhoneInput(mobile);
}

/// Israeli ID / company number check digit (9 digits, short ones left-padded).
bool isValidIsraeliId(String input) {
  final d = _digits(input);
  if (d.isEmpty || d.length > 9 || d != input.trim()) return false;
  final padded = d.padLeft(9, '0');
  var sum = 0;
  for (var i = 0; i < 9; i++) {
    var n = int.parse(padded[i]) * (i.isEven ? 1 : 2);
    if (n > 9) n -= 9;
    sum += n;
  }
  return sum % 10 == 0;
}

final RegExp _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
bool isValidEmail(String input) => _emailRe.hasMatch(input.trim());

/// 9–15 digits (Israeli or international).
bool isValidPhoneInput(String input) {
  final d = _digits(input);
  return d.length >= 9 && d.length <= 15;
}

extension on String {
  /// First user-visible character (Hebrew/Latin names are BMP; good enough).
  String get characters0 => isEmpty ? '' : String.fromCharCode(runes.first);
}
