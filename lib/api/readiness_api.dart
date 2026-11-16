// C6 · "מוכן לרו״ח" + "בקש תיקון/זיכוי" (QA 2026-11-16, persona 06).
//
//   GET  /reports/readiness?from=&to=  (or ?period=current)  → [Readiness]
//   POST /documents/:id/correction-requests {reason, amountMinor?}
//   POST /correction-requests/:id/dismiss {note?}
//
// A server without the endpoint (404) or with another shape → null: the card
// stays hidden (F5, never "בקרוב").

import 'client.dart';
import 'models/json.dart';
import 'models/models.dart' show ReportPeriod;

final _api = ApiClient.instance;

enum ReadinessStatus { ok, warn, fail }

/// Where the app opens to fix an item (server `target.screen`).
enum ReadinessScreen {
  report,
  payments,
  inboxList,
  allocationScan,
  expenses,
  document,
  unknown,
}

ReadinessScreen _screen(String? s) => switch (s) {
  'REPORT' => ReadinessScreen.report,
  'PAYMENTS' => ReadinessScreen.payments,
  'INBOX_LIST' => ReadinessScreen.inboxList,
  'ALLOCATION_SCAN' => ReadinessScreen.allocationScan,
  'EXPENSES' => ReadinessScreen.expenses,
  'DOCUMENT' => ReadinessScreen.document,
  _ => ReadinessScreen.unknown,
};

class ReadinessItem {
  const ReadinessItem({
    required this.key,
    required this.status,
    required this.count,
    required this.weight,
    required this.title,
    this.hint = '',
    this.amountMinor,
    this.ids = const [],
    this.screen = ReadinessScreen.unknown,
    this.ref,
  });

  factory ReadinessItem.fromJson(Map<String, dynamic> j) {
    final t = jMap(j['target']);
    return ReadinessItem(
      key: jStr(j['key']) ?? '',
      status: switch (jStr(j['status'])) {
        'fail' => ReadinessStatus.fail,
        'warn' => ReadinessStatus.warn,
        _ => ReadinessStatus.ok,
      },
      count: jIntOrNull(j['count']) ?? 0,
      weight: jIntOrNull(j['weight']) ?? 0,
      title: jStr(j['titleHe']) ?? '',
      hint: jStr(j['hintHe']) ?? '',
      amountMinor: jBigOrNull(j['amountMinor']),
      ids: jStrings(j['ids']),
      screen: _screen(jStr(t['screen'])),
      ref: jStr(t['ref']),
    );
  }

  /// NUMBERING | PAYMENTS_WITHOUT_RECEIPT | TAX_INVOICE_DUE | ALLOCATION |
  /// EXPENSES | VAT_WARNINGS | CORRECTIONS | CREDIT_REASON.
  final String key;
  final ReadinessStatus status;
  final int count;
  final int weight;
  final String title;
  final String hint;
  final BigInt? amountMinor;
  final List<String> ids;
  final ReadinessScreen screen;
  final String? ref;

  bool get open => status != ReadinessStatus.ok;
}

class Readiness {
  const Readiness({
    required this.score,
    required this.ready,
    required this.threshold,
    required this.items,
    this.from,
    this.to,
  });

  /// Null when [j] is not a readiness body (an old server's /reports/:kind).
  static Readiness? tryParse(Map<String, dynamic> j) {
    final score = j['score'];
    final items = j['items'];
    if (score is! num || items is! List) return null;
    return Readiness(
      score: score.round().clamp(0, 100),
      ready: j['ready'] == true,
      threshold: jIntOrNull(j['readyThreshold']) ?? 90,
      from: jStr(j['from']),
      to: jStr(j['to']),
      items: [
        for (final i in items)
          if (i is Map<String, dynamic>) ReadinessItem.fromJson(i),
      ],
    );
  }

  final int score;
  final bool ready;
  final int threshold;
  final List<ReadinessItem> items;
  final String? from;
  final String? to;

  /// Not ok, most severe first (fail, then warn; heavier first).
  List<ReadinessItem> get open {
    final list = [
      for (final i in items)
        if (i.open) i,
    ];
    list.sort((a, b) {
      final s = b.status.index.compareTo(a.status.index);
      return s != 0 ? s : b.weight.compareTo(a.weight);
    });
    return list;
  }

  List<ReadinessItem> get passed => [
    for (final i in items)
      if (!i.open) i,
  ];
}

/// The readiness of [period] for the selected business; null = not served.
Future<Readiness?> fetchReadiness(ReportPeriod period) async {
  try {
    return Readiness.tryParse(
      await _api.get(
        '/reports/readiness',
        query: {'from': period.fromIso, 'to': period.toIso},
      ),
    );
  } on ApiException catch (e) {
    if (e.status == 404 || e.code == 'REPORT_NOT_FOUND') return null;
    rethrow;
  }
}

/// The current VAT period of [businessId] (its own cadence, server side) —
/// the accountant's board, without switching business.
Future<Readiness?> fetchReadinessFor(String businessId) async {
  try {
    return Readiness.tryParse(
      await _api.getForBusiness(
        businessId,
        '/reports/readiness',
        query: {'period': 'current'},
      ),
    );
  } on ApiException catch (e) {
    if (e.status == 404 || e.status == 403 || e.code == 'REPORT_NOT_FOUND') {
      return null;
    }
    rethrow;
  }
}

/// "בקש תיקון/זיכוי": [amountMinor] null = the owner decides (full credit).
Future<void> requestCorrection(
  String documentId, {
  required String reason,
  BigInt? amountMinor,
}) => _api.post('/documents/$documentId/correction-requests', {
  'reason': reason,
  if (amountMinor != null) 'amountMinor': amountMinor.toString(),
});

/// The owner closes the request without a correction.
Future<void> dismissCorrection(String requestId, {String? note}) => _api.post(
  '/correction-requests/$requestId/dismiss',
  {if (note != null && note.trim().isNotEmpty) 'note': note.trim()},
);
