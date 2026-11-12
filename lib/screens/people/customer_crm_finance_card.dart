import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../state/customer_crm_insights.dart';
import '../../state/customer_crm_store.dart';
import '../../ui/ds.dart';
import '../../util/labels/customer_crm_he.dart';
import '../../util/money.dart';

String crmMoney(int minor) =>
    formatMoney(BigInt.from(minor), trimZeroAgorot: true);

class CustomerCrmFinanceCard extends StatefulWidget {
  const CustomerCrmFinanceCard({
    super.key,
    required this.jobs,
    required this.onOpenJob,
    this.compact = false,
  });
  final List<CustomerCrmJob> jobs;
  final ValueChanged<CustomerCrmJob> onOpenJob;
  final bool compact;
  @override
  State<CustomerCrmFinanceCard> createState() => _CustomerCrmFinanceCardState();
}

class _CustomerCrmFinanceCardState extends State<CustomerCrmFinanceCard> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final summary = CustomerCrmInsights(
      widget.jobs,
      month: _month,
      now: DateTime.now(),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Space.m),
        Text(
          CustomerCrmHe.remaining,
          style: AppText.body.copyWith(color: p.muted),
        ),
        const SizedBox(height: Space.xs),
        Text(
          crmMoney(summary.remainingMinor),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.right,
          style: AppText.title.copyWith(
            fontSize: 36,
            fontWeight: FontWeight.w600,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(
          summary.collections.length == 1
              ? 'עבודה אחת שהסתיימה · כל התקופות'
              : '${summary.collections.length} עבודות שהסתיימו · כל התקופות',
          style: AppText.secondary.copyWith(color: p.muted),
        ),
        const SizedBox(height: Space.m),
        if (summary.collections.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Space.m),
            child: Text(
              CustomerCrmHe.collectionEmpty,
              style: AppText.secondary,
            ),
          ),
        for (final job in summary.collections) ...[
          Divider(color: p.line, height: 1),
          ListTile(
            key: ValueKey('crm-collect-${job.id}'),
            contentPadding: EdgeInsets.zero,
            title: Text(job.title, style: AppText.body),
            subtitle: Text(
              '${job.customerName}${job.budget.paymentDueAt == null ? '' : ' · ${DateFormat('dd.MM').format(job.budget.paymentDueAt!)}'}${_late(job) ? ' · באיחור' : ''}',
              style: AppText.secondary.copyWith(
                color: _late(job) ? p.danger : p.muted,
              ),
            ),
            trailing: Text(
              crmMoney(job.budget.remainingMinor!),
              textDirection: TextDirection.ltr,
              style: AppText.headline,
            ),
            onTap: () => widget.onOpenJob(job),
          ),
        ],
        const SizedBox(height: Space.xl),
        Row(
          children: [
            Expanded(
              child: Text(
                DateFormat('MMMM yyyy', 'he').format(_month),
                style: AppText.headline,
              ),
            ),
            IconButton(
              tooltip: CustomerCrmHe.previousMonth,
              onPressed: () => setState(
                () => _month = DateTime(_month.year, _month.month - 1),
              ),
              icon: const Icon(Icons.chevron_right, size: 20),
            ),
            IconButton(
              tooltip: CustomerCrmHe.nextMonth,
              onPressed: () => setState(
                () => _month = DateTime(_month.year, _month.month + 1),
              ),
              icon: const Icon(Icons.chevron_left, size: 20),
            ),
          ],
        ),
        Divider(color: p.line, height: 1),
        for (final metric in [
          (
            CustomerCrmHe.completedPrice,
            crmMoney(summary.completedPriceMinor),
            false,
          ),
          (
            CustomerCrmHe.upcomingPrice,
            crmMoney(summary.openPriceMinor),
            false,
          ),
          (CustomerCrmHe.collected, crmMoney(summary.trackedPaidMinor), false),
          (
            CustomerCrmHe.contribution,
            summary.costedCount == 0
                ? '—'
                : crmMoney(summary.contributionMinor),
            summary.contributionMinor < 0,
          ),
          (
            CustomerCrmHe.hourly,
            summary.hourlyMinor == null ? '—' : crmMoney(summary.hourlyMinor!),
            (summary.hourlyMinor ?? 0) < 0,
          ),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.m),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    metric.$1,
                    style: AppText.body.copyWith(color: p.muted),
                  ),
                ),
                const SizedBox(width: Space.m),
                Flexible(
                  child: Text(
                    metric.$2,
                    style: AppText.headline.copyWith(
                      color: metric.$3 ? p.danger : p.ink,
                    ),
                    textDirection: TextDirection.ltr,
                  ),
                ),
              ],
            ),
          ),
        if (summary.unpricedCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Text(
              summary.unpricedCount == 1
                  ? 'עבודה אחת עדיין ללא מחיר'
                  : '${summary.unpricedCount} עבודות עדיין ללא מחיר',
              style: AppText.secondary.copyWith(color: p.warn),
            ),
          ),
        Divider(color: p.line),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: Space.m),
          title: Text(
            CustomerCrmHe.calculationDetails,
            style: AppText.secondary.copyWith(color: p.muted),
          ),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  CustomerCrmHe.byScheduledDate,
                  style: AppText.secondary,
                ),
                const SizedBox(height: Space.s),
                Text(
                  '${summary.costedCount}/${summary.completedCount} · ${CustomerCrmHe.partialContribution}',
                  style: AppText.secondary,
                ),
                const SizedBox(height: Space.s),
                const Text(CustomerCrmHe.manualMoney, style: AppText.secondary),
              ],
            ),
          ],
        ),
      ],
    );
    return Material(
      key: const Key('crm-finance-card'),
      type: MaterialType.transparency,
      child: widget.compact
          ? ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(
                CustomerCrmHe.financialOverview,
                style: AppText.headline,
              ),
              children: [content],
            )
          : content,
    );
  }

  bool _late(CustomerCrmJob job) {
    final now = DateTime.now();
    return job.budget.paymentDueAt?.isBefore(
          DateTime(now.year, now.month, now.day),
        ) ??
        false;
  }
}
