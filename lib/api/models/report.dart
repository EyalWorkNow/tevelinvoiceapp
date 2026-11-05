// Reports (R / R2) — squad E. §6.R, §11.
// P0: KPIs from GET /dashboard + the accountant export. BE-18 (P2):
// GET /reports/:kind?from=&to= → {kpis, rows, columns}.

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
  static ReportPeriod of(PeriodKey key, {String? vatReporting, bool exempt = false, DateTime? now}) {
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
  static PeriodKey parse(String? v) =>
      PeriodKey.values.firstWhere((k) => k.name == v, orElse: () => PeriodKey.current);

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
  const DashboardKpis({required this.monthIncome, required this.unpaidTotal, required this.overdueTotal});

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
    final v = json['valueMinor'] ?? json['amountMinor'] ?? (json['type'] == 'money' ? json['value'] : null);
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
  const ReportColumn({required this.key, required this.label, this.money = false});

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
  const ReportData({this.kpis = const [], this.columns = const [], this.rows = const []});

  factory ReportData.fromJson(Map<String, dynamic> json) => ReportData(
    kpis: [
      for (final k in (json['kpis'] as List? ?? const [])) ReportKpi.fromJson(k as Map<String, dynamic>),
    ],
    columns: [
      for (final c in (json['columns'] as List? ?? const []))
        ReportColumn.fromJson(c as Map<String, dynamic>),
    ],
    rows: [for (final r in (json['rows'] as List? ?? const [])) jMap(r)],
  );

  final List<ReportKpi> kpis;
  final List<ReportColumn> columns;
  final List<Map<String, dynamic>> rows;

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
