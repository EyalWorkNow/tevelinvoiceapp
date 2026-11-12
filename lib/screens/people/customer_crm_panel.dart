import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../state/customer_crm_store.dart';
import '../../ui/ds.dart';
import '../../util/labels/common_he.dart';
import '../../util/labels/customer_crm_he.dart';
import 'customer_crm_editors.dart';
import 'customer_crm_jobs.dart';
import 'customer_crm_finance_card.dart';
import 'customer_crm_sync_status.dart';

class CustomerCrmPanel extends StatefulWidget {
  const CustomerCrmPanel({
    super.key,
    required this.businessId,
    required this.customerId,
    required this.customerName,
    required this.canEdit,
    required this.onOpenAgenda,
    this.onCreateDocument,
    this.canViewMoney = false,
    this.onNavigate,
    this.onMessage,
  });

  final String businessId;
  final String customerId;
  final String customerName;
  final bool canEdit;
  final VoidCallback onOpenAgenda;
  final VoidCallback? onCreateDocument;
  final bool canViewMoney;
  final ValueChanged<CustomerCrmJob>? onNavigate, onMessage;

  @override
  State<CustomerCrmPanel> createState() => _CustomerCrmPanelState();
}

class _CustomerCrmPanelState extends State<CustomerCrmPanel> {
  final CustomerCrmStore _store = CustomerCrmStore.instance;
  bool _busy = false;
  int _section = 0;
  bool _showAllNotes = false;
  bool _showCompletedReminders = false;

  @override
  void initState() {
    super.initState();
    unawaited(_store.loadForBusiness(widget.businessId));
  }

  @override
  void didUpdateWidget(covariant CustomerCrmPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId) {
      unawaited(_store.loadForBusiness(widget.businessId));
    }
  }

  Future<void> _addNote() async {
    if (_busy || !widget.canEdit) return;
    final text = await _promptNote();
    if (text == null || !mounted) return;
    await _run(() => _store.addNote(widget.customerId, text));
    if (mounted) setState(() => _section = 1);
  }

  Future<void> _editNote(CustomerCrmNote note) async {
    if (_busy || !widget.canEdit) return;
    final text = await _promptNote(note: note);
    if (text == null || !mounted) return;
    await _run(() => _store.updateNote(widget.customerId, note.id, text));
  }

  Future<String?> _promptNote({CustomerCrmNote? note}) =>
      showCustomerNoteEditor(context, note: note);

  Future<void> _deleteNote(CustomerCrmNote note) async {
    if (_busy || !widget.canEdit) return;
    final confirmed = await _confirmDelete(
      title: 'למחוק את הפתק?',
      message: 'הפתק יוסר מהתיק של ${widget.customerName}.',
    );
    if (confirmed && mounted) {
      await _run(() => _store.deleteNote(widget.customerId, note.id));
    }
  }

  Future<void> _addReminder() async {
    if (_busy || !widget.canEdit) return;
    final reminder = await _promptReminder();
    if (reminder == null || !mounted) return;
    await _run(() => _store.addReminder(widget.customerId, reminder));
    if (mounted) setState(() => _section = 1);
  }

  Future<void> _editReminder(CustomerCrmReminder reminder) async {
    if (_busy || !widget.canEdit) return;
    final edited = await _promptReminder(reminder: reminder);
    if (edited == null || !mounted) return;
    await _run(() => _store.updateReminder(widget.customerId, edited));
  }

  Future<void> _deleteReminder(CustomerCrmReminder reminder) async {
    if (_busy || !widget.canEdit) return;
    final confirmed = await _confirmDelete(
      title: 'למחוק את התזכורת?',
      message: 'אפשר ליצור תזכורת חדשה בכל שלב.',
    );
    if (confirmed && mounted) {
      await _run(() => _store.deleteReminder(widget.customerId, reminder.id));
    }
  }

  Future<CustomerCrmReminder?> _promptReminder({
    CustomerCrmReminder? reminder,
  }) => showCustomerReminderEditor(
    context,
    customerId: widget.customerId,
    customerName: widget.customerName,
    reminder: reminder,
  );

  Future<void> _editJob({CustomerCrmJob? job, bool repeat = false}) async {
    if (_busy || !widget.canEdit) return;
    final businessId = widget.businessId;
    final customerId = widget.customerId;
    final saved = await showCustomerJobEditor(
      context,
      customerId: widget.customerId,
      customerName: widget.customerName,
      job: job,
      repeat: repeat,
      showMoney: widget.canViewMoney,
      onSave: (edited) async {
        if (!mounted ||
            !widget.canEdit ||
            widget.businessId != businessId ||
            widget.customerId != customerId ||
            !_store.isLoadedFor(businessId)) {
          throw StateError('CRM business changed before saving');
        }
        await (job == null || repeat
            ? _store.addJob(customerId, edited)
            : _store.updateJob(customerId, edited));
      },
    );
    if (saved != null && mounted) setState(() => _section = 0);
  }

  Future<void> _deleteJob(CustomerCrmJob job) async {
    final confirmed = await _confirmDelete(
      title: CustomerCrmHe.confirmDeleteJob,
      message: CustomerCrmHe.deleteJobBody,
    );
    if (confirmed && mounted) {
      await _run(() => _store.deleteJob(widget.customerId, job.id));
    }
  }

  Future<void> _toggleReminder(CustomerCrmReminder reminder) => _run(
    () => _store.setReminderCompleted(
      widget.customerId,
      reminder.id,
      !reminder.completed,
    ),
  );

  Future<bool> _confirmDelete({
    required String title,
    required String message,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(Iconsax.trash, color: context.palette.danger),
          title: Text(title),
          content: Text(message),
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
      ) ??
      false;

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy || !widget.canEdit) return;
    setState(() => _busy = true);
    try {
      if (!_store.isLoadedFor(widget.businessId)) {
        throw StateError('CRM business changed');
      }
      await operation();
    } on Object catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _store,
    builder: (context, _) {
      if (_store.hasLoadErrorFor(widget.businessId)) {
        return AppCard(
          child: Column(
            children: [
              const Text(CustomerCrmHe.loadError),
              TextButton(
                onPressed: () =>
                    unawaited(_store.loadForBusiness(widget.businessId)),
                child: const Text(CommonHe.retry),
              ),
            ],
          ),
        );
      }
      if (!_store.isLoadedFor(widget.businessId)) {
        return AppCard(
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: Space.s),
            child: Center(child: CircularProgressIndicator.adaptive()),
          ),
        );
      }

      final entry = _store.entryFor(widget.customerId);
      final notes = entry.notes.toList()
        ..sort(
          (a, b) => a.pinned == b.pinned
              ? b.createdAt.compareTo(a.createdAt)
              : a.pinned
              ? -1
              : 1,
        );
      final reminders = _store.remindersForCustomer(widget.customerId);
      final openReminders = reminders
          .where((reminder) => !reminder.completed)
          .toList(growable: false);
      final completedReminders = reminders
          .where((reminder) => reminder.completed)
          .toList(growable: false);
      final visibleNotes = _showAllNotes ? notes : notes.take(3).toList();

      final enabled = widget.canEdit && !_busy && _store.readyForEdits;
      return Column(
        key: const Key('person-crm'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CustomerCrmSyncStatus(store: _store),
          Row(
            children: [
              const Expanded(
                child: Text(CustomerCrmHe.title, style: AppText.title),
              ),
              PopupMenuButton<CustomerCrmStage>(
                enabled: enabled,
                tooltip: CustomerCrmHe.stage,
                onSelected: (stage) => unawaited(
                  _run(() => _store.setStage(widget.customerId, stage)),
                ),
                itemBuilder: (_) => [
                  for (final stage in CustomerCrmStage.values)
                    PopupMenuItem(value: stage, child: Text(stage.label)),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.stage.label,
                        style: AppText.secondary.copyWith(
                          color: context.palette.muted,
                        ),
                      ),
                      const Icon(Icons.expand_more, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.m),
          Wrap(
            spacing: Space.s,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                key: const Key('crm-add-job'),
                onPressed: enabled ? () => unawaited(_editJob()) : null,
                icon: const Icon(Icons.add, size: 19),
                label: const Text(CustomerCrmHe.newJob),
              ),
              TextButton(
                onPressed: enabled ? _addNote : null,
                child: const Text(CustomerCrmHe.newNote),
              ),
              TextButton(
                onPressed: enabled ? _addReminder : null,
                child: const Text(CustomerCrmHe.newReminder),
              ),
            ],
          ),
          const SizedBox(height: Space.m),
          Row(
            children: [
              for (final (index, label) in [
                (0, CustomerCrmHe.workTab),
                (1, CustomerCrmHe.followupTab),
                if (widget.canViewMoney) (2, CustomerCrmHe.moneyTab),
              ])
                Expanded(
                  child: Semantics(
                    selected: _section == index,
                    button: true,
                    child: InkWell(
                      key: Key('crm-section-$index'),
                      onTap: () => setState(() => _section = index),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: _section == index
                                  ? context.palette.ink
                                  : context.palette.line,
                              width: _section == index ? 2 : 1,
                            ),
                          ),
                        ),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: AppText.body.copyWith(
                            fontWeight: _section == index
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: _section == index
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
          const SizedBox(height: Space.m),
          if (_section == 0 || (_section == 2 && !widget.canViewMoney)) ...[
            for (final note in notes.where((note) => note.pinned))
              Container(
                key: ValueKey('crm-pinned-${note.id}'),
                margin: const EdgeInsets.only(bottom: Space.m),
                padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
                decoration: BoxDecoration(
                  border: BorderDirectional(
                    start: BorderSide(color: context.palette.warn, width: 2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      CustomerCrmHe.beforeArrival,
                      style: AppText.secondary.copyWith(
                        color: context.palette.muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(note.text, style: AppText.body),
                  ],
                ),
              ),
            CustomerCrmJobs(
              jobs: entry.jobs,
              enabled: enabled,
              onEdit: (job) => unawaited(_editJob(job: job)),
              onRepeat: (job) => unawaited(_editJob(job: job, repeat: true)),
              onDelete: (job) => unawaited(_deleteJob(job)),
              onStatus: (job, status) => unawaited(
                _run(
                  () => _store.setJobStatus(widget.customerId, job.id, status),
                ),
              ),
              onCreateDocument: !_busy ? widget.onCreateDocument : null,
              showMoney: widget.canViewMoney,
              onNavigate: widget.onNavigate,
              onMessage: widget.onMessage,
              onReschedule: (job, days) {
                final now = DateTime.now();
                final base = days == 1 || job.scheduledAt.isBefore(now)
                    ? now
                    : job.scheduledAt;
                final date = DateTime(
                  base.year,
                  base.month,
                  base.day + days,
                  job.scheduledAt.hour,
                  job.scheduledAt.minute,
                );
                unawaited(
                  _run(
                    () => _store.rescheduleJob(widget.customerId, job.id, date),
                  ),
                );
              },
              onChecklist: (job, itemId, done) => unawaited(
                _run(
                  () => _store.setChecklistCompleted(
                    widget.customerId,
                    job.id,
                    itemId,
                    done,
                  ),
                ),
              ),
            ),
          ],
          if (_section == 1) ...[
            Row(
              children: [
                const Expanded(
                  child: Text('לחזור ללקוח', style: AppText.headline),
                ),
                TextButton.icon(
                  key: const Key('crm-follow-tomorrow'),
                  onPressed: enabled
                      ? () {
                          final now = DateTime.now();
                          unawaited(
                            _run(
                              () => _store.addReminder(
                                widget.customerId,
                                CustomerCrmReminder.create(
                                  customerId: widget.customerId,
                                  customerName: widget.customerName,
                                  title: CustomerCrmHe.followUpWith(
                                    widget.customerName,
                                  ),
                                  dueAt: DateTime(
                                    now.year,
                                    now.month,
                                    now.day + 1,
                                    9,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }
                      : null,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text(CustomerCrmHe.followTomorrow),
                ),
              ],
            ),
            if (openReminders.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: Space.m),
                child: Text('אין מעקבים פתוחים.', style: AppText.secondary),
              ),
            for (final reminder in openReminders)
              _ReminderRow(
                reminder: reminder,
                busy: _busy,
                canEdit: widget.canEdit && _store.readyForEdits,
                onToggle: () => unawaited(_toggleReminder(reminder)),
                onEdit: () => unawaited(_editReminder(reminder)),
                onDelete: () => unawaited(_deleteReminder(reminder)),
              ),
            if (completedReminders.isNotEmpty) ...[
              TextButton(
                onPressed: () => setState(
                  () => _showCompletedReminders = !_showCompletedReminders,
                ),
                child: Text(
                  _showCompletedReminders
                      ? CustomerCrmHe.hideCompletedFollowups
                      : CustomerCrmHe.completedFollowupsCount(
                          completedReminders.length,
                        ),
                ),
              ),
              if (_showCompletedReminders)
                for (final reminder in completedReminders)
                  _ReminderRow(
                    reminder: reminder,
                    busy: _busy,
                    canEdit: widget.canEdit && _store.readyForEdits,
                    onToggle: () => unawaited(_toggleReminder(reminder)),
                    onEdit: () => unawaited(_editReminder(reminder)),
                    onDelete: () => unawaited(_deleteReminder(reminder)),
                  ),
            ],
            const SizedBox(height: Space.m),
            Divider(color: context.palette.line),
            const SizedBox(height: Space.m),
            Text('פתקים (${notes.length})', style: AppText.headline),
            if (notes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: Space.m),
                child: Text(
                  'קוד לשער, העדפות או סיכום שיחה — מה שצריך לזכור לפעם הבאה.',
                  style: AppText.secondary,
                ),
              ),
            for (final note in visibleNotes)
              _NoteRow(
                note: note,
                canEdit: widget.canEdit && _store.readyForEdits,
                busy: _busy,
                onEdit: () => unawaited(_editNote(note)),
                onDelete: () => unawaited(_deleteNote(note)),
                onPin: () => unawaited(
                  _run(
                    () => _store.setNotePinned(
                      widget.customerId,
                      note.id,
                      !note.pinned,
                    ),
                  ),
                ),
              ),
            if (notes.length > 3)
              TextButton(
                onPressed: () => setState(() => _showAllNotes = !_showAllNotes),
                child: Text(
                  _showAllNotes
                      ? CustomerCrmHe.fewerNotes
                      : CustomerCrmHe.allNotesCount(notes.length),
                ),
              ),
          ],
          if (_section == 2 && widget.canViewMoney)
            CustomerCrmFinanceCard(
              jobs: entry.jobs,
              onOpenJob: (job) => unawaited(_editJob(job: job)),
            ),
          const SizedBox(height: Space.m),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: widget.onOpenAgenda,
              icon: const Icon(Iconsax.calendar_1, size: 18),
              label: const Text(CustomerCrmHe.businessBoard),
            ),
          ),
          const SizedBox(height: Space.s),
          Text(
            CustomerCrmHe.local,
            style: AppText.secondary.copyWith(color: context.palette.muted),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
        ],
      );
    },
  );
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.note,
    required this.canEdit,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
    required this.onPin,
  });

  final CustomerCrmNote note;
  final VoidCallback onPin;
  final bool canEdit;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            note.pinned ? Icons.push_pin_outlined : Iconsax.note_text,
            size: 17,
            color: context.palette.muted,
          ),
        ),
        const SizedBox(width: Space.s),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(note.text, style: AppText.body),
              const SizedBox(height: 3),
              Text(
                '${note.pinned ? 'מוצמד · ' : ''}${_noteTimestamp(note)}',
                style: AppText.secondary.copyWith(color: context.palette.muted),
              ),
            ],
          ),
        ),
        if (canEdit)
          _ItemMenu(
            enabled: !busy,
            onEdit: onEdit,
            onDelete: onDelete,
            onPin: onPin,
            pinned: note.pinned,
          ),
      ],
    ),
  );
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    required this.reminder,
    required this.busy,
    required this.canEdit,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final CustomerCrmReminder reminder;
  final bool busy;
  final bool canEdit;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          tooltip: reminder.completed
              ? CustomerCrmHe.reopenFollowup
              : CustomerCrmHe.completeFollowup,
          visualDensity: VisualDensity.compact,
          onPressed: busy || !canEdit ? null : onToggle,
          icon: Icon(
            reminder.completed ? Iconsax.tick_circle : Iconsax.record_circle,
            color: reminder.completed
                ? context.palette.ok
                : context.palette.info,
          ),
        ),
        const SizedBox(width: Space.xs),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reminder.title, style: AppText.body),
                const SizedBox(height: 3),
                Text(
                  _reminderTimestamp(context, reminder.dueAt),
                  style: AppText.secondary.copyWith(
                    color: _isOverdue(reminder.dueAt)
                        ? context.palette.danger
                        : context.palette.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (canEdit)
          _ItemMenu(enabled: !busy, onEdit: onEdit, onDelete: onDelete),
      ],
    ),
  );
}

class _ItemMenu extends StatelessWidget {
  const _ItemMenu({
    required this.enabled,
    required this.onEdit,
    required this.onDelete,
    this.onPin,
    this.pinned = false,
  });

  final bool enabled;
  final VoidCallback? onPin;
  final bool pinned;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'אפשרויות',
    enabled: enabled,
    onSelected: (value) {
      if (value == 'pin') {
        onPin?.call();
      } else if (value == 'edit') {
        onEdit();
      } else {
        onDelete();
      }
    },
    itemBuilder: (context) => [
      if (onPin != null)
        PopupMenuItem(
          value: 'pin',
          child: Text(pinned ? CustomerCrmHe.unpinNote : CustomerCrmHe.pinNote),
        ),
      const PopupMenuItem(
        value: 'edit',
        child: Row(
          children: [
            Icon(Iconsax.edit_2, size: 18),
            SizedBox(width: Space.s),
            Text(CustomerCrmHe.edit),
          ],
        ),
      ),
      const PopupMenuItem(
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
    icon: const Icon(Iconsax.more),
  );
}

String _noteTimestamp(CustomerCrmNote note) {
  final created = DateFormat('dd.MM.yyyy · HH:mm').format(note.createdAt);
  final updatedAt = note.updatedAt;
  if (updatedAt == null) return created;
  return '$created · נערך ${DateFormat('dd.MM · HH:mm').format(updatedAt)}';
}

String _reminderTimestamp(BuildContext context, DateTime dateTime) {
  final local = dateTime.toLocal();
  final today = DateTime.now();
  final startToday = DateTime(today.year, today.month, today.day);
  final day = DateTime(local.year, local.month, local.day);
  final dayLabel = day == startToday
      ? 'היום'
      : day == startToday.add(const Duration(days: 1))
      ? 'מחר'
      : DateFormat('dd.MM.yyyy').format(local);
  return '$dayLabel · ${TimeOfDay.fromDateTime(local).format(context)}';
}

bool _isOverdue(DateTime dueAt) {
  final now = DateTime.now();
  return !dueAt.isAfter(now);
}
