// CRM edits used by the customer page and its "ביקורים ופגישות" page: the
// existing editors (job / note / reminder) and store methods, with the same
// guards as the old CRM panel (business switched → nothing is written).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../state/customer_crm_store.dart';
import '../../ui/ds.dart';
import '../../util/labels/common_he.dart';
import '../../util/labels/customer_crm_he.dart';
import '../../util/labels/person_page_he.dart';
import 'customer_crm_editors.dart';

class PersonCrmOps {
  PersonCrmOps({
    required this.businessId,
    required this.customerId,
    required this.customerName,
    this.store,
  });

  final String businessId;
  final String customerId;
  final String customerName;
  final CustomerCrmStore? store;

  CustomerCrmStore get _store => store ?? CustomerCrmStore.instance;

  bool get ready => _store.isLoadedFor(businessId) && _store.readyForEdits;

  /// Runs [op]; a failure becomes the usual error snack.
  Future<bool> run(BuildContext context, Future<void> Function() op) async {
    try {
      if (!_store.isLoadedFor(businessId)) {
        throw StateError('CRM business changed');
      }
      await op();
      return true;
    } on Object catch (e) {
      if (context.mounted) showErrorSnack(context, e);
      return false;
    }
  }

  Future<void> editJob(
    BuildContext context, {
    CustomerCrmJob? job,
    bool repeat = false,
    bool showMoney = false,
  }) async {
    if (!ready) return;
    await showCustomerJobEditor(
      context,
      customerId: customerId,
      customerName: customerName,
      job: job,
      repeat: repeat,
      showMoney: showMoney,
      onSave: (edited) async {
        if (!_store.isLoadedFor(businessId)) {
          throw StateError('CRM business changed before saving');
        }
        await (job == null || repeat
            ? _store.addJob(customerId, edited)
            : _store.updateJob(customerId, edited));
      },
    );
  }

  Future<void> deleteJob(BuildContext context, CustomerCrmJob job) async {
    if (await confirmDelete(
          context,
          title: CustomerCrmHe.confirmDeleteJob,
          message: CustomerCrmHe.deleteJobBody,
        ) &&
        context.mounted) {
      await run(context, () => _store.deleteJob(customerId, job.id));
    }
  }

  Future<void> setJobStatus(
    BuildContext context,
    CustomerCrmJob job,
    CustomerCrmJobStatus status,
  ) => run(context, () => _store.setJobStatus(customerId, job.id, status));

  Future<void> reschedule(BuildContext context, CustomerCrmJob job, int days) {
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
    return run(context, () => _store.rescheduleJob(customerId, job.id, date));
  }

  Future<void> setChecklist(
    BuildContext context,
    CustomerCrmJob job,
    String itemId,
    bool done,
  ) => run(
    context,
    () => _store.setChecklistCompleted(customerId, job.id, itemId, done),
  );

  Future<bool> addNote(BuildContext context) async {
    if (!ready) return false;
    final text = await showCustomerNoteEditor(context);
    if (text == null || !context.mounted) return false;
    return run(context, () => _store.addNote(customerId, text));
  }

  Future<void> editNote(BuildContext context, CustomerCrmNote note) async {
    if (!ready) return;
    final text = await showCustomerNoteEditor(context, note: note);
    if (text == null || !context.mounted) return;
    await run(context, () => _store.updateNote(customerId, note.id, text));
  }

  Future<void> pinNote(BuildContext context, CustomerCrmNote note) => run(
    context,
    () => _store.setNotePinned(customerId, note.id, !note.pinned),
  );

  Future<void> deleteNote(BuildContext context, CustomerCrmNote note) async {
    if (await confirmDelete(
          context,
          title: PersonCrmHe.deleteNoteTitle,
          message: PersonCrmHe.deleteNoteBody(customerName),
        ) &&
        context.mounted) {
      await run(context, () => _store.deleteNote(customerId, note.id));
    }
  }

  Future<void> editReminder(
    BuildContext context,
    CustomerCrmReminder reminder,
  ) async {
    if (!ready) return;
    final edited = await showCustomerReminderEditor(
      context,
      customerId: customerId,
      customerName: customerName,
      reminder: reminder,
    );
    if (edited == null || !context.mounted) return;
    await run(context, () => _store.updateReminder(customerId, edited));
  }

  Future<void> toggleReminder(
    BuildContext context,
    CustomerCrmReminder reminder,
  ) => run(
    context,
    () => _store.setReminderCompleted(
      customerId,
      reminder.id,
      !reminder.completed,
    ),
  );

  Future<void> deleteReminder(
    BuildContext context,
    CustomerCrmReminder reminder,
  ) async {
    if (await confirmDelete(
          context,
          title: PersonCrmHe.deleteReminderTitle,
          message: PersonCrmHe.deleteReminderBody,
        ) &&
        context.mounted) {
      await run(context, () => _store.deleteReminder(customerId, reminder.id));
    }
  }

  /// "תזכורת לעצמי": מחר / בעוד שבוע / a date + an optional text.
  Future<bool> quickReminder(BuildContext context) async {
    if (!ready) return false;
    final r = await showAppSheet<CustomerCrmReminder>(
      context,
      builder: (_) => QuickReminderSheet(
        customerId: customerId,
        customerName: customerName,
      ),
    );
    if (r == null || !context.mounted) return false;
    return run(context, () => _store.addReminder(customerId, r));
  }
}

Future<bool> confirmDelete(
  BuildContext context, {
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
            key: const Key('crm-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Iconsax.trash),
            label: const Text(CustomerCrmHe.delete),
          ),
        ],
      ),
    ) ??
    false;

enum _When { tomorrow, week, date }

/// The small "תזכורת לעצמי" sheet: when (מחר · בעוד שבוע · בחירת תאריך,
/// 09:00) and what (optional; "לחזור ל…" by default).
class QuickReminderSheet extends StatefulWidget {
  const QuickReminderSheet({
    super.key,
    required this.customerId,
    required this.customerName,
    this.now,
  });

  final String customerId;
  final String customerName;
  final DateTime? now;

  @override
  State<QuickReminderSheet> createState() => _QuickReminderSheetState();
}

class _QuickReminderSheetState extends State<QuickReminderSheet> {
  _When _when = _When.tomorrow;
  DateTime? _date;
  final _text = TextEditingController();

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  DateTime get _due {
    final n = _now;
    final day = switch (_when) {
      _When.tomorrow => DateTime(n.year, n.month, n.day + 1),
      _When.week => DateTime(n.year, n.month, n.day + 7),
      _When.date => _date ?? DateTime(n.year, n.month, n.day + 1),
    };
    return DateTime(day.year, day.month, day.day, 9);
  }

  Future<void> _pickDate() async {
    final n = _now;
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime(n.year, n.month, n.day + 1),
      firstDate: DateTime(n.year, n.month, n.day),
      lastDate: DateTime(n.year + 2, n.month, n.day),
    );
    if (picked != null && mounted) {
      setState(() {
        _date = picked;
        _when = _When.date;
      });
    }
  }

  void _save() {
    final title = _text.text.trim().isEmpty
        ? PersonPageHe.reminderDefault(widget.customerName)
        : _text.text.trim();
    Navigator.of(context).pop(
      CustomerCrmReminder.create(
        customerId: widget.customerId,
        customerName: widget.customerName,
        title: title,
        dueAt: _due,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final date = _date;
    final dateLabel = date == null
        ? PersonPageHe.pickDate
        : '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(PersonPageHe.reminderTitle, subtitle: widget.customerName),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.xs,
          children: [
            ChoiceChip(
              key: const Key('quick-reminder-tomorrow'),
              label: const Text(PersonPageHe.tomorrow),
              selected: _when == _When.tomorrow,
              onSelected: (_) => setState(() => _when = _When.tomorrow),
            ),
            ChoiceChip(
              key: const Key('quick-reminder-week'),
              label: const Text(PersonPageHe.inWeek),
              selected: _when == _When.week,
              onSelected: (_) => setState(() => _when = _When.week),
            ),
            ChoiceChip(
              key: const Key('quick-reminder-date'),
              avatar: const Icon(Iconsax.calendar_1, size: 16),
              label: Text(dateLabel),
              selected: _when == _When.date,
              onSelected: (_) => unawaited(_pickDate()),
            ),
          ],
        ),
        const SizedBox(height: Space.m),
        TextField(
          key: const Key('quick-reminder-text'),
          controller: _text,
          maxLength: 200,
          decoration: InputDecoration(
            labelText: PersonPageHe.reminderText,
            counterText: '',
            hintText: PersonPageHe.reminderDefault(widget.customerName),
          ),
        ),
        const SizedBox(height: Space.s),
        PrimaryButton(
          key: const Key('quick-reminder-save'),
          label: PersonPageHe.saveReminder,
          onPressed: _save,
        ),
      ],
    );
  }
}
