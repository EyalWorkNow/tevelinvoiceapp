import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../state/customer_crm_store.dart';
import '../../ui/ds.dart';
import '../../util/labels/customer_crm_he.dart';
import 'customer_crm_finance_card.dart';
import 'customer_crm_job_fields.dart';

class CustomerCrmJobs extends StatefulWidget {
  const CustomerCrmJobs({
    super.key,
    required this.jobs,
    required this.enabled,
    required this.onEdit,
    required this.onRepeat,
    required this.onDelete,
    required this.onStatus,
    this.onCreateDocument,
    this.showMoney = false,
    this.onChecklist,
    this.onReschedule,
    this.onNavigate,
    this.onMessage,
  });
  final List<CustomerCrmJob> jobs;
  final bool enabled;
  final ValueChanged<CustomerCrmJob> onEdit, onRepeat, onDelete;
  final void Function(CustomerCrmJob, CustomerCrmJobStatus) onStatus;
  final VoidCallback? onCreateDocument;
  final bool showMoney;
  final void Function(CustomerCrmJob, String, bool)? onChecklist;
  final void Function(CustomerCrmJob, int)? onReschedule;
  final ValueChanged<CustomerCrmJob>? onNavigate, onMessage;
  @override
  State<CustomerCrmJobs> createState() => _CustomerCrmJobsState();
}

class _CustomerCrmJobsState extends State<CustomerCrmJobs> {
  bool _history = false;
  final Set<String> _expanded = {}, _collapsed = {};

  @override
  Widget build(BuildContext context) {
    final open = widget.jobs.where((job) => job.status.isOpen).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final history = widget.jobs.where((job) => !job.status.isOpen).toList()
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (open.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Space.xl),
            child: Text(CustomerCrmHe.noJobs, style: AppText.body),
          ),
        for (final (index, job) in open.indexed) ...[
          if (index <= 1)
            Padding(
              padding: const EdgeInsets.only(top: Space.m, bottom: Space.s),
              child: Text(
                index == 0 ? CustomerCrmHe.nextVisit : CustomerCrmHe.moreVisits,
                style: AppText.secondary.copyWith(color: context.palette.muted),
              ),
            ),
          _tile(context, job, featured: index == 0),
        ],
        if (history.isNotEmpty) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('crm-job-history'),
              onPressed: () => setState(() => _history = !_history),
              icon: Icon(
                _history ? Icons.expand_less : Icons.history,
                size: 18,
              ),
              label: Text(
                _history
                    ? CustomerCrmHe.hideHistory
                    : '${CustomerCrmHe.history} (${history.length})',
              ),
            ),
          ),
          if (_history)
            for (final job in history) _tile(context, job),
        ],
      ],
    );
  }

  Widget _tile(
    BuildContext context,
    CustomerCrmJob job, {
    bool featured = false,
  }) {
    final p = context.palette;
    final expanded =
        _expanded.contains(job.id) ||
        (featured && !_collapsed.contains(job.id));
    final tone = job.status == CustomerCrmJobStatus.active
        ? p.info
        : job.status == CustomerCrmJobStatus.completed
        ? p.ok
        : p.muted;
    return Padding(
      key: ValueKey('crm-job-${job.id}'),
      padding: const EdgeInsets.only(bottom: Space.s),
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: p.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: ValueKey('crm-job-expand-${job.id}'),
              onTap: () => setState(() {
                if (expanded) {
                  _expanded.remove(job.id);
                  _collapsed.add(job.id);
                } else {
                  _expanded.add(job.id);
                  _collapsed.remove(job.id);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 64,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('HH:mm').format(job.scheduledAt),
                            style: AppText.headline,
                            textDirection: TextDirection.ltr,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _day(job.scheduledAt),
                            style: AppText.secondary.copyWith(color: p.muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Space.s),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(job.title, style: AppText.headline),
                          const SizedBox(height: 4),
                          Text(
                            job.address.isEmpty
                                ? job.status.label
                                : job.address,
                            style: AppText.secondary.copyWith(color: p.muted),
                          ),
                          if (job.address.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                job.status.label,
                                style: AppText.secondary.copyWith(color: tone),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: p.muted,
                    ),
                  ],
                ),
              ),
            ),
            if (expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Divider(color: p.line, height: 16),
                    if (job.details.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.s),
                        child: Text(job.details, style: AppText.body),
                      ),
                    if (job.repeatEveryDays > 0)
                      Text(
                        crmRepeatLabels[job.repeatEveryDays]!,
                        style: AppText.secondary.copyWith(color: p.muted),
                      ),
                    if (job.checklist.isNotEmpty) ...[
                      const SizedBox(height: Space.m),
                      Text(
                        '${CustomerCrmHe.checklist}  ${job.checklist.where((item) => item.done).length}/${job.checklist.length}',
                        style: AppText.secondary.copyWith(color: p.muted),
                      ),
                      for (final item in job.checklist)
                        CheckboxListTile(
                          key: ValueKey('crm-check-${item.id}'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            item.text,
                            style: AppText.body.copyWith(
                              color: item.done ? p.muted : p.ink,
                              decoration: item.done
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          value: item.done,
                          onChanged:
                              widget.enabled &&
                                  job.status !=
                                      CustomerCrmJobStatus.cancelled &&
                                  widget.onChecklist != null
                              ? (value) => widget.onChecklist!(
                                  job,
                                  item.id,
                                  value ?? false,
                                )
                              : null,
                        ),
                    ],
                    if (widget.showMoney &&
                        job.status != CustomerCrmJobStatus.cancelled &&
                        job.budget.priceMinor != null) ...[
                      const SizedBox(height: Space.s),
                      _moneyLine(
                        context,
                        CustomerCrmHe.price,
                        crmMoney(job.budget.priceMinor!),
                      ),
                      if (job.budget.paidMinor > 0 ||
                          job.status == CustomerCrmJobStatus.completed)
                        _moneyLine(
                          context,
                          CustomerCrmHe.remaining,
                          crmMoney(job.budget.remainingMinor!),
                        ),
                    ],
                    const SizedBox(height: Space.s),
                    Wrap(
                      spacing: Space.xs,
                      runSpacing: Space.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (job.status.isOpen)
                          FilledButton.tonalIcon(
                            key: ValueKey('crm-job-next-${job.id}'),
                            onPressed: widget.enabled
                                ? () => widget.onStatus(
                                    job,
                                    job.status == CustomerCrmJobStatus.scheduled
                                        ? CustomerCrmJobStatus.active
                                        : CustomerCrmJobStatus.completed,
                                  )
                                : null,
                            icon: Icon(
                              job.status == CustomerCrmJobStatus.scheduled
                                  ? Icons.play_arrow
                                  : Icons.check,
                              size: 18,
                            ),
                            label: Text(
                              job.status == CustomerCrmJobStatus.scheduled
                                  ? CustomerCrmHe.start
                                  : CustomerCrmHe.complete,
                            ),
                          ),
                        if (widget.onNavigate != null && job.address.isNotEmpty)
                          TextButton.icon(
                            onPressed: () => widget.onNavigate!(job),
                            icon: const Icon(Iconsax.location, size: 18),
                            label: const Text(CustomerCrmHe.navigate),
                          ),
                        if (widget.onMessage != null && job.status.isOpen)
                          TextButton.icon(
                            onPressed: () => widget.onMessage!(job),
                            icon: const Icon(Iconsax.message, size: 18),
                            label: const Text(CustomerCrmHe.visitMessage),
                          ),
                        if (job.status == CustomerCrmJobStatus.completed &&
                            job.repeatEveryDays > 0)
                          TextButton.icon(
                            onPressed: widget.enabled
                                ? () => widget.onRepeat(job)
                                : null,
                            icon: const Icon(Iconsax.calendar_add, size: 18),
                            label: const Text(CustomerCrmHe.repeatVisit),
                          ),
                        if (job.status == CustomerCrmJobStatus.completed &&
                            widget.onCreateDocument != null)
                          TextButton(
                            onPressed: widget.onCreateDocument,
                            child: const Text(CustomerCrmHe.createDocument),
                          ),
                        PopupMenuButton<String>(
                          key: ValueKey('crm-job-menu-${job.id}'),
                          tooltip: CustomerCrmHe.edit,
                          enabled: widget.enabled,
                          icon: const Icon(Icons.more_horiz),
                          onSelected: (action) {
                            switch (action) {
                              case 'edit':
                                widget.onEdit(job);
                              case 'repeat':
                                widget.onRepeat(job);
                              case 'tomorrow':
                                widget.onReschedule?.call(job, 1);
                              case 'week':
                                widget.onReschedule?.call(job, 7);
                              case 'cancel':
                                widget.onStatus(
                                  job,
                                  CustomerCrmJobStatus.cancelled,
                                );
                              case 'reopen':
                                widget.onStatus(
                                  job,
                                  CustomerCrmJobStatus.scheduled,
                                );
                              case 'delete':
                                widget.onDelete(job);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text(CustomerCrmHe.edit),
                            ),
                            if (widget.showMoney)
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text(CustomerCrmHe.moneyEdit),
                              ),
                            if (job.status.isOpen &&
                                widget.onReschedule != null) ...[
                              const PopupMenuItem(
                                value: 'tomorrow',
                                child: Text(CustomerCrmHe.tomorrow),
                              ),
                              const PopupMenuItem(
                                value: 'week',
                                child: Text(CustomerCrmHe.nextWeek),
                              ),
                            ],
                            const PopupMenuItem(
                              value: 'repeat',
                              child: Text(CustomerCrmHe.repeatVisit),
                            ),
                            if (job.status.isOpen)
                              const PopupMenuItem(
                                value: 'cancel',
                                child: Text(CustomerCrmHe.cancelJob),
                              ),
                            if (!job.status.isOpen)
                              const PopupMenuItem(
                                value: 'reopen',
                                child: Text(CustomerCrmHe.reopen),
                              ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text(CustomerCrmHe.delete),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _moneyLine(BuildContext context, String label, String value) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppText.secondary.copyWith(color: context.palette.muted),
              ),
            ),
            Text(value, style: AppText.body, textDirection: TextDirection.ltr),
          ],
        ),
      );

  String _day(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return CustomerCrmHe.todayJobs;
    }
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    if (date.year == tomorrow.year &&
        date.month == tomorrow.month &&
        date.day == tomorrow.day) {
      return 'מחר';
    }
    return DateFormat('dd.MM').format(date);
  }
}
