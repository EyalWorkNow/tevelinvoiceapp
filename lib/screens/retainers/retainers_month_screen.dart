// "חשבוניות החודש" (QA 2026-11-16 C4, SPEC-v2 BE-29). The month's retainer
// drafts that the server prepared on each template's day; per row: edit the
// amount, skip this month or remove the customer from the package. One
// button issues them all (the approval policy and allocation rules apply on
// the server; a retry or a double tap never issues twice).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../router.dart' show openDocument;
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../ui/app_page_route.dart';
import '../../ui/ds.dart';
import '../../ui/widgets/notch_notice.dart' show NoticeMotion;
import '../../util/labels/retainer_he.dart';
import '../../util/money.dart';
import '../business/business_template.dart';
import '../compose/signing_unlock.dart';
import '../document/dialogs.dart' show toast;
import 'retainer_templates_screen.dart';
import 'retainers_api.dart';
import '../../util/money_input.dart';

/// Opens "חשבוניות החודש" ([period] YYYY-MM, default: this Israel month).
Future<void> openRetainersMonth(BuildContext context, {String? period}) =>
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => RetainersMonthScreen(period: period),
        settings: const RouteSettings(name: '/retainers'),
      ),
    );

/// The Management entry is shown to who may draft and see amounts.
bool mayUseRetainers(Caps caps) =>
    caps.can(Cap.docDraft) && caps.can(Cap.moneyView);

class RetainersMonthScreen extends StatefulWidget {
  const RetainersMonthScreen({super.key, this.period});

  final String? period;

  @override
  State<RetainersMonthScreen> createState() => _RetainersMonthScreenState();
}

class _RetainersMonthScreenState extends State<RetainersMonthScreen> {
  late final String _period = widget.period ?? currentPeriod();
  RetainerMonth? _month;
  Object? _error;
  bool _issuing = false;
  bool _send = false;
  final Set<String> _rowBusy = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final m = await fetchRetainerMonth(_period);
      if (!mounted) return;
      setState(() {
        _month = m;
        _error = null;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _row(String runId, Future<void> Function() action) async {
    if (_rowBusy.contains(runId)) return;
    setState(() => _rowBusy.add(runId));
    try {
      await action();
      await _load();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _rowBusy.remove(runId));
    }
  }

  Future<void> _issueAll() async {
    if (_issuing) return; // one tap; the server is idempotent anyway
    setState(() => _issuing = true);
    try {
      var r = await issueRetainerMonth(_period, send: _send);
      if (r.signingLocked > 0 && mounted) {
        toast(context, RetainerHe.signingLocked, motion: NoticeMotion.error);
        if (await ensureSigningUnlocked(context)) {
          r = await issueRetainerMonth(_period, send: _send);
        }
      }
      if (!mounted) return;
      final summary = RetainerHe.issueSummary(
        issued: r.issued,
        submitted: r.submitted,
        waiting: r.waitingAllocation,
        failed: r.failed,
      );
      toast(
        context,
        r.failed > 0 ? '$summary. ${RetainerHe.error(r.firstError)}' : summary,
        motion: r.failed > 0 ? NoticeMotion.error : NoticeMotion.document,
      );
      await _load();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _issuing = false);
    }
  }

  Future<void> _editAmount(RetainerRun run) async {
    final List<BigInt> current;
    try {
      current = [
        for (final l in await fetchDraftLines(run.documentId!))
          l.unitPriceMinor,
      ];
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
      return;
    }
    if (!mounted) return;
    final prices = await showPricesDialog(
      context,
      title: run.customerName,
      prices: current,
    );
    if (prices == null || !mounted) return;
    await _row(run.runId, () => setRetainerRunPrices(run.runId, prices));
  }

  Future<void> _remove(RetainerRun run) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(RetainerHe.removeConfirmTitle),
        content: const Text(RetainerHe.removeConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text(RetainerHe.cancel),
          ),
          TextButton(
            key: const Key('retainer-remove-confirm'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text(RetainerHe.removeConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _row(run.runId, () => removeRetainerRun(run.runId));
  }

  @override
  Widget build(BuildContext context) {
    final m = _month;
    final canSend = businessContext.can(Cap.docSend);
    return BusinessPage(
      title: RetainerHe.monthTitle,
      onRefresh: _load,
      header: Row(
        children: [
          Expanded(
            child: Text(
              m == null
                  ? ''
                  : m.pendingCount == 0
                  ? m.labelHe
                  : '${m.labelHe} · ${RetainerHe.readyCount(m.pendingCount)}',
              key: const Key('retainers-header'),
              style: AppText.secondary.copyWith(color: context.palette.muted),
            ),
          ),
          TextButton(
            key: const Key('retainers-templates'),
            onPressed: () => openRetainerTemplates(context),
            child: const Text(RetainerHe.templatesTitle),
          ),
        ],
      ),
      bottom: m == null || m.pendingCount == 0
          ? null
          : BottomActionArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (canSend)
                    CheckboxListTile(
                      key: const Key('retainers-send'),
                      contentPadding: EdgeInsets.zero,
                      value: _send,
                      onChanged: _issuing
                          ? null
                          : (v) => setState(() => _send = v ?? false),
                      title: const Text(RetainerHe.andSend),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  PrimaryButton(
                    key: const Key('retainers-issue-all'),
                    label:
                        '${RetainerHe.issueAll} · ${formatMoney(m.pendingTotalMinor, trimZeroAgorot: true)}',
                    loadingText: _issuing ? RetainerHe.issuing : null,
                    offline: businessContext.offline,
                    onPressed: () => unawaited(_issueAll()),
                  ),
                ],
              ),
            ),
      children: [
        if (_error != null && m == null)
          Padding(
            padding: const EdgeInsets.only(top: Space.xl),
            child: ErrorView(error: _error!, onRetry: () => unawaited(_load())),
          )
        else if (m == null)
          const Padding(
            padding: EdgeInsets.only(top: Space.xl),
            child: Center(child: CircularProgressIndicator.adaptive()),
          )
        else if (m.items.isEmpty)
          const EmptyState(
            icon: Iconsax.calendar_1,
            title: RetainerHe.nothingYet,
            message: RetainerHe.nothingYetBody,
          )
        else
          for (final run in m.items)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: _RunCard(
                run: run,
                busy: _rowBusy.contains(run.runId) || _issuing,
                onOpen: run.documentId == null
                    ? null
                    : () => openDocument(context, run.documentId!),
                onEdit: () => unawaited(_editAmount(run)),
                onSkip: () => unawaited(
                  _row(run.runId, () => skipRetainerRun(run.runId)),
                ),
                onRemove: () => unawaited(_remove(run)),
              ),
            ),
      ],
    );
  }
}

class _RunCard extends StatelessWidget {
  const _RunCard({
    required this.run,
    required this.busy,
    required this.onOpen,
    required this.onEdit,
    required this.onSkip,
    required this.onRemove,
  });

  final RetainerRun run;
  final bool busy;
  final VoidCallback? onOpen;
  final VoidCallback onEdit;
  final VoidCallback onSkip;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final total = run.totalMinor;
    final hints = [
      for (final h in run.hints)
        switch (h) {
          'APPROVAL' => RetainerHe.hintApproval,
          'ALLOCATION' => RetainerHe.hintAllocation,
          'CUSTOMER_VAT_STATUS' => RetainerHe.hintCustomerVat,
          _ => null,
        },
    ].whereType<String>().toList();
    return AppCard(
      key: Key('retainer-run-${run.runId}'),
      onTap: onOpen,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(run.customerName, style: AppText.headline),
                if (run.title != null)
                  Text(
                    run.title!,
                    style: AppText.secondary.copyWith(color: p.muted),
                  ),
                const SizedBox(height: Space.xs),
                Text(
                  RetainerHe.status(run.status),
                  key: Key('retainer-status-${run.runId}'),
                  style: AppText.secondary.copyWith(
                    color: run.status == 'FAILED' ? p.danger : p.muted,
                  ),
                ),
                for (final h in hints)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Row(
                      children: [
                        Icon(Iconsax.info_circle, size: 14, color: p.warn),
                        const SizedBox(width: Space.xs),
                        Flexible(
                          child: Text(
                            h,
                            style: AppText.secondary.copyWith(color: p.warn),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // The menu before the amount: totals hug the card's end on every
          // run, waiting or not (2026-11-23).
          if (run.waiting && !busy)
            MoreMenu(
              key: Key('retainer-menu-${run.runId}'),
              items: [
                MoreMenuItem(label: RetainerHe.editAmount, onSelected: onEdit),
                MoreMenuItem(label: RetainerHe.skip, onSelected: onSkip),
                MoreMenuItem(
                  label: RetainerHe.remove,
                  destructive: true,
                  onSelected: onRemove,
                ),
              ],
            ),
          if (total != null)
            Text(
              formatMoney(total, trimZeroAgorot: true),
              key: Key('retainer-total-${run.runId}'),
              style: AppText.amountRow,
            ),
        ],
      ),
    );
  }
}

/// One price field per line (before VAT). Null = cancelled.
Future<List<BigInt>?> showPricesDialog(
  BuildContext context, {
  required String title,
  required List<BigInt> prices,
}) => showDialog<List<BigInt>>(
  context: context,
  builder: (_) => _PricesDialog(title: title, prices: prices),
);

class _PricesDialog extends StatefulWidget {
  const _PricesDialog({required this.title, required this.prices});

  final String title;
  final List<BigInt> prices;

  @override
  State<_PricesDialog> createState() => _PricesDialogState();
}

class _PricesDialogState extends State<_PricesDialog> {
  late final List<TextEditingController> _fields = [
    for (final p in widget.prices)
      TextEditingController(text: formatMoney(p, symbol: '').trim()),
  ];

  @override
  void dispose() {
    for (final f in _fields) {
      f.dispose();
    }
    super.dispose();
  }

  List<BigInt>? get _parsed {
    final out = <BigInt>[];
    for (final f in _fields) {
      final v = parseAmount(f.text);
      if (v == null) return null;
      out.add(v);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, f) in _fields.indexed)
          TextField(
            key: Key('retainer-price-$i'),
            controller: f,
            keyboardType: moneyKeyboard,
            inputFormatters: moneyFormatters,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: _fields.length == 1
                  ? RetainerHe.unitPrice
                  : '${RetainerHe.linePrice(i)} · ${RetainerHe.unitPrice}',
              prefixText: '₪ ',
            ),
            onChanged: (_) => setState(() {}),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text(RetainerHe.cancel),
      ),
      TextButton(
        key: const Key('retainer-price-save'),
        onPressed: _parsed == null
            ? null
            : () => Navigator.pop(context, _parsed),
        child: const Text(RetainerHe.save),
      ),
    ],
  );
}
