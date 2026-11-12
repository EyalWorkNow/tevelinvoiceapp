// Catalog items (squad D; squad B's S3 imports it). SPEC-v2 §3.4, §10:
// autocomplete in S3, "לשמור כפריט?" after a new line, long-press edit /
// archive (BE-15). V1: GET/POST /items. BE-15: GET /items?q=&includeArchived=,
// PATCH /items/:id, POST /items/:id/archive | /restore.

import '../state/cache.dart';
import '../state/session.dart';
import 'client.dart';
import 'models/models.dart';

final _api = ApiClient.instance;

String _key(String? bid) => 'items_$bid';

List<Item> _parse(Object? list) => [
  for (final i in (list as List? ?? const []))
    Item.fromJson(Map<String, dynamic>.from(i as Map)),
];

Future<List<Item>?> readCachedItems() async {
  try {
    final v = await AppCache.read(_key(session.business?.businessId));
    return v is List ? _parse(v) : null;
  } on Object {
    return null;
  }
}

/// GET /items (≤500 by name). Network failure → the cached list (or empty).
Future<List<Item>> fetchItems() async {
  final bid = session.business?.businessId;
  try {
    final json = await _api.get('/items');
    final raw = json['items'] as List? ?? const [];
    try {
      await AppCache.write(_key(bid), raw);
    } on Object {
      // best effort
    }
    return _parse(raw);
  } on ApiException catch (e) {
    if (!e.isNetwork) rethrow;
    return await readCachedItems() ?? const [];
  }
}

/// POST /items → the new item. [priceMinor] = default unit price (agorot).
Future<Item> createItem({
  required String name,
  BigInt? priceMinor,
  String itemType = 'SERVICE',
  String? unit,
}) async {
  final json = await _api.post('/items', {
    'name': name.trim(),
    'itemType': itemType,
    'unit': ?unit,
    // Required by the server (vBigintString); 0 = no default price.
    'defaultUnitPriceMinor': (priceMinor ?? BigInt.zero).toString(),
    'currency': 'ILS',
  });
  return Item(
    id: json['id'] as String,
    name: name.trim(),
    itemType: itemType,
    unit: unit,
    defaultUnitPriceMinor: priceMinor,
    currency: 'ILS',
    isActive: true,
  );
}

/// PATCH /items/:id (BE-15): {name?, defaultUnitPriceMinor?, unit?, itemType?}.
Future<void> updateItem(
  String id, {
  String? name,
  BigInt? priceMinor,
  String? unit,
}) async {
  final body = <String, Object?>{
    if (name != null) 'name': name.trim(),
    if (priceMinor != null) 'defaultUnitPriceMinor': priceMinor.toString(),
    'unit': ?unit,
  };
  if (body.isEmpty) return;
  await _api.patch('/items/$id', body);
}

/// POST /items/:id/archive (BE-15) — "השבת".
Future<void> archiveItem(String id) => _api.post('/items/$id/archive');

/// POST /items/:id/restore (BE-15).
Future<void> restoreItem(String id) => _api.post('/items/$id/restore');

// ---- pure helpers (tested) -------------------------------------------------

/// S3 autocomplete: active items whose name starts with [query] first, then
/// those containing it; at most [limit].
List<Item> itemSuggestions(
  Iterable<Item> items,
  String query, {
  int limit = 5,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final active = items.where((i) => i.isActive);
  final starts = [
    for (final i in active)
      if (i.name.toLowerCase().startsWith(q)) i,
  ];
  final contains = [
    for (final i in active)
      if (!i.name.toLowerCase().startsWith(q) &&
          i.name.toLowerCase().contains(q))
        i,
  ];
  return [...starts, ...contains].take(limit).toList();
}

/// "לשמור כפריט?" is offered for a line whose description is not already an
/// item (case/space-insensitive).
bool shouldOfferSaveAsItem(Iterable<Item> items, String description) {
  final d = description.trim().toLowerCase();
  if (d.isEmpty) return false;
  return !items.any((i) => i.name.trim().toLowerCase() == d);
}
