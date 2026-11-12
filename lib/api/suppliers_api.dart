// Suppliers (squad D, SPEC-v2 §3.4, §6.P chip "ספקים", P2 supplier card, E).
// V1: GET/POST /suppliers. BE-16 (P2) adds GET/PATCH /suppliers/:id and
// archive; until then the card reads the list row and offers neither.

import '../state/cache.dart';
import '../state/session.dart';
import '../util/errors_he.dart';
import 'client.dart';
import 'customers_api.dart' show isMissingRoute;
import 'models/models.dart';

final _api = ApiClient.instance;

String _key(String? bid) => 'people_suppliers_$bid';

List<Supplier> _parse(Object? list) => [
  for (final s in (list as List? ?? const []))
    Supplier.fromJson(Map<String, dynamic>.from(s as Map)),
];

Future<List<Supplier>?> readCachedSuppliers() async {
  try {
    final v = await AppCache.read(_key(session.business?.businessId));
    return v is List ? _parse(v) : null;
  } on Object {
    return null;
  }
}

/// GET /suppliers (≤500, by name; archived included — filter [Supplier.isArchived]).
Future<List<Supplier>> fetchSuppliers() async {
  final bid = session.business?.businessId;
  final json = await _api.get('/suppliers');
  final raw = json['suppliers'] as List? ?? const [];
  try {
    await AppCache.write(_key(bid), raw);
  } on Object {
    // best effort
  }
  return _parse(raw);
}

/// The supplier card: [be16] when GET /suppliers/:id answered (the server
/// has BE-16, so edit and archive are offered).
typedef SupplierCard = ({Supplier supplier, bool be16});

/// GET /suppliers/:id (BE-16, `{supplier:{…}}`), else the list row.
/// Throws ApiException NOT_FOUND when it does not exist.
Future<SupplierCard> fetchSupplierCard(String id) async {
  try {
    final json = await _api.get('/suppliers/$id');
    final s = json['supplier'];
    if (s is Map)
      return (
        supplier: Supplier.fromJson(Map<String, dynamic>.from(s)),
        be16: true,
      );
  } on ApiException catch (e) {
    if (!isMissingRoute(e)) rethrow;
  }
  for (final s in await fetchSuppliers()) {
    if (s.id == id) return (supplier: s, be16: false);
  }
  throw ApiException(
    404,
    'NOT_FOUND',
    errorMessageHe('NOT_FOUND', status: 404),
  );
}

Future<Supplier> fetchSupplier(String id) async =>
    (await fetchSupplierCard(id)).supplier;

/// PATCH /suppliers/:id with only the changed fields (BE-16; null clears).
Future<void> updateSupplier(String id, Map<String, Object?> changes) async {
  if (changes.isEmpty) return;
  await _api.patch('/suppliers/$id', changes);
}

/// POST /suppliers/:id/archive (BE-16).
Future<void> archiveSupplier(String id) async {
  await _api.post('/suppliers/$id/archive');
}

/// POST /suppliers (needs expense:record) → the new supplier.
Future<Supplier> createSupplier({
  required String name,
  String? taxId,
  String? phone,
  String? email,
}) async {
  final json = await _api.post('/suppliers', {
    'name': name,
    'taxId': taxId,
    'phone': phone,
    'email': email,
  });
  return Supplier(
    id: json['id'] as String,
    name: name,
    taxId: taxId,
    phone: phone,
    email: email,
  );
}
