// R2 · one report (same template as R) (SPEC-v2 §6.R): period → 2–4 KPIs →
// table (≤20 rows + "הצג הכל") → "שלח לרו״ח" (owner) / "שתף" (accountant)
// → ⋯ PDF · CSV · Excel. Needs BE-18; without it the page says the report is
// not in the app yet. Owner: squad E.
// "payments" (תקבולים, P1, BE-11): KPIs + CSV from GET /payments, rows by
// squad C's PaymentsLedger (tap → D, ⋯ "בטל תשלום"). The owner's "שלח לרו״ח" uses POST
// /reports/:kind/send when the server has it (P2), else the share sheet.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../api/models/models.dart';
import '../../api/reports_api.dart';
import '../../state/business_context.dart';
import '../../state/session.dart';
import '../../ui/ds.dart';
import '../../util/labels/labels.dart';
import '../document/payments_ledger.dart' show PaymentsLedger;
import 'reports_screen.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

class ReportView extends StatefulWidget {
  const ReportView({super.key, required this.kind, required this.period});

  final String kind;
  final PeriodKey period;

  @override
  State<ReportView> createState() => _ReportViewState();
}

class _ReportViewState extends State<ReportView> {
  late PeriodKey _key = widget.period;
  ReportData? _data;
  bool _missing = false;
  Object? _error;
  bool _showAll = false;
  bool _sharing = false;

  ReportPeriod get _period => periodFor(_key);

  bool get _ledger => widget.kind == paymentsReportKind;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _data = null;
      _error = null;
      _missing = false;
    });
    try {
      final data = _ledger
          ? await fetchPaymentsLedger(_period, methodLabel: paymentMethodLabel)
          : await fetchReport(widget.kind, _period);
      if (mounted) setState(() => _data = data);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => e.status == 404 ? _missing = true : _error = e);
    }
  }

  Future<void> _share(String format) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final data = _data;
      final file = _ledger && data != null
          ? reportCsv(widget.kind, _period, data)
          : await fetchReportFile(widget.kind, _period, format);
      await shareWithAccountant(file, _period);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Owner: the server e-mails the report to the accountant (P2); without
  /// the route or an accountant e-mail → the share sheet.
  Future<void> _sendToAccountant() async {
    final to = session.profile?.accountantEmail;
    if (to == null || _sharing) return _share('pdf');
    setState(() => _sharing = true);
    var sent = false;
    try {
      sent = await sendReportByEmail(widget.kind, _period, to);
      if (sent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ReportsHe.sentToAccountant(to))));
      }
    } on Object catch (e) {
      sent = true; // the error is shown; do not open the share sheet too
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
    if (!sent) await _share('pdf');
  }

  @override
  Widget build(BuildContext context) {
    final title = ReportsHe.kinds[widget.kind] ?? ReportsHe.title;
    final data = _data;
    final accountant = businessContext.caps.homeIsReports;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (data != null)
            MoreMenu(
              items: [
                if (!_ledger) MoreMenuItem(label: ReportsHe.pdf, onSelected: () => _share('pdf')),
                MoreMenuItem(label: ReportsHe.csv, onSelected: () => _share('csv')),
                if (!_ledger) MoreMenuItem(label: ReportsHe.exportExcel, onSelected: () => _share('xlsx')),
              ],
            ),
        ],
      ),
      body: SafeArea(
        bottom: data == null,
        child: Column(
          children: [
            OfflineBanner(visible: session.offline),
            Expanded(child: _body(context, data)),
          ],
        ),
      ),
      bottomNavigationBar: data == null
          ? null
          : BottomActionArea(
              child: PrimaryButton(
                key: const Key('report-share'),
                label: accountant ? ReportsHe.share : ReportsHe.sendToAccountant,
                loadingText: _sharing ? ReportsHe.preparing : null,
                offline: session.offline,
                onPressed: accountant || _ledger ? () => _share(_ledger ? 'csv' : 'pdf') : _sendToAccountant,
              ),
            ),
    );
  }

  Widget _body(BuildContext context, ReportData? data) {
    if (_missing) {
      return const EmptyState(icon: Iconsax.status_up, title: ReportsHe.notAvailable);
    }
    if (_error != null) return ErrorView(error: _error!, onRetry: _load);
    final p = context.palette;
    final rows = data == null
        ? const <Map<String, dynamic>>[]
        : (_showAll ? data.rows : data.rows.take(20).toList());
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.page, Space.s, Space.page, Space.xl),
      children: [
        PeriodChips(
          selected: _key,
          onSelected: (k) {
            setState(() => _key = k);
            unawaited(_load());
          },
        ),
        const SizedBox(height: Space.l),
        if (data == null)
          const SizedBox(height: 320, child: SkeletonList(rows: 4))
        else ...[
          Wrap(
            spacing: Space.m,
            runSpacing: Space.m,
            children: [
              for (final k in data.kpis.take(4))
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(k.label, style: AppText.secondary.copyWith(color: p.muted)),
                      if (k.amountMinor != null)
                        AmountText(k.amountMinor!)
                      else
                        Text(k.text ?? '', style: AppText.headline),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.section),
          // תקבולים: squad C's ledger body (tap → D, ⋯ "בטל תשלום", paging).
          if (_ledger)
            PaymentsLedger(key: ValueKey(_period.fromIso), from: _period.fromIso, to: _period.toIso)
          else if (data.rows.isEmpty)
            Text(ReportsHe.emptyRows, style: AppText.body.copyWith(color: p.muted))
          else
            for (final r in rows) _row(context, data.columns, r),
          if (!_ledger && !_showAll && data.rows.length > 20)
            TextButton(
              key: const Key('report-show-all'),
              onPressed: () => setState(() => _showAll = true),
              child: const Text(ReportsHe.showAll),
            ),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, List<ReportColumn> columns, Map<String, dynamic> row) {
    final p = context.palette;
    final first = columns.isEmpty ? null : columns.first;
    final money = [
      for (final c in columns.skip(1))
        if (c.money) c,
    ];
    final other = [
      for (final c in columns.skip(1))
        if (!c.money) c,
    ];
    return Container(
      constraints: const BoxConstraints(minHeight: Hit.row),
      padding: const EdgeInsets.symmetric(vertical: Space.s),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.line)),
      ),
      // The last money column (the row's total) sits beside the label and may
      // shrink; the others wrap underneath with their labels. Never a row of
      // natural-width amounts: 3+ of them overflow a phone (STATUS-v2 §8 #4).
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(first == null ? '' : '${row[first.key] ?? ''}', style: AppText.body),
              ),
              if (money.isNotEmpty) ...[
                const SizedBox(width: Space.m),
                Flexible(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: AmountText(jBig(row[money.last.key])),
                  ),
                ),
              ],
            ],
          ),
          if (other.isNotEmpty)
            Text(
              other.map((c) => '${c.label}: ${row[c.key] ?? ''}').join(' · '),
              style: AppText.secondary.copyWith(color: p.muted),
            ),
          if (money.length > 1)
            Wrap(
              spacing: Space.m,
              runSpacing: Space.xs,
              children: [
                for (final c in money.take(money.length - 1))
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text('${c.label}:', style: AppText.secondary.copyWith(color: p.muted)),
                      ),
                      const SizedBox(width: Space.xs),
                      Flexible(
                        child: AmountText(
                          jBig(row[c.key]),
                          style: AppText.secondary,
                          color: p.muted,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
