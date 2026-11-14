import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../state/customer_crm_store.dart';
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../util/labels/customer_crm_he.dart';
import '../../ui/app_page_route.dart';
import '../../ui/ds.dart';
import '../../util/labels/common_he.dart';
import '../business/business_template.dart';
import 'customer_crm_editors.dart';
import 'customer_crm_finance_card.dart';
import 'customer_crm_sync_status.dart';

Future<void> openCustomerCrmAgenda(
  BuildContext context, {
  required String businessId,
  required ValueChanged<String> onOpenCustomer,
}) async {
  await Navigator.of(context).push<void>(
    AppPageRoute<void>(
      settings: const RouteSettings(name: '/crm/agenda'),
      builder: (_) => CustomerCrmAgendaScreen(
        businessId: businessId,
        onOpenCustomer: onOpenCustomer,
      ),
    ),
  );
}

/// Job range filter: 0 all, 1 today, 2 the next 7 days. Only open jobs reach
/// the board, so one scheduled before today is overdue and stays visible in
/// every range until it is completed or cancelled.
@visibleForTesting
bool crmJobInRange(DateTime scheduledAt, int range, DateTime now) {
  if (range == 0) return true;
  final end = DateTime(now.year, now.month, now.day + (range == 1 ? 1 : 7));
  return scheduledAt.isBefore(end);
}

class CustomerCrmAgendaScreen extends StatefulWidget {
  const CustomerCrmAgendaScreen({
    super.key,
    required this.businessId,
    required this.onOpenCustomer,
  });

  final String businessId;
  final ValueChanged<String> onOpenCustomer;

  @override
  State<CustomerCrmAgendaScreen> createState() =>
      _CustomerCrmAgendaScreenState();
}

class _CustomerCrmAgendaScreenState extends State<CustomerCrmAgendaScreen> {
  final CustomerCrmStore _store = CustomerCrmStore.instance;
  final Set<String> _updating = {};
  int _jobRange = 0;
  int _boardSection = 0;
  String _search = '';

  bool _matches(String text) =>
      text.toLowerCase().contains(_search.trim().toLowerCase());
  bool get _canEdit => businessContext.can(Cap.customerManage);
  void _checkScope() {
    if (!_store.isLoadedFor(widget.businessId)) {
      throw StateError('CRM business changed');
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_store.loadForBusiness(widget.businessId));
  }

  @override
  void didUpdateWidget(covariant CustomerCrmAgendaScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId) {
      unawaited(_store.loadForBusiness(widget.businessId));
    }
  }

  Future<void> _complete(CustomerCrmReminder reminder) async {
    if (!_canEdit || _updating.contains(reminder.id)) return;
    setState(() => _updating.add(reminder.id));
    try {
      _checkScope();
      await _store.setReminderCompleted(
        reminder.customerId,
        reminder.id,
        !reminder.completed,
      );
    } on Object catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _updating.remove(reminder.id));
    }
  }

  Future<void> _edit(CustomerCrmReminder reminder) async {
    if (!_canEdit || _updating.contains(reminder.id)) return;
    final edited = await showCustomerReminderEditor(
      context,
      customerId: reminder.customerId,
      customerName: reminder.customerName,
      reminder: reminder,
    );
    if (edited == null || !mounted) return;
    setState(() => _updating.add(reminder.id));
    try {
      _checkScope();
      await _store.updateReminder(reminder.customerId, edited);
    } on Object catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _updating.remove(reminder.id));
    }
  }

  Future<void> _delete(CustomerCrmReminder reminder) async {
    if (!_canEdit || _updating.contains(reminder.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Iconsax.trash, color: context.palette.danger),
        title: const Text('למחוק את התזכורת?'),
        content: const Text('אפשר להוסיף תזכורת חדשה מתוך כרטיס הלקוח.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(CommonHe.cancel),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Iconsax.trash),
            label: const Text(CustomerCrmHe.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _updating.add(reminder.id));
    try {
      _checkScope();
      await _store.deleteReminder(reminder.customerId, reminder.id);
    } on Object catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _updating.remove(reminder.id));
    }
  }

  Future<void> _completeJob(CustomerCrmJob job) async {
    if (!_canEdit || _updating.contains(job.id)) return;
    setState(() => _updating.add(job.id));
    try {
      _checkScope();
      await _store.setJobStatus(
        job.customerId,
        job.id,
        CustomerCrmJobStatus.completed,
      );
    } on Object catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _updating.remove(job.id));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _store,
    builder: (context, _) {
      if (_store.hasLoadErrorFor(widget.businessId)) {
        return BusinessPage(
          title: CustomerCrmHe.businessBoard,
          children: [
            ErrorView(
              error: _store.loadError!,
              onRetry: () =>
                  unawaited(_store.loadForBusiness(widget.businessId)),
            ),
          ],
        );
      }
      if (!_store.isLoadedFor(widget.businessId)) {
        return BusinessPage(
          title: CustomerCrmHe.businessBoard,
          children: const [
            AppCard(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: Space.s),
                child: Center(child: CircularProgressIndicator.adaptive()),
              ),
            ),
          ],
        );
      }

      final jobs = _store.jobs
          .where(
            (job) =>
                job.status.isOpen &&
                _matches('${job.customerName} ${job.title} ${job.address}'),
          )
          .toList();
      final all = _store.reminders;
      final open = all
          .where(
            (reminder) =>
                !reminder.completed &&
                _matches('${reminder.customerName} ${reminder.title}'),
          )
          .toList();
      final done = all.where((reminder) => reminder.completed).length;
      final now = DateTime.now();
      final startToday = DateTime(now.year, now.month, now.day);
      final endToday = startToday.add(const Duration(days: 1));
      final visibleJobs = jobs
          .where((job) => crmJobInRange(job.scheduledAt, _jobRange, now))
          .toList();
      final overdue = open
          .where((reminder) => reminder.dueAt.isBefore(startToday))
          .toList();
      final today = open
          .where(
            (reminder) =>
                !reminder.dueAt.isBefore(startToday) &&
                reminder.dueAt.isBefore(endToday),
          )
          .toList();
      final upcoming = open
          .where((reminder) => !reminder.dueAt.isBefore(endToday))
          .toList();

      final money = businessContext.can(Cap.moneyView);
      final section = _boardSection == 1 && !money ? 0 : _boardSection;
      return BusinessPage(
        title: CustomerCrmHe.businessBoard,
        children: [
          CustomerCrmSyncStatus(store: _store),
          Text(
            DateFormat('EEEE, dd.MM', 'he').format(now),
            style: AppText.secondary.copyWith(color: context.palette.muted),
          ),
          const SizedBox(height: Space.l),
          Row(
            children: [
              for (final (index, label) in [
                (0, CustomerCrmHe.workTab),
                if (money) (1, CustomerCrmHe.remaining),
                (2, 'מעקבים'),
              ])
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: section == index,
                    child: InkWell(
                      key: Key('crm-board-$index'),
                      onTap: () => setState(() => _boardSection = index),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: section == index
                                  ? context.palette.ink
                                  : context.palette.line,
                              width: section == index ? 2 : 1,
                            ),
                          ),
                        ),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: AppText.body.copyWith(
                            color: section == index
                                ? context.palette.ink
                                : context.palette.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.l),
          if (section != 1) ...[
            TextField(
              key: const Key('crm-board-search'),
              onChanged: (value) => setState(() => _search = value),
              decoration: const InputDecoration(
                hintText: CustomerCrmHe.searchJobs,
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: Space.m),
          ],
          if (section == 1)
            CustomerCrmFinanceCard(
              jobs: _store.jobs,
              onOpenJob: (job) => widget.onOpenCustomer(job.customerId),
            ),
          if (section == 0) ...[
            Wrap(
              spacing: Space.s,
              children: [
                for (final (value, label) in const [
                  (0, CustomerCrmHe.allJobs),
                  (1, CustomerCrmHe.todayJobs),
                  (2, CustomerCrmHe.weekJobs),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _jobRange == value,
                    onSelected: (_) => setState(() => _jobRange = value),
                  ),
              ],
            ),
            const SizedBox(height: Space.m),
            if (visibleJobs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: Space.xl),
                child: Text(CustomerCrmHe.noMatchingJobs),
              ),
            for (final job in visibleJobs)
              Material(
                type: MaterialType.transparency,
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: SizedBox(
                        width: 58,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat('HH:mm').format(job.scheduledAt),
                              style: AppText.headline,
                            ),
                            Text(
                              DateFormat('dd.MM').format(job.scheduledAt),
                              style: AppText.secondary.copyWith(
                                color: context.palette.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      title: Text(job.customerName, style: AppText.headline),
                      subtitle: Text(
                        '${job.title}${job.address.isEmpty ? '' : '\n${job.address}'}',
                        style: AppText.secondary,
                      ),
                      trailing: IconButton(
                        tooltip: CustomerCrmHe.complete,
                        onPressed: !_canEdit || _updating.contains(job.id)
                            ? null
                            : () => unawaited(_completeJob(job)),
                        icon: const Icon(Icons.check_circle_outline),
                      ),
                      onTap: () => widget.onOpenCustomer(job.customerId),
                    ),
                    Divider(color: context.palette.line, height: 1),
                  ],
                ),
              ),
          ],
          if (section == 2) ...[
            if (overdue.isNotEmpty) ...[
              _AgendaHeading(
                title: 'באיחור',
                count: overdue.length,
                tone: context.palette.danger,
              ),
              for (final reminder in overdue) _tile(context, reminder),
            ],
            if (today.isNotEmpty) ...[
              _AgendaHeading(
                title: 'היום',
                count: today.length,
                tone: context.palette.info,
              ),
              for (final reminder in today) _tile(context, reminder),
            ],
            if (upcoming.isNotEmpty) ...[
              _AgendaHeading(
                title: 'בהמשך',
                count: upcoming.length,
                tone: context.palette.muted,
              ),
              for (final reminder in upcoming) _tile(context, reminder),
            ],
            if (open.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: Space.xl),
                child: Text('אין מעקבים פתוחים שמתאימים לחיפוש.'),
              ),
            if (done > 0)
              Padding(
                padding: const EdgeInsets.only(top: Space.m),
                child: Text(
                  '$done מעקבים הושלמו',
                  style: AppText.secondary.copyWith(
                    color: context.palette.muted,
                  ),
                ),
              ),
          ],
        ],
      );
    },
  );

  Widget _tile(BuildContext context, CustomerCrmReminder reminder) => Padding(
    padding: const EdgeInsets.only(bottom: Space.s),
    child: AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.l,
        vertical: Space.s,
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        minTileHeight: Hit.row,
        leading: IconButton(
          tooltip: reminder.completed
              ? CustomerCrmHe.markOpenAction
              : CustomerCrmHe.markDoneAction,
          onPressed: !_canEdit || _updating.contains(reminder.id)
              ? null
              : () => unawaited(_complete(reminder)),
          icon: _updating.contains(reminder.id)
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                )
              : Icon(
                  reminder.completed
                      ? Iconsax.tick_circle
                      : Iconsax.record_circle,
                  color: reminder.completed
                      ? context.palette.ok
                      : context.palette.info,
                ),
        ),
        title: Text(reminder.title, style: AppText.body),
        subtitle: Text(
          '${reminder.customerName} · ${DateFormat('dd.MM.yy · HH:mm').format(reminder.dueAt)}',
          style: AppText.secondary.copyWith(color: context.palette.muted),
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'אפשרויות לתזכורת',
          enabled: _canEdit && !_updating.contains(reminder.id),
          onSelected: (action) {
            if (action == 'edit') {
              unawaited(_edit(reminder));
            } else {
              unawaited(_delete(reminder));
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Iconsax.edit_2, size: 18),
                  SizedBox(width: Space.s),
                  Text(CustomerCrmHe.edit),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Iconsax.trash, size: 18),
                  SizedBox(width: Space.s),
                  Text(CustomerCrmHe.delete),
                ],
              ),
            ),
          ],
        ),
        onTap: () => widget.onOpenCustomer(reminder.customerId),
      ),
    ),
  );
}

class _AgendaHeading extends StatelessWidget {
  const _AgendaHeading({
    required this.title,
    required this.count,
    required this.tone,
  });

  final String title;
  final int count;
  final Color tone;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.s, top: Space.m),
    child: Row(
      children: [
        Text(title, style: AppText.headline),
        const SizedBox(width: Space.s),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 2),
          decoration: BoxDecoration(
            color: tone.withValues(alpha: .15),
            borderRadius: BorderRadius.circular(Radii.chip),
          ),
          child: Text(
            '$count',
            style: AppText.secondary.copyWith(
              color: tone,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class CustomerCrmReminderPreview extends StatefulWidget {
  const CustomerCrmReminderPreview({
    super.key,
    required this.businessId,
    required this.onOpenAgenda,
    required this.onOpenCustomer,
  });

  final String businessId;
  final VoidCallback onOpenAgenda;
  final ValueChanged<String> onOpenCustomer;

  @override
  State<CustomerCrmReminderPreview> createState() =>
      _CustomerCrmReminderPreviewState();
}

class _CustomerCrmReminderPreviewState
    extends State<CustomerCrmReminderPreview> {
  final CustomerCrmStore _store = CustomerCrmStore.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_store.loadForBusiness(widget.businessId));
  }

  @override
  void didUpdateWidget(covariant CustomerCrmReminderPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId) {
      unawaited(_store.loadForBusiness(widget.businessId));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _store,
    builder: (context, _) {
      if (!_store.isLoadedFor(widget.businessId)) {
        return const SizedBox.shrink();
      }
      final upcoming = [
        for (final reminder in _store.reminders.where(
          (item) => !item.completed,
        ))
          (
            customerId: reminder.customerId,
            customerName: reminder.customerName,
            title: reminder.title,
            dueAt: reminder.dueAt,
          ),
        for (final job in _store.jobs.where((item) => item.status.isOpen))
          (
            customerId: job.customerId,
            customerName: job.customerName,
            title: job.title,
            dueAt: job.scheduledAt,
          ),
        if (businessContext.can(Cap.moneyView))
          for (final job in _store.jobs.where(
            (item) =>
                item.status == CustomerCrmJobStatus.completed &&
                (item.budget.remainingMinor ?? 0) > 0,
          ))
            (
              customerId: job.customerId,
              customerName: job.customerName,
              title:
                  '${CustomerCrmHe.remaining}: ${crmMoney(job.budget.remainingMinor!)} · ${job.title}',
              dueAt: job.budget.paymentDueAt ?? job.scheduledAt,
            ),
      ]..sort((a, b) => a.dueAt.compareTo(b.dueAt));
      final reminders = upcoming.take(2).toList(growable: false);
      if (reminders.isEmpty) return const SizedBox.shrink();
      final first = reminders.first;
      final overdue = first.dueAt.isBefore(DateTime.now());
      return Padding(
        padding: const EdgeInsets.only(bottom: Space.l),
        child: AppCard(
          key: const Key('home-crm-reminders'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      overdue
                          ? 'יש משימות שממתינות לך'
                          : 'העבודה או המעקב הקרובים',
                      style: AppText.headline,
                    ),
                  ),
                  IconButton(
                    tooltip: CustomerCrmHe.businessBoard,
                    onPressed: widget.onOpenAgenda,
                    icon: const Icon(Iconsax.arrow_left_2),
                  ),
                ],
              ),
              for (final reminder in reminders)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    overdue && reminder == first
                        ? Iconsax.notification_bing
                        : Iconsax.calendar,
                    color: overdue && reminder == first
                        ? context.palette.danger
                        : context.palette.info,
                  ),
                  title: Text(reminder.title, style: AppText.body),
                  subtitle: Text(
                    '${reminder.customerName} · ${DateFormat('dd.MM.yy · HH:mm').format(reminder.dueAt)}',
                    style: AppText.secondary.copyWith(
                      color: context.palette.muted,
                    ),
                  ),
                  onTap: () => widget.onOpenCustomer(reminder.customerId),
                ),
              TextButton.icon(
                onPressed: widget.onOpenAgenda,
                icon: const Icon(Iconsax.arrow_left_2),
                label: const Text(CustomerCrmHe.businessBoard),
              ),
            ],
          ),
        ),
      );
    },
  );
}
