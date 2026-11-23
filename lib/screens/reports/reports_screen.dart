// R · דוחות + R2 (same template, [kind] set) (SPEC-v2 §6.R, §11). Owner: squad E.
// Routes: /reports?period=  and  /reports/:kind?period=
// Also the home tab of the accountant presets (embedded = true, no AppBar).
//
// P0: money card from GET /dashboard (this month) + "שלח לרו״ח" (accountant
// export → share sheet). Report cards appear only once the server serves
// BE-18 (F5: hidden, never "בקרוב").
// P1: the "תקבולים" card (BE-11 GET /payments, §3.3), the accountant's "לטיפול"
// (BE-05 inbox: expenses to review, approvals, allocation, continuity) and the
// "מבנה אחיד" row when /me.exports.uniformFormatReady (sent to the computer:
// the export needs a compliance decision id the app does not hold).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/widgets/notch_notice.dart';
import '../../api/client.dart' show ApiException;
import '../../api/models/models.dart';
import '../../api/reports_api.dart';
import '../../api/settings_api.dart' show sendWebHandoff;
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../state/session.dart';
import '../../ui/ds.dart';
import '../../util/labels/labels.dart';
import '../../router.dart';
import '../business/sheets/s14_switch.dart';
import '../home/inbox_cards.dart' show inboxCardFor;
import '../../util/allocation_meter.dart' show AllocationHe;
import 'allocation_scan_view.dart';
import 'daily_summary_view.dart';
import '../../api/readiness_api.dart';
import '../../api/accountant_api.dart'
    show
        PeriodReview,
        fetchPeriodReviews,
        markPeriodReviewed,
        periodKeyOf,
        unmarkPeriodReviewed;
import '../../state/accountant_store.dart' show accountantFocusTodo;
import 'clients_summary_row.dart';
import 'readiness_card.dart';
import 'report_view.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({
    super.key,
    this.period,
    this.kind,
    this.embedded = false,
  });

  final String? period;

  /// R2 report kind: income | vat | receivables | expenses | pnl | advances | …
  final String? kind;

  /// True when shown as the accountant's home tab.
  final bool embedded;

  @override
  Widget build(BuildContext context) => kind == allocationScanKind
      ? const AllocationScanView()
      : kind == dailySummaryKind
      ? const DailySummaryView()
      : kind != null
      ? ReportView(kind: kind!, period: ReportPeriod.parse(period))
      : _Reports(period: ReportPeriod.parse(period), embedded: embedded);
}

/// The period of [key] for the selected business (§6.R: VAT period; exempt: year).
ReportPeriod periodFor(PeriodKey key, {DateTime? now}) => ReportPeriod.of(
  key,
  vatReporting:
      businessContext.me?.vatReporting ??
      session.profile?.raw['vatReporting'] as String?,
  exempt: businessContext.isVatExempt,
  now: now,
);

/// Report cards each audience sees once BE-18 is live (§6.R, §11).
List<String> reportKinds(Caps caps, {required bool exempt}) =>
    caps.homeIsReports
    ? [
        'income',
        'expenses',
        if (!exempt) 'vat',
        'pnl',
        'advances',
        'receivables',
        'continuity', // A8: the server's numbering-gap check
      ]
    : ['income', if (!exempt) 'vat', 'receivables', 'continuity'];

class PeriodChips extends StatelessWidget {
  const PeriodChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final PeriodKey selected;
  final ValueChanged<PeriodKey> onSelected;

  @override
  Widget build(BuildContext context) {
    final exempt = businessContext.isVatExempt;
    return ChipRow<PeriodKey>(
      padding: EdgeInsets.zero,
      options: [
        ChipOption(
          PeriodKey.current,
          exempt ? ReportsHe.periodYear : ReportsHe.periodCurrent,
        ),
        ChipOption(PeriodKey.previous, ReportsHe.periodPrevious),
        if (!exempt) const ChipOption(PeriodKey.year, ReportsHe.periodYear),
      ],
      selected: selected,
      onSelected: onSelected,
    );
  }
}

/// Shares [file] with the accountant's e-mail in the text (§11 "שלח לרו״ח").
Future<void> shareWithAccountant(ExportFile file, ReportPeriod period) {
  final to = session.profile?.accountantEmail;
  return fileSharer(
    file,
    subject: ReportsHe.accountantSubject(
      businessContext.displayName,
      ltrIsolate(period.label),
    ),
    text: to,
  );
}

class _Reports extends StatefulWidget {
  const _Reports({required this.period, required this.embedded});

  final PeriodKey period;
  final bool embedded;

  @override
  State<_Reports> createState() => _ReportsState();
}

class _ReportsState extends State<_Reports> {
  late PeriodKey _key = widget.period;
  DashboardKpis? _kpis;

  /// Income of the selected period (BE-18 income report); null before BE-18.
  BigInt? _periodIncome;
  bool _cards = false;
  List<InboxItem> _todo = const [];

  /// C6 "מוכן לרו״ח" of the selected period (null = not served / no access).
  Readiness? _readiness;
  bool _loading = true;
  Object? _error;
  String? _exporting;

  /// Feature 6: reviewed periods (null = not served / not an accountant).
  List<PeriodReview>? _reviews;
  bool _reviewBusy = false;
  final GlobalKey _todoKey = GlobalKey();

  ReportPeriod get _period => periodFor(_key);

  /// 'YYYY-MM' of the period's first month; null for the year chip.
  String? get _reviewPeriod {
    final p = _period;
    final months = (p.to.year - p.from.year) * 12 + p.to.month - p.from.month;
    return months <= 1 ? periodKeyOf(p.from) : null;
  }

  /// "הכנסות החודש" only when the period is this one month; otherwise
  /// "הכנסות החודש בלבד (10.2026)" under '9–10.2026' / '2026'.
  String get _monthIncomeLabel {
    final p = _period;
    if (p.from.year == p.to.year && p.from.month == p.to.month) {
      return ReportsHe.monthIncome;
    }
    final now = DateTime.now();
    return ReportsHe.monthOnlyIncome(ltrIsolate('${now.month}.${now.year}'));
  }

  @override
  void initState() {
    super.initState();
    accountantFocusTodo.addListener(_focusTodo);
    unawaited(_load());
  }

  @override
  void dispose() {
    accountantFocusTodo.removeListener(_focusTodo);
    super.dispose();
  }

  /// A client row was tapped (S14): show "לטיפול" once R has loaded.
  void _focusTodo() {
    if (!accountantFocusTodo.value || _loading || !widget.embedded) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !accountantFocusTodo.value) return;
      accountantFocusTodo.value = false;
      final target = _todoKey.currentContext;
      if (target != null) {
        unawaited(
          Scrollable.ensureVisible(
            target,
            duration: context.motion(280),
            alignment: 0.05,
          ),
        );
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final caps = businessContext.caps;
      final results = await Future.wait<Object?>([
        caps.can(Cap.moneyView)
            ? fetchDashboardKpis()
            : Future<Object?>.value(),
        caps.can(Cap.reportView)
            ? reportsAvailable(_period)
            : Future<Object?>.value(false),
        widget.embedded
            ? _optionalInbox()
            : Future<Object?>.value(const <InboxItem>[]),
        caps.can(Cap.reportView)
            ? _optionalReadiness()
            : Future<Object?>.value(),
        caps.homeIsReports ? _optionalReviews() : Future<Object?>.value(),
      ]);
      final cards = results[1] as bool;
      // The headline follows the chip: income of the selected period (BE-18).
      // Without BE-18 only /dashboard's current month exists.
      BigInt? periodIncome;
      if (cards && caps.can(Cap.moneyView)) {
        try {
          periodIncome = (await fetchReport(
            'income',
            _period,
          )).money('totalMinor');
        } on ApiException {
          periodIncome = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _kpis = results[0] as DashboardKpis?;
        _periodIncome = periodIncome;
        _cards = cards;
        _todo = results[2] as List<InboxItem>;
        _readiness = results[3] as Readiness?;
        _reviews = results[4] as List<PeriodReview>?;
        _loading = false;
      });
      _focusTodo();
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  /// The inbox never blocks R: an error there just shows no cards.
  Future<List<InboxItem>> _optionalInbox() async {
    try {
      return await fetchAccountantInbox();
    } on Object {
      return const [];
    }
  }

  /// C6: the readiness card never blocks R either.
  Future<Readiness?> _optionalReadiness() async {
    try {
      return await fetchReadiness(_period);
    } on Object {
      return null;
    }
  }

  /// Feature 6: never blocks R either.
  Future<List<PeriodReview>?> _optionalReviews() async {
    try {
      return await fetchPeriodReviews();
    } on Object {
      return null;
    }
  }

  bool get _reviewed {
    final key = _reviewPeriod;
    return key != null && (_reviews ?? const []).any((r) => r.period == key);
  }

  Future<void> _toggleReviewed() async {
    final key = _reviewPeriod;
    final before = _reviews;
    if (key == null || before == null || _reviewBusy) return;
    final reviewed = _reviewed;
    setState(() => _reviewBusy = true);
    try {
      if (reviewed) {
        await unmarkPeriodReviewed(key);
      } else {
        await markPeriodReviewed(key);
      }
      if (!mounted) return;
      setState(
        () => _reviews = reviewed
            ? [
                for (final r in before)
                  if (r.period != key) r,
              ]
            : [
                PeriodReview(period: key, reviewedAt: DateTime.now()),
                ...before,
              ],
      );
      ScaffoldMessenger.of(context).showNotchNotice(
        SnackBar(
          content: Text(
            reviewed
                ? AccountantHe.reviewedRemoved
                : AccountantHe.reviewedSaved,
          ),
        ),
        motion: reviewed ? NoticeMotion.sent : NoticeMotion.saved,
      );
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _reviewBusy = false);
    }
  }

  Widget _reviewRow(BuildContext context) {
    final p = context.palette;
    final reviewed = _reviewed;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.m),
      child: Row(
        children: [
          if (reviewed) ...[
            Icon(Iconsax.tick_circle, color: p.ok, size: 20),
            const SizedBox(width: Space.xs),
            Text(
              AccountantHe.reviewed,
              key: const Key('period-reviewed'),
              style: AppText.body.copyWith(color: p.ok),
            ),
            const Spacer(),
            TextButton(
              key: const Key('period-unreview'),
              onPressed: session.offline || _reviewBusy
                  ? null
                  : () => unawaited(_toggleReviewed()),
              child: const Text(AccountantHe.unmarkReviewed),
            ),
          ] else
            OutlinedButton.icon(
              key: const Key('period-review'),
              onPressed: session.offline || _reviewBusy
                  ? null
                  : () => unawaited(_toggleReviewed()),
              icon: const Icon(Iconsax.tick_square, size: 18),
              label: const Text(AccountantHe.markReviewed),
            ),
        ],
      ),
    );
  }

  /// "שלח לרו״ח": below the readiness threshold only after an explicit confirm.
  Future<void> _sendToAccountant() async {
    if (!await confirmSendBelowThreshold(context, _readiness)) return;
    if (!mounted) return;
    await _export('accountant');
  }

  Future<void> _uniformFormat() async {
    try {
      await sendWebHandoff('UNIFORM_FORMAT', ReportsHe.uniformFormat);
      if (mounted) {
        ScaffoldMessenger.of(context).showNotchNotice(
          const SnackBar(content: Text(BusinessHe.desktopSent)),
          motion: NoticeMotion.sent,
        );
      }
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _export(String kind) async {
    if (_exporting != null) return;
    setState(() => _exporting = kind);
    final period = _period;
    final business = session.business?.businessId;
    try {
      final file = await exportPeriod(kind, period);
      if (!mounted ||
          ModalRoute.of(context)?.isCurrent != true ||
          business != session.business?.businessId) {
        return;
      }
      await shareWithAccountant(file, period);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final caps = businessContext.caps;
    final exempt = businessContext.isVatExempt;
    final rules = businessContext.me?.rules;
    final ceiling = rules?.exemptCeilingMinor;
    final owner = !caps.homeIsReports;
    final content = <Widget>[
      if (widget.embedded) ..._accountantHeader(context),
      PeriodChips(
        selected: _key,
        onSelected: (k) {
          setState(() => _key = k);
          unawaited(_load());
        },
      ),
      const SizedBox(height: Space.l),
      if (_error != null)
        SizedBox(
          height: 320,
          child: ErrorView(error: _error!, onRetry: _load),
        )
      else if (_loading)
        const SizedBox(height: 320, child: SkeletonList(rows: 3))
      else ...[
        // The period is shown once, LTR-isolated ('9–10.2026', not '10.2026–9').
        Text(
          ltrIsolate(_period.label),
          key: const Key('report-period'),
          style: AppText.secondary,
        ),
        const SizedBox(height: Space.s),
        if (_readiness != null) ...[
          ReadinessCard(
            readiness: _readiness!,
            period: _key.name,
            onChanged: () => unawaited(_load()),
          ),
          const SizedBox(height: Space.m),
        ],
        if (_reviews != null && _reviewPeriod != null) _reviewRow(context),
        if (_periodIncome != null)
          MoneyCard(
            key: const Key('period-income'),
            label: ReportsHe.periodIncome,
            amountMinor: _periodIncome!,
          )
        else if (_kpis != null && _key == PeriodKey.current)
          // No BE-18: /dashboard knows only this month, so only under "current";
          // a bi-monthly / yearly period names the month (the label follows the period).
          MoneyCard(
            key: const Key('month-income'),
            label: _monthIncomeLabel,
            amountMinor: _kpis!.monthIncome,
          ),
        // Owed is not overdue: no red (MoneyCard's secondary slot is the overdue colour).
        if (_kpis != null && owner && _kpis!.unpaidTotal > BigInt.zero) ...[
          const SizedBox(height: Space.s),
          Text(
            ReportsHe.owedLine(moneyInline(_kpis!.unpaidTotal)),
            key: const Key('owed-line'),
            style: AppText.secondary,
          ),
        ],
        if (exempt && ceiling != null) ...[
          const SizedBox(height: Space.m),
          Text(
            ReportsHe.exemptCeiling(
              moneyInline(rules?.yearTurnoverMinor ?? BigInt.zero),
              moneyInline(ceiling),
            ),
            key: const Key('exempt-ceiling'),
            style: AppText.body,
          ),
        ],
        if (_todo.isNotEmpty) ...[
          const SizedBox(height: Space.l),
          Semantics(
            key: _todoKey,
            header: true,
            child: const Text(ReportsHe.todo, style: AppText.headline),
          ),
          for (final c in _todo)
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: inboxCardFor(
                context,
                c,
                onChanged: () => unawaited(_load()),
              ),
            ),
        ],
        for (final k in [
          // C2: the till's day first (the salon's first question each evening).
          if (owner && caps.can(Cap.docView)) dailySummaryKind,
          if (_cards) ...reportKinds(caps, exempt: exempt),
          if (caps.can(Cap.docView))
            paymentsReportKind, // §3.3: R → "תקבולים" (BE-11)
          // R7: VAT businesses — invoices that should carry an allocation number.
          if (!exempt && caps.can(Cap.docView) && caps.can(Cap.moneyView))
            allocationScanKind,
        ])
          Padding(
            padding: const EdgeInsets.only(top: Space.m),
            child: AppCard(
              key: Key('report-card-$k'),
              onTap: () => openReport(context, k, period: _key.name),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: context.palette.tint(context.palette.info),
                      borderRadius: BorderRadius.circular(Radii.button),
                    ),
                    child: Icon(
                      switch (k) {
                        dailySummaryKind => Iconsax.calendar_tick,
                        'vat' => Iconsax.percentage_circle,
                        'debts' || 'receivables' => Iconsax.wallet_2,
                        paymentsReportKind => Iconsax.money_recive,
                        allocationScanKind => Iconsax.verify,
                        'expenses' => Iconsax.receipt_item,
                        'customers' => Iconsax.profile_2user,
                        'items' => Iconsax.box,
                        'continuity' => Iconsax.document_text,
                        _ => Iconsax.chart_2,
                      },
                      color: context.palette.info,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          k == allocationScanKind
                              ? AllocationHe.scanTitle
                              : k == dailySummaryKind
                              ? DailySummaryHe.title
                              : ReportsHe.kinds[k] ?? k,
                          style: AppText.headline,
                        ),
                        const SizedBox(height: Space.xs),
                        Text(
                          _reportHint(k),
                          style: AppText.secondary.copyWith(
                            color: context.palette.muted,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.s),
                  Icon(
                    Iconsax.arrow_left_2,
                    size: 20,
                    color: context.palette.muted,
                  ),
                ],
              ),
            ),
          ),
        if (!owner && caps.can(Cap.reportExport)) ...[
          const SizedBox(height: Space.section),
          _exportRow('accountant', ReportsHe.exportAccountant, Iconsax.folder),
          _exportRow('excel', ReportsHe.exportExcel, Iconsax.grid_1),
          if (businessContext.me?.uniformFormatReady ?? false)
            ListTile(
              key: const Key('export-uniform'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: Hit.row,
              leading: const Icon(Iconsax.monitor),
              title: const Text(ReportsHe.uniformFormat, style: AppText.body),
              subtitle: const Text(CommonHe.continueOnComputer),
              onTap: session.offline ? null : _uniformFormat,
            ),
        ],
      ],
    ];
    final list = ListView(
      padding: EdgeInsets.fromLTRB(
        Space.page,
        widget.embedded ? Space.xl : Space.s,
        Space.page,
        MediaQuery.paddingOf(context).bottom + Space.xl,
      ),
      children: content,
    );
    final bottom = owner && caps.can(Cap.reportExport) && _error == null
        ? BottomActionArea(
            note: session.profile?.accountantEmail == null
                ? ReportsHe.noAccountantEmail
                : null,
            child: PrimaryButton(
              key: const Key('send-to-accountant'),
              label: ReportsHe.sendToAccountant,
              loadingText: _exporting == 'accountant'
                  ? ReportsHe.preparing
                  : null,
              offline: session.offline,
              onPressed: _sendToAccountant,
            ),
          )
        : null;
    return Scaffold(
      appBar: (widget.embedded || context.isDark)
          ? null
          : AppBar(title: const Text(ReportsHe.title)),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (!widget.embedded && context.isDark)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.page,
                  Space.m,
                  Space.page,
                  Space.s,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(ReportsHe.title, style: AppText.displayTitle),
                    ),
                    const DesignBackButton(),
                  ],
                ),
              ),
            OfflineBanner(visible: session.offline),
            Expanded(
              child: ContentReveal(
                key: ValueKey((_loading, _key)),
                child: RefreshIndicator(onRefresh: _load, child: list),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: bottom,
    );
  }

  List<Widget> _accountantHeader(BuildContext context) => [
    // Feature 1: "הלקוחות שלי" — above the existing reports screen.
    const ClientsSummaryRow(),
    Semantics(
      header: true,
      child: const Text(ReportsHe.myClients, style: AppText.title),
    ),
    Row(
      children: [
        Expanded(
          child: Text(businessContext.displayName, style: AppText.headline),
        ),
        if (businessContext.hasManyBusinesses)
          TextButton(
            key: const Key('reports-switch'),
            onPressed: () => showSwitchBusinessSheet(context),
            child: const Text(BusinessHe.switchBusiness),
          ),
      ],
    ),
    const SizedBox(height: Space.m),
  ];

  String _reportHint(String kind) => switch (kind) {
    'income' => 'פירוט הכנסות ומסמכים לתקופה שנבחרה',
    'expenses' => 'הוצאות שנקלטו וסווגו בתקופה',
    'vat' => 'סיכום מע״מ לפי מסמכי העסק',
    'pnl' => 'תמונת מצב של הכנסות מול הוצאות',
    'advances' => 'אומדן לפי שיעור המקדמות שהוגדר',
    'receivables' || 'debts' => 'יתרות פתוחות ופירוט לפי לקוח',
    'items' => 'מוצרים ושירותים שנכללו במסמכים',
    'customers' => 'פירוט הכנסות לפי לקוח',
    'continuity' => 'רצף המסמכים והמספור בעסק',
    paymentsReportKind => 'תשלומים שנרשמו ושיוכם למסמכים',
    dailySummaryKind => DailySummaryHe.cardHint,
    allocationScanKind => AllocationHe.scanHint,
    _ => 'פירוט הנתונים לתקופה שנבחרה',
  };

  Widget _exportRow(String kind, String label, IconData icon) => ListTile(
    key: Key('export-$kind'),
    contentPadding: EdgeInsets.zero,
    minTileHeight: Hit.row,
    leading: Icon(icon),
    title: Text(label, style: AppText.body),
    trailing: _exporting == kind
        ? const SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          )
        : null,
    onTap: session.offline ? null : () => _export(kind),
  );
}
