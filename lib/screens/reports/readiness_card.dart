// C6 · "מוכן לרו״ח" (QA 2026-11-16, persona 06 idea 1). Owner: C6.
// The card at the top of R: the period's readiness score 0–100 (server
// GET /reports/readiness, built on the existing checks) and a checklist; each
// open item opens the screen that fixes it. Below the threshold "שלח לרו״ח"
// asks for an explicit confirm ([confirmSendBelowThreshold]).
// Also the score badge of the accountant's board in S14 ([ReadinessBadge]).

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/models/models.dart' show InboxKind;
import '../../api/readiness_api.dart';
import '../../api/reports_api.dart' show paymentsReportKind;
import '../../router.dart';
import '../../ui/ds.dart';
import '../../util/labels/labels.dart';
import '../home/inbox_list.dart' show openInboxList;
import 'allocation_scan_view.dart' show allocationScanKind;

/// Opens the screen that fixes [item] ([period] = the R chip, for reports).
Future<void> openReadinessTarget(
  BuildContext context,
  ReadinessItem item, {
  String? period,
}) async {
  switch (item.screen) {
    case ReadinessScreen.report:
      return openReport(context, item.ref ?? 'continuity', period: period);
    case ReadinessScreen.payments:
      return openReport(context, paymentsReportKind, period: period);
    case ReadinessScreen.inboxList:
      final kind = InboxKind.fromWire(item.ref);
      if (kind != null) return openInboxList(context, kind);
      return;
    case ReadinessScreen.allocationScan:
      return openReport(context, allocationScanKind, period: period);
    case ReadinessScreen.expenses:
      return openExpenses(context, expenseId: item.ref);
    case ReadinessScreen.document:
      final id = item.ref ?? (item.ids.isEmpty ? null : item.ids.first);
      if (id != null) return openDocument(context, id);
      return;
    case ReadinessScreen.unknown:
      return;
  }
}

/// True when "שלח לרו״ח" may go: ready, unknown (no readiness), or the user
/// explicitly confirms sending a period that is not ready yet.
Future<bool> confirmSendBelowThreshold(
  BuildContext context,
  Readiness? readiness,
) async {
  if (readiness == null || readiness.ready) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(ReadinessHe.sendAnywayTitle),
      content: Text(
        ReadinessHe.sendAnywayBody(readiness.score, readiness.open.length),
      ),
      actions: [
        TextButton(
          key: const Key('readiness-fix-first'),
          onPressed: () => Navigator.pop(context, false),
          child: const Text(ReadinessHe.fixFirst),
        ),
        TextButton(
          key: const Key('readiness-send-anyway'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text(ReadinessHe.sendAnyway),
        ),
      ],
    ),
  );
  return ok ?? false;
}

Color readinessColor(BuildContext context, int score, int threshold) {
  final p = context.palette;
  if (score >= threshold) return p.ok;
  if (score >= threshold - 20) return p.warn;
  return p.danger;
}

/// The score ring + badge word ("82 · כמעט"). [score] null = still loading.
class ReadinessBadge extends StatelessWidget {
  const ReadinessBadge({
    super.key,
    required this.score,
    this.threshold = 90,
    this.size = 40,
  });

  final int? score;
  final int threshold;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = score;
    if (s == null) {
      return SizedBox.square(
        dimension: size,
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final color = readinessColor(context, s, threshold);
    return Semantics(
      label: ReadinessHe.scoreSemantics(s, ReadinessHe.badge(s, threshold)),
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.square(
              dimension: size,
              child: CircularProgressIndicator(
                value: s / 100,
                strokeWidth: size / 10,
                color: color,
                backgroundColor: context.palette.tint(color),
              ),
            ),
            Text(
              '$s',
              style: AppText.secondary.copyWith(
                fontWeight: FontWeight.w700,
                color: context.palette.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "מוכן לרו״ח" at the top of R. Stateless: R loads [readiness] with the
/// rest of the period and reloads after a fix ([onChanged]).
class ReadinessCard extends StatefulWidget {
  const ReadinessCard({
    super.key,
    required this.readiness,
    this.period,
    this.onChanged,
  });

  final Readiness readiness;

  /// The R chip (passed to the reports an item opens).
  final String? period;
  final VoidCallback? onChanged;

  @override
  State<ReadinessCard> createState() => _ReadinessCardState();
}

class _ReadinessCardState extends State<ReadinessCard> {
  bool _showPassed = false;

  Future<void> _open(ReadinessItem item) async {
    await openReadinessTarget(context, item, period: widget.period);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.readiness;
    final p = context.palette;
    final open = r.open;
    final passed = r.passed;
    final color = readinessColor(context, r.score, r.threshold);
    return AppCard(
      key: const Key('readiness-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ReadinessBadge(score: r.score, threshold: r.threshold, size: 52),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: const Text(
                        ReadinessHe.title,
                        style: AppText.headline,
                      ),
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      open.isEmpty
                          ? ReadinessHe.allGood
                          : ReadinessHe.missing(open.length),
                      key: const Key('readiness-summary'),
                      style: AppText.secondary.copyWith(color: p.muted),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.s,
                  vertical: Space.xs,
                ),
                decoration: BoxDecoration(
                  color: p.tint(color),
                  borderRadius: BorderRadius.circular(Radii.button),
                ),
                child: Text(
                  ReadinessHe.badge(r.score, r.threshold),
                  key: const Key('readiness-badge'),
                  style: AppText.secondary.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (open.isNotEmpty) const SizedBox(height: Space.s),
          for (final item in open)
            _ItemRow(item: item, onTap: () => _open(item)),
          if (passed.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            TextButton(
              key: const Key('readiness-toggle-passed'),
              style: TextButton.styleFrom(
                alignment: AlignmentDirectional.centerStart,
              ),
              onPressed: () => setState(() => _showPassed = !_showPassed),
              child: Text(
                _showPassed
                    ? ReadinessHe.hidePassed
                    : '${ReadinessHe.passed(passed.length)} · ${ReadinessHe.showPassed}',
              ),
            ),
            if (_showPassed)
              for (final item in passed) _ItemRow(item: item, onTap: null),
          ],
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.onTap});

  final ReadinessItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (IconData icon, Color color) = switch (item.status) {
      ReadinessStatus.fail => (Iconsax.danger, p.danger),
      ReadinessStatus.warn => (Iconsax.info_circle, p.warn),
      ReadinessStatus.ok => (Iconsax.tick_circle, p.ok),
    };
    return InkWell(
      key: Key('readiness-item-${item.key}'),
      borderRadius: BorderRadius.circular(Radii.button),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Hit.row),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(item.title, style: AppText.body),
                    if (item.hint.isNotEmpty)
                      Text(
                        item.hint,
                        style: AppText.secondary.copyWith(color: p.muted),
                      ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Iconsax.arrow_left_2, size: 18, color: p.muted),
            ],
          ),
        ),
      ),
    );
  }
}
