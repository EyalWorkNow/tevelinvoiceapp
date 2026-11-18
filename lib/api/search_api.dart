// Home search (tester feedback 2026-11-18): GET /mobile/search?q= — customers,
// documents, quotes and documents sent for signature in one call. The server
// understands plain Hebrew ("הצעת מחיר של כהן", "בקשת תשלום 12", "קבלה 450").

import 'client.dart';
import 'models/models.dart' show jStr, jBigOrNull;

enum SearchHitKind { customer, document, quote, signRequest }

class SearchHit {
  const SearchHit({
    required this.kind,
    required this.id,
    this.name,
    this.documentType,
    this.number,
    this.status,
    this.totalMinor,
    this.openMinor,
    this.title,
    this.date,
  });

  static SearchHit? fromJson(Map<String, dynamic> j) {
    final kind = switch (j['kind']) {
      'customer' => SearchHitKind.customer,
      'document' => SearchHitKind.document,
      'quote' => SearchHitKind.quote,
      'signRequest' => SearchHitKind.signRequest,
      _ => null,
    };
    final id = j['id'];
    if (kind == null || id is! String) return null;
    return SearchHit(
      kind: kind,
      id: id,
      name: jStr(j['name']),
      documentType: jStr(j['documentType']),
      number: jStr(j['number']),
      status: jStr(j['status']),
      totalMinor: jBigOrNull(j['totalMinor']),
      openMinor: jBigOrNull(j['openMinor']),
      title: jStr(j['title']),
      date: jStr(j['date']),
    );
  }

  final SearchHitKind kind;
  final String id;
  final String? name;
  final String? documentType;
  final String? number;
  final String? status;

  /// Null when hidden (no money:read) or not a document.
  final BigInt? totalMinor;
  final BigInt? openMinor;

  /// Sign request title / customer phone.
  final String? title;
  final String? date;
}

Future<List<SearchHit>> globalSearch(String q) async {
  final json = await ApiClient.instance.get(
    '/mobile/search',
    query: {'q': q, 'limit': '20'},
  );
  return [
    for (final h in (json['hits'] as List? ?? const []))
      if (h is Map<String, dynamic>) ?SearchHit.fromJson(h),
  ];
}
