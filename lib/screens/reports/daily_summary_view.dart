// C2 · "סיכום יום" (Z-style). GET /reports/daily-summary: today by default,
// "השבוע" (Sunday → today) or a picked day. Totals by method (cash, card,
// cheque, transfer, bit, PayBox, other), the count and the day's receipts;
// "שלח בוואטסאפ" (text to the owner / accountant) and PDF (server render).
// Without money:read (employee / cashier) the server sends only the count of
// the caller's own receipts, and that is all this page shows.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/models/models.dart';
import '../../api/reports_api.dart';
import '../../router.dart' show openDocument;
import '../../state/business_context.dart';
import '../../state/session.dart';
import '../../ui/ds.dart';
import '../../util/allowed_urls.dart' show launchAllowed;
import '../../util/labels/labels.dart';
import '../../util/money.dart' show formatMoney;
import '../../util/phone.dart' show whatsAppUri;
import '../../util/still_here.dart';

enum _RangeKind { today, week, picked }

class DailySummaryView extends StatefulWidget {
  const DailySummaryView({super.key, this.now});

  /// Test hook: "today".
  final DateTime? now;

  @override
  State<DailySummaryView> createState() => _DailySummaryViewState();
}

class _DailySummaryViewState extends State<DailySummaryView> {
  DateTime get _now => widget.now ?? DateTime.now();
  _RangeKind _kind = _RangeKind.today;
  // The Israel civil day (the server's boundaries), not the phone's zone.
  late DailyRange _range = DailyRange.today(_now);
  DailySummary? _data;
  Object? _error;
  bool _loading = true;
  bool _pdf = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await fetchDailySummary(_range);
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _select(_RangeKind kind) async {
    if (kind == _RangeKind.picked) {
      final today = DailyRange.today(_now).to;
      final picked = await showDatePicker(
        context: context,
        firstDate: today.subtract(const Duration(days: 366 * 2)),
        lastDate: today,
        initialDate: _range.to.isAfter(today) ? today : _range.to,
      );
      if (picked == null || !mounted) return;
      _range = DailyRange.day(picked);
    } else {
      _range = kind == _RangeKind.week
          ? DailyRange.week(_now)
          : DailyRange.today(_now);
    }
    setState(() => _kind = kind);
    await _load();
  }

  String get _shareText {
    final d = _data!;
    return DailySummaryHe.shareText(
      businessName: businessContext.displayName,
      rangeLabel: _range.label,
      isDay: _range.isDay,
      totalMinor: d.totalMinor ?? BigInt.zero,
      count: d.count,
      methods: [
        for (final m in d.byMethod)
          (label: m.label, count: m.count, totalMinor: m.totalMinor),
      ],
    );
  }

  Future<void> _whatsApp() async {
    try {
      await launchAllowed(whatsAppUri(text: _shareText));
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _sharePdf() async {
    if (_pdf) return;
    setState(() => _pdf = true);
    try {
      final file = await fetchDailySummaryPdf(_range);
      // Late navigation: left (or leaving) while the PDF was made.
      if (!mounted || !stillHere(context)) return;
      await fileSharer(
        file,
        subject: '${DailySummaryHe.title} · ${businessContext.displayName}',
      );
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _pdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final money = d != null && !d.restricted;
    return Scaffold(
      appBar: AppBar(title: const Text(DailySummaryHe.title)),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            OfflineBanner(visible: session.offline),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    Space.page,
                    Space.s,
                    Space.page,
                    MediaQuery.paddingOf(context).bottom + Space.xl,
                  ),
                  children: [
                    ChipRow<_RangeKind>(
                      key: const Key('daily-range'),
                      padding: EdgeInsets.zero,
                      options: [
                        const ChipOption(
                          _RangeKind.today,
                          DailySummaryHe.today,
                        ),
                        const ChipOption(_RangeKind.week, DailySummaryHe.week),
                        ChipOption(
                          _RangeKind.picked,
                          _kind == _RangeKind.picked
                              ? _range.label
                              : DailySummaryHe.pickDay,
                        ),
                      ],
                      selected: _kind,
                      onSelected: (k) => unawaited(_select(k)),
                    ),
                    const SizedBox(height: Space.s),
                    Text(
                      ltrIsolate(_range.label),
                      key: const Key('daily-range-label'),
                      style: AppText.secondary,
                    ),
                    const SizedBox(height: Space.m),
                    if (_error != null)
                      SizedBox(
                        height: 320,
                        child: ErrorView(error: _error!, onRetry: _load),
                      )
                    else if (_loading || d == null)
                      const SizedBox(height: 320, child: SkeletonList(rows: 4))
                    else if (d.restricted)
                      ..._restricted(context, d)
                    else
                      ..._full(context, d),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: money && d.count > 0 && _error == null
          ? BottomActionArea(
              child: Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      key: const Key('daily-whatsapp'),
                      label: DailySummaryHe.shareWhatsApp,
                      onPressed: _whatsApp,
                    ),
                  ),
                  const SizedBox(width: Space.s),
                  OutlinedButton.icon(
                    key: const Key('daily-pdf'),
                    onPressed: session.offline || _pdf ? null : _sharePdf,
                    icon: const Icon(Iconsax.document_download, size: 19),
                    label: Text(
                      _pdf ? DailySummaryHe.preparing : DailySummaryHe.pdf,
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(96, 52),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  List<Widget> _restricted(BuildContext context, DailySummary d) => [
    AppCard(
      key: const Key('daily-own-count'),
      child: Text(DailySummaryHe.ownCount(d.ownCount), style: AppText.title),
    ),
    if (d.issuedOwnCount > 0) ...[
      const SizedBox(height: Space.s),
      Text(
        DailySummaryHe.issuedOwn(d.issuedOwnCount),
        key: const Key('daily-issued-own'),
        style: AppText.body,
      ),
    ],
    const SizedBox(height: Space.s),
    Text(
      DailySummaryHe.restrictedNote,
      style: AppText.secondary.copyWith(color: context.palette.muted),
    ),
  ];

  /// FIXB: what was ISSUED in the range next to what came in (a day of unpaid
  /// invoices used to read as "₪0 — the summary does not work").
  List<Widget> _issued(
    BuildContext context,
    List<DailyIssuedType> types,
    int count,
  ) {
    final p = context.palette;
    return [
      const SizedBox(height: Space.l),
      Semantics(
        header: true,
        child: Text(
          _range.isDay
              ? DailySummaryHe.issuedToday
              : DailySummaryHe.issuedRange,
          style: AppText.headline,
        ),
      ),
      const SizedBox(height: Space.s),
      AppCard(
        key: const Key('daily-issued'),
        child: types.isEmpty
            ? SizedBox(
                height: Hit.row,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    DailySummaryHe.issuedNone,
                    style: AppText.body.copyWith(color: p.muted),
                  ),
                ),
              )
            : Column(
                children: [
                  for (final t in types)
                    SizedBox(
                      key: Key('daily-issued-${t.documentType}'),
                      height: Hit.row,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${docTypeLabels[t.documentType] ?? t.label} (${t.count})',
                              style: AppText.body,
                            ),
                          ),
                          Text(
                            ltrIsolate(formatMoney(t.totalMinor)),
                            style: AppText.body.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
      if (count > 0) ...[
        const SizedBox(height: Space.xs),
        Text(
          DailySummaryHe.issuedCount(count),
          key: const Key('daily-issued-count'),
          style: AppText.secondary.copyWith(color: p.muted),
        ),
      ],
    ];
  }

  List<Widget> _full(BuildContext context, DailySummary d) {
    final p = context.palette;
    return [
      MoneyCard(
        key: const Key('daily-total'),
        label: _range.isDay
            ? DailySummaryHe.totalToday
            : DailySummaryHe.totalRange,
        amountMinor: d.totalMinor ?? BigInt.zero,
      ),
      const SizedBox(height: Space.xs),
      Text(
        DailySummaryHe.count(d.count),
        key: const Key('daily-count'),
        style: AppText.secondary,
      ),
      if (d.issued != null) ..._issued(context, d.issued!, d.issuedCount),
      const SizedBox(height: Space.l),
      Semantics(
        header: true,
        child: const Text(DailySummaryHe.byMethod, style: AppText.headline),
      ),
      const SizedBox(height: Space.s),
      AppCard(
        child: Column(
          children: [
            for (final m in d.byMethod)
              SizedBox(
                key: Key('daily-method-${m.method}'),
                height: Hit.row,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        m.count == 0 ? m.label : '${m.label} (${m.count})',
                        style: AppText.body.copyWith(
                          color: m.count == 0 ? p.muted : p.ink,
                        ),
                      ),
                    ),
                    Text(
                      ltrIsolate(formatMoney(m.totalMinor)),
                      style: AppText.body.copyWith(
                        color: m.count == 0 ? p.muted : p.ink,
                        fontWeight: m.count == 0 ? null : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: Space.l),
      Semantics(
        header: true,
        child: const Text(DailySummaryHe.receipts, style: AppText.headline),
      ),
      if (d.receipts.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.l),
          child: Text(
            DailySummaryHe.empty,
            key: const Key('daily-empty'),
            style: AppText.secondary.copyWith(color: p.muted),
          ),
        ),
      for (final r in d.receipts)
        ListTile(
          key: Key('daily-receipt-${r.paymentId}'),
          contentPadding: EdgeInsets.zero,
          minTileHeight: Hit.row,
          title: Text(
            [
              paymentMethodLabel(r.summaryMethod),
              if (r.customerName != null) r.customerName!,
            ].join(' · '),
            style: AppText.body,
          ),
          subtitle: Text(
            [
              if (!_range.isDay) formatDateHe(r.day),
              ltrIsolate(r.time),
              if (r.documentType != null)
                [
                  docTypeLabels[r.documentType] ?? '',
                  if (r.documentNumber != null) ltrIsolate(r.documentNumber!),
                ].join(' '),
            ].join(' · '),
            style: AppText.secondary.copyWith(color: p.muted),
          ),
          trailing: Text(
            ltrIsolate(formatMoney(r.amountMinor)),
            style: AppText.body.copyWith(fontWeight: FontWeight.w600),
          ),
          onTap: r.documentId == null
              ? null
              : () => openDocument(context, r.documentId!),
        ),
      if (d.truncated)
        Text(
          DailySummaryHe.truncated,
          style: AppText.secondary.copyWith(color: p.muted),
        ),
      const SizedBox(height: Space.m),
      Text(
        DailySummaryHe.timeZoneNote,
        style: AppText.secondary.copyWith(color: p.muted),
      ),
    ];
  }
}
