// Reports (R / R2) — squad E. SPEC-v2 §6.R, §11.
//
// P0: KPIs from GET /dashboard (current month: income, owed, overdue) and the
//     existing exports: POST /exports/accountant|excel {fromDate,toDate} →
//     {storageKey} → GET /exports/download?key= (bytes) → share sheet.
// P2 (BE-18): GET /reports/:kind?from=&to=[&format=pdf|csv|xlsx]. Until the
//     server has it, report cards stay hidden (F5): [reportsAvailable] probes
//     once per business and remembers the answer.

import 'dart:convert';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../state/session.dart';
import 'client.dart';
import 'models/models.dart';

final _api = ApiClient.instance;

Future<DashboardKpis> fetchDashboardKpis() async => DashboardKpis.fromJson(await _api.get('/dashboard'));

final Map<String, bool> _available = {};

/// True when the server serves BE-18 reports (probed with the income report).
Future<bool> reportsAvailable(ReportPeriod period) async {
  final business = session.business?.businessId ?? '';
  final known = _available[business];
  if (known != null) return known;
  try {
    await _api.get('/reports/income', query: {'from': period.fromIso, 'to': period.toIso});
    return _available[business] = true;
  } on ApiException catch (e) {
    if (e.status == 404) return _available[business] = false;
    rethrow;
  }
}

/// Test hook: forget the BE-18 probe results.
void resetReportsProbe() => _available.clear();

Future<ReportData> fetchReport(String kind, ReportPeriod period) async => ReportData.fromJson(
  await _api.get('/reports/$kind', query: {'from': period.fromIso, 'to': period.toIso}),
);

/// A file ready for the share sheet.
class ExportFile {
  const ExportFile(this.bytes, this.name, this.mimeType);

  final Uint8List bytes;
  final String name;
  final String mimeType;
}

/// BE-18 file of one report (pdf | csv | xlsx).
Future<ExportFile> fetchReportFile(String kind, ReportPeriod period, String format) async {
  final bytes = await _api.getBytes(
    '/reports/$kind',
    query: {'from': period.fromIso, 'to': period.toIso, 'format': format},
  );
  return ExportFile(bytes, '$kind-${period.fromIso}-${period.toIso}.$format', _mime(format));
}

/// [kind]: 'accountant' (ZIP: PDFs + expense files) | 'excel' (XLSX).
Future<ExportFile> exportPeriod(String kind, ReportPeriod period) async {
  final json = await _api.post('/exports/$kind', {'fromDate': period.fromIso, 'toDate': period.toIso});
  final key = json['storageKey'] as String;
  final bytes = await _api.getBytes('/exports/download', query: {'key': key});
  final name = key.split('/').last;
  return ExportFile(bytes, name, kind == 'excel' ? _mime('xlsx') : 'application/zip');
}

String _mime(String format) => switch (format) {
  'pdf' => 'application/pdf',
  'csv' => 'text/csv',
  'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'zip' => 'application/zip',
  _ => 'application/octet-stream',
};

/// Opens the system share sheet with a file. Tests replace it.
typedef FileSharer = Future<void> Function(ExportFile file, {String? subject, String? text});

FileSharer fileSharer = _shareFile;

Future<void> _shareFile(ExportFile file, {String? subject, String? text}) async {
  final dir = await getTemporaryDirectory();
  final path = '${dir.path}/${file.name}';
  await XFile.fromData(file.bytes, mimeType: file.mimeType, name: file.name).saveTo(path);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(path, mimeType: file.mimeType)],
      subject: subject,
      text: text,
    ),
  );
}

// ---- BE-18 send (P2) ------------------------------------------------------------

/// POST /reports/:kind/send {to, from, to-date} — the server e-mails the
/// report. False when the server has no send route (the caller shares the
/// file instead).
Future<bool> sendReportByEmail(String kind, ReportPeriod period, String to) async {
  try {
    await _api.post('/reports/$kind/send?from=${period.fromIso}&to=${period.toIso}', {
      'to': to,
      'from': period.fromIso,
      'toDate': period.toIso,
    });
    return true;
  } on ApiException catch (e) {
    if (e.status == 404 && e.code == 'NOT_FOUND') return false;
    rethrow;
  }
}

// ---- BE-11 תקבולים (accountant, P1) ----------------------------------------------

/// Report kind served by GET /payments (not BE-18).
const String paymentsReportKind = 'payments';

/// Max rows read for one period (server limit).
const int _ledgerLimit = 500;

/// The payments ledger of [period] as an R2 report: KPIs (total when the
/// whole period fits, count) + rows date · customer · method · receipt · amount.
Future<ReportData> fetchPaymentsLedger(ReportPeriod period, {String Function(String)? methodLabel}) async {
  final json = await _api.get(
    '/payments',
    query: {'from': period.fromIso, 'to': period.toIso, 'limit': '$_ledgerLimit'},
  );
  final list = (json['payments'] as List? ?? const []).cast<Map<String, dynamic>>();
  final total = (json['total'] as num?)?.toInt() ?? list.length;
  var sum = BigInt.zero;
  final rows = <Map<String, dynamic>>[];
  for (final p in list) {
    final amount = BigInt.tryParse('${p['amountMinor']}') ?? BigInt.zero;
    sum += amount;
    final method = '${p['method'] ?? ''}';
    rows.add({
      'date': _ddmm('${p['paymentDate'] ?? ''}'),
      'customer': p['customerName'] ?? '',
      'method': methodLabel == null ? method : methodLabel(method),
      'receipt': p['receiptDocumentNumber'] ?? '',
      'amount': '$amount',
    });
  }
  return ReportData(
    kpis: [
      if (total <= list.length) ReportKpi(label: 'סה״כ תקבולים', amountMinor: sum),
      ReportKpi(label: 'מספר תקבולים', text: '$total'),
    ],
    columns: const [
      ReportColumn(key: 'customer', label: 'לקוח'),
      ReportColumn(key: 'date', label: 'תאריך'),
      ReportColumn(key: 'method', label: 'אמצעי'),
      ReportColumn(key: 'receipt', label: 'קבלה'),
      ReportColumn(key: 'amount', label: 'סכום', money: true),
    ],
    rows: rows,
  );
}

String _ddmm(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : '${d.day}/${d.month}/${d.year}';
}

/// [data] as a CSV file (UTF-8 BOM so Excel reads Hebrew). Money columns in ₪.
ExportFile reportCsv(String kind, ReportPeriod period, ReportData data) {
  String cell(Object? v) {
    final s = '${v ?? ''}';
    return s.contains(RegExp('[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  String money(Object? v) {
    final m = BigInt.tryParse('$v') ?? BigInt.zero;
    final neg = m.isNegative;
    final a = m.abs();
    final s = '${a ~/ BigInt.from(100)}.${(a % BigInt.from(100)).toString().padLeft(2, '0')}';
    return neg ? '-$s' : s;
  }

  final b = StringBuffer('\uFEFF')..writeln(data.columns.map((c) => cell(c.label)).join(','));
  for (final r in data.rows) {
    b.writeln(data.columns.map((c) => c.money ? money(r[c.key]) : cell(r[c.key])).join(','));
  }
  return ExportFile(
    Uint8List.fromList(utf8.encode(b.toString())),
    '$kind-${period.fromIso}-${period.toIso}.csv',
    _mime('csv'),
  );
}

// ---- the accountant's "לטיפול" on R (§6.R) ----------------------------------------

/// Cards of GET /mobile/inbox (BE-05) that belong on the accountant's R:
/// expenses to review, approvals, allocation problems, continuity gaps.
/// Empty when the server has no inbox.
Future<List<InboxItem>> fetchAccountantInbox() async {
  const kinds = {
    InboxKind.expenseReview,
    InboxKind.approvalNeeded,
    InboxKind.allocationProblem,
    InboxKind.continuityGap,
  };
  try {
    final json = await _api.get('/mobile/inbox', query: {'limit': '10'});
    return [
      for (final c in (json['cards'] as List? ?? const []))
        if (InboxKind.fromWire((c as Map)['kind'] as String?) case final k? when kinds.contains(k))
          InboxItem.fromJson(c.cast<String, dynamic>()),
    ].take(3).toList();
  } on ApiException catch (e) {
    if (e.status == 404 && e.code == 'NOT_FOUND') return const [];
    rethrow;
  }
}
