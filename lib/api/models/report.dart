// Reports (R / R2) — squad E. §6.R, §11.
// P0: KPIs from GET /dashboard + the accountant export. BE-18 (P2):
// GET /reports/:kind?from=&to= → {kpis, rows, columns}.

import '../../util/israel_date.dart' show israelTodayDate;
import 'json.dart';

/// The period chips of R (§6.R): current VAT period (exempt: the year),
/// the previous one, and the calendar year.
enum PeriodKey { current, previous, year }

class ReportPeriod {
  const ReportPeriod(this.key, this.from, this.to);

  final PeriodKey key;
  final DateTime from;

  /// Inclusive last day.
  final DateTime to;

  /// [vatReporting]: MONTHLY | BIMONTHLY | NONE | null; [exempt] = no VAT
  /// periods (פטור / עמותה) → the calendar year.
  static ReportPeriod of(
    PeriodKey key, {
    String? vatReporting,
    bool exempt = false,
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    if (key == PeriodKey.year || exempt || vatReporting == 'NONE') {
      final year = key == PeriodKey.previous ? n.year - 1 : n.year;
      return ReportPeriod(key, DateTime(year), DateTime(year, 12, 31));
    }
    final months = vatReporting == 'MONTHLY' ? 1 : 2;
    var startMonth = ((n.month - 1) ~/ months) * months + 1;
    var year = n.year;
    if (key == PeriodKey.previous) {
      startMonth -= months;
      if (startMonth < 1) {
        startMonth += 12;
        year -= 1;
      }
    }
    return ReportPeriod(
      key,
      DateTime(year, startMonth),
      DateTime(year, startMonth + months, 0),
    ); // day 0 = last day
  }

  /// URL value for /reports?period=.
  static PeriodKey parse(String? v) => PeriodKey.values.firstWhere(
    (k) => k.name == v,
    orElse: () => PeriodKey.current,
  );

  String get fromIso => _iso(from);
  String get toIso => _iso(to);

  /// '9–10.2026', '10.2026', '2026'. Plain digits: wrap in ltrIsolate() inside
  /// Hebrew text, or the range renders reversed ('10.2026–9').
  String get label {
    if (from.month == 1 && to.month == 12) return '${from.year}';
    if (from.month == to.month) return '${from.month}.${from.year}';
    return '${from.month}–${to.month}.${from.year}';
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// The part of GET /dashboard that R shows in P0 (BE-01 fields).
class DashboardKpis {
  const DashboardKpis({
    required this.monthIncome,
    required this.unpaidTotal,
    required this.overdueTotal,
  });

  factory DashboardKpis.fromJson(Map<String, dynamic> json) {
    final s = jMap(json['summary']);
    return DashboardKpis(
      monthIncome: jBig(s['month_income']),
      unpaidTotal: jBig(jPick(s, const ['unpaid_total', 'unpaid_balance'])),
      overdueTotal: jBig(s['overdue_total']),
    );
  }

  final BigInt monthIncome;
  final BigInt unpaidTotal;
  final BigInt overdueTotal;
}

/// One KPI of a BE-18 report. Money KPIs carry [amountMinor]; others [text].
class ReportKpi {
  const ReportKpi({required this.label, this.key, this.amountMinor, this.text});

  /// BE-18 sends {key, label, type: 'money', value}; older shapes
  /// {valueMinor | amountMinor}.
  factory ReportKpi.fromJson(Map<String, dynamic> json) {
    final v =
        json['valueMinor'] ??
        json['amountMinor'] ??
        (json['type'] == 'money' ? json['value'] : null);
    return ReportKpi(
      label: jStr(json['label']) ?? '',
      key: jStr(json['key']),
      amountMinor: v == null ? null : jBig(v),
      text: v == null ? jStr(json['value']) : null,
    );
  }

  final String label;

  /// Stable id ('totalMinor', 'netMinor', …) when the server sends one.
  final String? key;
  final BigInt? amountMinor;
  final String? text;
}

class ReportColumn {
  const ReportColumn({
    required this.key,
    required this.label,
    this.money = false,
  });

  factory ReportColumn.fromJson(Map<String, dynamic> json) => ReportColumn(
    key: jStr(json['key']) ?? '',
    label: jStr(json['label']) ?? '',
    money: json['type'] == 'money' || jBool(json['money']),
  );

  final String key;
  final String label;
  final bool money;
}

/// GET /reports/:kind (BE-18).
class ReportData {
  const ReportData({
    this.kpis = const [],
    this.columns = const [],
    this.rows = const [],
    this.warnings = const [],
    this.draft = false,
    this.notes = const [],
  });

  factory ReportData.fromJson(Map<String, dynamic> json) => ReportData(
    kpis: [
      for (final k in (json['kpis'] as List? ?? const []))
        ReportKpi.fromJson(k as Map<String, dynamic>),
    ],
    columns: [
      for (final c in (json['columns'] as List? ?? const []))
        ReportColumn.fromJson(c as Map<String, dynamic>),
    ],
    rows: [for (final r in (json['rows'] as List? ?? const [])) jMap(r)],
    warnings: jStrings(json['warnings']),
    draft: jBool(json['draft']),
    notes: jStrings(json['notes']),
  );

  final List<ReportKpi> kpis;
  final List<ReportColumn> columns;
  final List<Map<String, dynamic>> rows;

  /// A4: problems to read before trusting the figures (warning rows).
  final List<String> warnings;

  /// A4: the figures are a draft for the accountant (the VAT report).
  final bool draft;

  /// The server's explanation lines.
  final List<String> notes;

  /// Money KPI [key], else the first money KPI.
  BigInt? money(String key) {
    for (final k in kpis) {
      if (k.key == key && k.amountMinor != null) return k.amountMinor;
    }
    for (final k in kpis) {
      if (k.amountMinor != null) return k.amountMinor;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// C2 · "סיכום יום" — GET /reports/daily-summary?date= | from=&to=
// ---------------------------------------------------------------------------

/// The ranges of the daily summary: one Israel civil day, or this week.
/// (PeriodKey stays the VAT-period chips of R; a till closes per day.)
class DailyRange {
  const DailyRange(this.from, this.to);

  /// Today in Israel (the server's day boundaries), whatever the phone's zone.
  factory DailyRange.today([DateTime? now]) =>
      DailyRange.day(israelTodayDate(now));

  /// [day] alone (today by default).
  factory DailyRange.day(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return DailyRange(d, d);
  }

  /// Sunday (the Israeli week start) up to today in Israel at [now].
  factory DailyRange.week(DateTime now) {
    final today = israelTodayDate(now);
    // DateTime.weekday: Monday = 1 … Sunday = 7.
    final sunday = today.subtract(Duration(days: today.weekday % 7));
    return DailyRange(sunday, today);
  }

  final DateTime from;
  final DateTime to;

  bool get isDay => from == to;

  String get fromIso => _iso(from);
  String get toIso => _iso(to);

  Map<String, String> get query =>
      isDay ? {'date': fromIso} : {'from': fromIso, 'to': toIso};

  /// '16.11.2026' or '15–21.11.2026' (wrap in ltrIsolate() inside Hebrew).
  String get label {
    String d(DateTime x) => '${x.day}.${x.month}.${x.year}';
    if (isDay) return d(from);
    if (from.year == to.year && from.month == to.month) {
      return '${from.day}–${d(to)}';
    }
    return '${d(from)}–${d(to)}';
  }

  @override
  bool operator ==(Object other) =>
      other is DailyRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// One method bucket: CASH | CREDIT_CARD | CHECK | BANK_TRANSFER | BIT |
/// PAYBOX | OTHER (bit / PayBox = BANK_TRANSFER + wallet reference).
class DailyMethodTotal {
  const DailyMethodTotal({
    required this.method,
    required this.label,
    required this.count,
    required this.totalMinor,
  });

  factory DailyMethodTotal.fromJson(Map<String, dynamic> j) => DailyMethodTotal(
    method: jStr(j['method']) ?? 'OTHER',
    label: jStr(j['label']) ?? '',
    count: jIntOrNull(j['count']) ?? 0,
    totalMinor: jBig(j['totalMinor']),
  );

  final String method;
  final String label;
  final int count;
  final BigInt totalMinor;
}

/// One payment of the range (time in Israel; the receipt that covers it).
class DailyReceipt {
  const DailyReceipt({
    required this.paymentId,
    required this.day,
    required this.time,
    required this.method,
    required this.summaryMethod,
    required this.amountMinor,
    this.reference,
    this.documentId,
    this.documentType,
    this.documentNumber,
    this.customerName,
  });

  factory DailyReceipt.fromJson(Map<String, dynamic> j) => DailyReceipt(
    paymentId: jStr(j['paymentId']) ?? '',
    day: jStr(j['day']) ?? '',
    time: jStr(j['time']) ?? '',
    method: jStr(j['method']) ?? 'OTHER',
    summaryMethod: jStr(j['summaryMethod']) ?? jStr(j['method']) ?? 'OTHER',
    amountMinor: jBig(j['amountMinor']),
    reference: jStr(j['reference']),
    documentId: jStr(j['documentId']),
    documentType: jStr(j['documentType']),
    documentNumber: jStr(j['documentNumber']),
    customerName: jStr(j['customerName']),
  );

  final String paymentId;
  final String day;
  final String time;
  final String method;

  /// The bucket (BIT / PAYBOX for a wallet transfer).
  final String summaryMethod;
  final BigInt amountMinor;
  final String? reference;
  final String? documentId;
  final String? documentType;
  final String? documentNumber;
  final String? customerName;
}

/// FIXB (tester 2026-11-18): one type of document issued in the range.
class DailyIssuedType {
  const DailyIssuedType({
    required this.documentType,
    required this.label,
    required this.count,
    required this.totalMinor,
  });

  factory DailyIssuedType.fromJson(Map<String, dynamic> j) => DailyIssuedType(
    documentType: jStr(j['documentType']) ?? '',
    label: jStr(j['label']) ?? '',
    count: jIntOrNull(j['count']) ?? 0,
    totalMinor: jBig(j['totalMinor']),
  );

  final String documentType;
  final String label;
  final int count;
  final BigInt totalMinor;
}

class DailySummary {
  const DailySummary({
    this.issued,
    this.issuedCount = 0,
    this.issuedOwnCount = 0,
    required this.from,
    required this.to,
    required this.restricted,
    required this.count,
    required this.ownCount,
    this.totalMinor,
    this.byMethod = const [],
    this.receipts = const [],
    this.truncated = false,
  });

  factory DailySummary.fromJson(Map<String, dynamic> j) => DailySummary(
    from: jStr(j['from']) ?? '',
    to: jStr(j['to']) ?? '',
    restricted: jBool(j['restricted']),
    count: jIntOrNull(j['count']) ?? 0,
    ownCount: jIntOrNull(j['ownCount']) ?? 0,
    totalMinor: jBigOrNull(j['totalMinor']),
    byMethod: [
      for (final m in (j['byMethod'] as List? ?? const []))
        DailyMethodTotal.fromJson(jMap(m)),
    ],
    receipts: [
      for (final r in (j['receipts'] as List? ?? const []))
        DailyReceipt.fromJson(jMap(r)),
    ],
    truncated: jBool(j['truncated']),
    issued: j['issued'] is Map
        ? [
            for (final t in (jMap(j['issued'])['byType'] as List? ?? const []))
              DailyIssuedType.fromJson(jMap(t)),
          ]
        : null,
    issuedCount: j['issued'] is Map
        ? jIntOrNull(jMap(j['issued'])['count']) ?? 0
        : 0,
    issuedOwnCount: jIntOrNull(j['issuedOwnCount']) ?? 0,
  );

  /// Documents issued in the range, by type (null: restricted, or a server
  /// before FIXB).
  final List<DailyIssuedType>? issued;
  final int issuedCount;

  /// Documents the caller issued in the range.
  final int issuedOwnCount;

  final String from;
  final String to;

  /// No money:read (employee / cashier): only [ownCount], no amounts.
  final bool restricted;
  final int count;
  final int ownCount;
  final BigInt? totalMinor;
  final List<DailyMethodTotal> byMethod;
  final List<DailyReceipt> receipts;
  final bool truncated;
}
