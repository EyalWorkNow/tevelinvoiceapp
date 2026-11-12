// Reference data and device memory of the Composer (SPEC-v2 F8, §7 defaults).
// Owner: squad B. Everything is per business and best-effort: a cache failure
// never fails the Composer.
//
// * VAT rate (GET /tax-rates, cache-first; 1800 if never loaded).
// * Customers (GET /customers; the Composer only resolves an id → Customer).
// * Description: last one for the customer (device, then BE-09 server) →
//   business default (BE-25) → "שירותים".
// * Payment method: the last one used (CASH the first time).
// * "first issue ever" flag (the one-time commitment toast, §6.C step 5).
// * The unsent Composer state ("יציאה עם נתונים → טיוטה מקומית ללא דיאלוג").

import 'dart:async';

import '../../api/client.dart';
import '../../api/issue_api.dart' show cacheWrite, currentBusinessId;
import '../../api/models/models.dart';
import '../../state/cache.dart';
import '../../util/labels/compose_he.dart';

final ApiClient _api = ApiClient.instance;
String get _bid => currentBusinessId;

Future<Object?> _read(String name) async {
  try {
    return await AppCache.read(name);
  } on Object {
    return null;
  }
}

/// Statutory VAT in basis points. Cache-first (the customer picker opens at
/// once): a cached rate is returned now and refreshed in the background; with
/// nothing cached the server is asked and waited for.
Future<int> fetchVatRate() async {
  final key = 'nd_vat_$_bid';
  final cached = await _read(key);
  if (cached is int) {
    unawaited(_refreshVatRate(key).then((_) {}, onError: (Object _) {}));
    return cached;
  }
  try {
    return await _refreshVatRate(key) ?? 1800;
  } on ApiException catch (e) {
    if (!e.isNetwork) rethrow;
  }
  return 1800;
}

/// GET /tax-rates → the VAT rate (also cached); null when the server has none.
Future<int?> _refreshVatRate(String key) async {
  final json = await _api.get('/tax-rates');
  for (final r in (json['rates'] as List? ?? const [])) {
    final m = r as Map<String, dynamic>;
    if (m['tax_code'] == 'VAT') {
      final bp = m['rate_basis_points'] as int;
      await cacheWrite(key, bp);
      return bp;
    }
  }
  return null;
}

/// The customer with [id] (cached list first, then GET /customers).
Future<Customer?> findCustomer(String id) async {
  Customer? from(Object? list) {
    if (list is! List) return null;
    for (final c in list) {
      if (c is Map<String, dynamic> && c['id'] == id)
        return Customer.fromJson(c);
    }
    return null;
  }

  final key = 'nd_customers_$_bid';
  try {
    final json = await _api.get('/customers');
    final list = json['customers'] as List? ?? const [];
    await cacheWrite(key, list);
    return from(list);
  } on ApiException catch (e) {
    if (!e.isNetwork) rethrow;
    return from(await _read(key));
  }
}

/// F8: last description for [customerId] on this device → the customer's
/// last line on the server ([lastOnServer], BE-09 `lastLineDescription`) →
/// [businessDefault] (BE-25) → "שירותים".
Future<String> defaultDescription(
  String? customerId, {
  String? lastOnServer,
  String? businessDefault,
}) async {
  final map = await _read('nd_desc_by_customer_$_bid');
  final last = customerId != null && map is Map ? map[customerId] : null;
  if (last is String && last.trim().isNotEmpty) return last;
  if (lastOnServer != null && lastOnServer.trim().isNotEmpty)
    return lastOnServer.trim();
  if (businessDefault != null && businessDefault.trim().isNotEmpty)
    return businessDefault;
  return ComposeHe.defaultDescription;
}

Future<void> rememberDescription(String? customerId, String description) async {
  final text = description.trim();
  if (customerId == null || text.isEmpty) return;
  final key = 'nd_desc_by_customer_$_bid';
  final map = await _read(key);
  await cacheWrite(key, {if (map is Map) ...map, customerId: text});
}

/// F8: the payment method used last ('CASH' the first time).
Future<String> lastPaymentMethod() async {
  final v = await _read('nd_last_method_$_bid');
  return v is String ? v : 'CASH';
}

Future<void> rememberPaymentMethod(String method) =>
    cacheWrite('nd_last_method_$_bid', method);

/// True exactly once per device: the first successful issue (§6.C step 5).
Future<bool> takeFirstIssueFlag() async {
  if (await _read('nd_first_issue_done') == true) return false;
  await cacheWrite('nd_first_issue_done', true);
  return true;
}

/// The Composer state left without issuing (restored next time, same intent).
Future<Map<String, dynamic>?> loadLocalDraft(String intent) async {
  final v = await _read('nd_local_draft_$_bid');
  if (v is! Map<String, dynamic> || v['intent'] != intent) return null;
  final form = v['form'];
  return form is Map<String, dynamic> ? form : null;
}

Future<void> saveLocalDraft(String intent, Map<String, dynamic> form) =>
    cacheWrite('nd_local_draft_$_bid', {'intent': intent, 'form': form});

Future<void> clearLocalDraft() async {
  try {
    await AppCache.remove('nd_local_draft_$_bid');
  } on Object {
    // nothing saved
  }
}
