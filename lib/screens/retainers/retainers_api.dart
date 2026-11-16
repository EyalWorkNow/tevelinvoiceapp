// "חבילת ריטיינר" API (server: apps/api/src/routes/v2/recurring.ts, BE-29).
// The server creates the month's DRAFTS on each template's day (Israel time);
// everything here is a person's action. "הפק הכל" is idempotent on the
// server (run row lock + a finalize key per run), so a retry is always safe.

import '../../api/client.dart';
import '../../api/documents_api.dart' show notifyDocumentsChanged;
import '../../api/issue_api.dart' show resolveScopeKey;
import '../../api/models/json.dart';

ApiClient get _api => ApiClient.instance;

class RetainerLine {
  const RetainerLine({
    required this.description,
    required this.quantityMicros,
    required this.unitPriceMinor,
    required this.discountMinor,
    required this.taxRateBasisPoints,
    this.itemId,
  });

  factory RetainerLine.fromJson(Map<String, dynamic> j) => RetainerLine(
    description: j['description'] as String? ?? '',
    quantityMicros: jBig(j['quantityMicros']),
    unitPriceMinor: jBig(j['unitPriceMinor']),
    discountMinor: jBig(j['discountMinor']),
    taxRateBasisPoints: jInt(j['taxRateBasisPoints'] ?? 0),
    itemId: jStr(j['itemId']),
  );

  final String description;
  final BigInt quantityMicros;
  final BigInt unitPriceMinor;
  final BigInt discountMinor;
  final int taxRateBasisPoints;
  final String? itemId;

  RetainerLine withPrice(BigInt price) => RetainerLine(
    description: description,
    quantityMicros: quantityMicros,
    unitPriceMinor: price,
    discountMinor: discountMinor,
    taxRateBasisPoints: taxRateBasisPoints,
    itemId: itemId,
  );

  Map<String, dynamic> toJson() => {
    'description': description,
    'quantityMicros': quantityMicros.toString(),
    'unitPriceMinor': unitPriceMinor.toString(),
    'discountMinor': discountMinor.toString(),
    'taxRateBasisPoints': taxRateBasisPoints,
    'itemId': ?itemId,
  };
}

class RetainerTemplate {
  const RetainerTemplate({
    required this.id,
    required this.customerName,
    required this.dayOfMonth,
    required this.status,
    required this.subtotalMinor,
    required this.lines,
    this.title,
    this.activeUntil,
    this.pendingFromPeriod,
    this.pendingLines,
  });

  factory RetainerTemplate.fromJson(Map<String, dynamic> j) => RetainerTemplate(
    id: j['id'] as String,
    customerName: j['customerName'] as String? ?? '',
    dayOfMonth: jInt(j['dayOfMonth']),
    status: j['status'] as String? ?? 'ACTIVE',
    subtotalMinor: jBig(j['subtotalMinor']),
    lines: [
      for (final l in (j['lines'] as List? ?? const []))
        RetainerLine.fromJson(l as Map<String, dynamic>),
    ],
    title: jStr(j['title']),
    activeUntil: jStr(j['activeUntil']),
    pendingFromPeriod: jStr(j['pendingFromPeriod']),
    pendingLines: j['pendingLines'] is List
        ? [
            for (final l in j['pendingLines'] as List)
              RetainerLine.fromJson(l as Map<String, dynamic>),
          ]
        : null,
  );

  final String id;
  final String customerName;
  final int dayOfMonth;
  final String status;
  final BigInt subtotalMinor;
  final List<RetainerLine> lines;
  final String? title;
  final String? activeUntil;
  final String? pendingFromPeriod;
  final List<RetainerLine>? pendingLines;
}

class RetainerRun {
  const RetainerRun({
    required this.runId,
    required this.templateId,
    required this.customerName,
    required this.status,
    required this.hints,
    required this.lineCount,
    this.title,
    this.documentId,
    this.documentNumber,
    this.totalMinor,
    this.subtotalMinor,
    this.errorCode,
  });

  factory RetainerRun.fromJson(Map<String, dynamic> j) => RetainerRun(
    runId: j['runId'] as String,
    templateId: j['templateId'] as String,
    customerName: j['customerName'] as String? ?? '',
    status: j['status'] as String? ?? 'DRAFTED',
    hints: jStrings(j['hints']),
    lineCount: jIntOrNull(j['lineCount']) ?? 0,
    title: jStr(j['title']),
    documentId: jStr(j['documentId']),
    documentNumber: jStr(j['documentNumber']),
    totalMinor: jBigOrNull(j['totalMinor']),
    subtotalMinor: jBigOrNull(j['subtotalMinor']),
    errorCode: jStr(j['errorCode']),
  );

  final String runId;
  final String templateId;
  final String customerName;
  final String status;
  final List<String> hints;
  final int lineCount;
  final String? title;
  final String? documentId;
  final String? documentNumber;
  final BigInt? totalMinor;
  final BigInt? subtotalMinor;
  final String? errorCode;

  bool get waiting => status == 'DRAFTED';
}

class RetainerMonth {
  const RetainerMonth({
    required this.period,
    required this.labelHe,
    required this.items,
    required this.pendingCount,
    required this.pendingTotalMinor,
  });

  factory RetainerMonth.fromJson(Map<String, dynamic> j) => RetainerMonth(
    period: j['period'] as String,
    labelHe: j['labelHe'] as String? ?? '',
    items: [
      for (final i in (j['items'] as List? ?? const []))
        RetainerRun.fromJson(i as Map<String, dynamic>),
    ],
    pendingCount: jIntOrNull(j['pendingCount']) ?? 0,
    pendingTotalMinor: jBig(j['pendingTotalMinor']),
  );

  final String period;
  final String labelHe;
  final List<RetainerRun> items;
  final int pendingCount;
  final BigInt pendingTotalMinor;
}

class RetainerIssueResult {
  const RetainerIssueResult({
    required this.issued,
    required this.submitted,
    required this.waitingAllocation,
    required this.failed,
    required this.signingLocked,
    required this.items,
  });

  factory RetainerIssueResult.fromJson(Map<String, dynamic> j) {
    final s = jMap(j['summary']);
    return RetainerIssueResult(
      issued: jIntOrNull(s['issued']) ?? 0,
      submitted: jIntOrNull(s['submitted']) ?? 0,
      waitingAllocation: jIntOrNull(s['waitingAllocation']) ?? 0,
      failed: jIntOrNull(s['failed']) ?? 0,
      signingLocked: jIntOrNull(s['signingLocked']) ?? 0,
      items: [
        for (final i in (j['items'] as List? ?? const []))
          i as Map<String, dynamic>,
      ],
    );
  }

  final int issued;
  final int submitted;
  final int waitingAllocation;
  final int failed;
  final int signingLocked;
  final List<Map<String, dynamic>> items;

  /// The first per-row error code (for the toast).
  String? get firstError {
    for (final i in items) {
      final c = i['errorCode'];
      if (c is String) return c;
    }
    return null;
  }
}

/// Israel civil month (YYYY-MM) of [now]: UTC+2 in winter, +3 in summer. The
/// server owns the real boundary; this only picks the screen's default month.
String currentPeriod([DateTime? now]) {
  final utc = (now ?? DateTime.now()).toUtc();
  final local = utc.add(Duration(hours: _israelSummer(utc) ? 3 : 2));
  return '${local.year}-${local.month.toString().padLeft(2, '0')}';
}

bool _israelSummer(DateTime utc) {
  // Last Friday before the last Sunday of March … last Sunday of October.
  DateTime lastSunday(int month) {
    var d = DateTime.utc(utc.year, month + 1, 0);
    while (d.weekday != DateTime.sunday) {
      d = d.subtract(const Duration(days: 1));
    }
    return d;
  }

  final start = lastSunday(3).subtract(const Duration(days: 2));
  final end = lastSunday(10);
  return !utc.isBefore(start) && utc.isBefore(end);
}

Future<RetainerMonth> fetchRetainerMonth(String period) async =>
    RetainerMonth.fromJson(await _api.get('/recurring/months/$period'));

Future<List<RetainerTemplate>> fetchRetainerTemplates() async {
  final json = await _api.get('/recurring/templates');
  return [
    for (final t in (json['templates'] as List? ?? const []))
      RetainerTemplate.fromJson(t as Map<String, dynamic>),
  ];
}

/// "הפוך לחשבונית חודשית". `created` false = it already existed.
Future<({RetainerTemplate template, bool created})> createRetainerTemplate({
  required String sourceDocumentId,
  required int dayOfMonth,
}) async {
  final json = await _api.post('/recurring/templates', {
    'sourceDocumentId': sourceDocumentId,
    'dayOfMonth': dayOfMonth,
  });
  return (
    template: RetainerTemplate.fromJson(jMap(json['template'])),
    created: json['created'] == true,
  );
}

Future<RetainerTemplate> updateRetainerTemplate(
  String id,
  Map<String, dynamic> patch,
) async => RetainerTemplate.fromJson(
  jMap((await _api.patch('/recurring/templates/$id', patch))['template']),
);

Future<void> setRetainerRunPrices(String runId, List<BigInt> prices) async {
  await _api.put('/recurring/runs/$runId/prices', {
    'unitPricesMinor': [for (final p in prices) p.toString()],
  });
  notifyDocumentsChanged();
}

Future<void> skipRetainerRun(String runId) async {
  await _api.post('/recurring/runs/$runId/skip');
  notifyDocumentsChanged();
}

Future<void> removeRetainerRun(String runId) async {
  await _api.post('/recurring/runs/$runId/remove');
  notifyDocumentsChanged();
}

/// "הפק הכל". Safe to call again (retry, after unlocking the signature).
Future<RetainerIssueResult> issueRetainerMonth(
  String period, {
  required bool send,
}) async {
  final scopeKey = await resolveScopeKey();
  try {
    return RetainerIssueResult.fromJson(
      await _api.post('/recurring/months/$period/issue', {
        'scopeKey': scopeKey,
        'send': send,
      }),
    );
  } finally {
    notifyDocumentsChanged();
  }
}

/// The draft's lines (for "ערוך סכום" on a multi-line draft).
Future<List<RetainerLine>> fetchDraftLines(String documentId) async {
  final json = await _api.get('/documents/$documentId');
  return [
    for (final l in (json['lines'] as List? ?? const []))
      RetainerLine(
        description:
            (l as Map<String, dynamic>)['description'] as String? ?? '',
        quantityMicros: BigInt.zero,
        unitPriceMinor: jBig(l['unit_price_minor'] ?? l['unitPriceMinor']),
        discountMinor: BigInt.zero,
        taxRateBasisPoints: 0,
      ),
  ];
}
