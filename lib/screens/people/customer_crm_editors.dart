import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../state/customer_crm_store.dart';
import '../../state/customer_crm_job_budget.dart';
import '../../ui/ds.dart';
import '../../util/labels/common_he.dart';
import '../../util/labels/customer_crm_he.dart';
import 'confirm_discard.dart';
import 'customer_crm_job_fields.dart';

Future<String?> showCustomerNoteEditor(
  BuildContext context, {
  CustomerCrmNote? note,
}) => showDialog<String>(
  context: context,
  builder: (_) => _NoteEditor(note: note),
);

/// The controller belongs to the route's widget, including its exit animation.
class _NoteEditor extends StatefulWidget {
  const _NoteEditor({this.note});
  final CustomerCrmNote? note;
  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  final _form = GlobalKey<FormState>();
  late final _text = TextEditingController(text: widget.note?.text ?? '');
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, _text.text.trim());
    }
  }

  /// A tap outside or a back swipe asks first when the text changed (06·9).
  Future<void> _leave(bool didPop, Object? _) async {
    if (didPop) return;
    final changed = _text.text.trim() != (widget.note?.text ?? '').trim();
    if (changed && !await confirmDiscardChanges(context)) return;
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PopScope<String>(
    canPop: false,
    onPopInvokedWithResult: _leave,
    child: _dialog(context),
  );

  Widget _dialog(BuildContext context) => AlertDialog(
    title: Text(
      widget.note == null ? CustomerCrmHe.noteTitle : CustomerCrmHe.editNote,
    ),
    scrollable: true,
    content: Form(
      key: _form,
      child: TextFormField(
        key: const Key('crm-note-text'),
        controller: _text,
        autofocus: true,
        minLines: 3,
        maxLines: 7,
        maxLength: 2000,
        validator: _required,
        decoration: const InputDecoration(
          labelText: CustomerCrmHe.noteLabel,
          hintText: CustomerCrmHe.noteHint,
          alignLabelWithHint: true,
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text(CommonHe.cancel),
      ),
      FilledButton.icon(
        key: const Key('crm-note-save'),
        onPressed: _save,
        icon: const Icon(Iconsax.note_add),
        label: Text(
          widget.note == null
              ? CustomerCrmHe.saveNote
              : CustomerCrmHe.saveChanges,
        ),
      ),
    ],
  );
}

String? _required(String? text) =>
    text == null || text.trim().isEmpty ? CustomerCrmHe.required : null;

Future<CustomerCrmReminder?> showCustomerReminderEditor(
  BuildContext context, {
  required String customerId,
  required String customerName,
  CustomerCrmReminder? reminder,
}) => showDialog<CustomerCrmReminder>(
  context: context,
  builder: (_) => _WorkEditor(
    customerId: customerId,
    customerName: customerName,
    reminder: reminder,
  ),
);

Future<CustomerCrmJob?> showCustomerJobEditor(
  BuildContext context, {
  required String customerId,
  required String customerName,
  CustomerCrmJob? job,
  bool repeat = false,
  bool showMoney = false,
  Future<void> Function(CustomerCrmJob)? onSave,
}) => showDialog<CustomerCrmJob>(
  context: context,
  builder: (_) => _WorkEditor(
    customerId: customerId,
    customerName: customerName,
    job: job,
    isJob: true,
    repeat: repeat,
    showMoney: showMoney,
    onSaveJob: onSave,
  ),
);

class _WorkEditor extends StatefulWidget {
  const _WorkEditor({
    required this.customerId,
    required this.customerName,
    this.reminder,
    this.job,
    this.isJob = false,
    this.repeat = false,
    this.showMoney = false,
    this.onSaveJob,
  });
  final String customerId;
  final String customerName;
  final CustomerCrmReminder? reminder;
  final CustomerCrmJob? job;
  final bool isJob;
  final bool repeat;
  final bool showMoney;
  final Future<void> Function(CustomerCrmJob)? onSaveJob;
  @override
  State<_WorkEditor> createState() => _WorkEditorState();
}

class _WorkEditorState extends State<_WorkEditor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(
    text: widget.isJob
        ? widget.job?.title ?? ''
        : widget.reminder?.title ?? 'שיחת מעקב עם ${widget.customerName}',
  );
  late final _address = TextEditingController(text: widget.job?.address ?? '');
  late final _details = TextEditingController(text: widget.job?.details ?? '');
  late final _jobDraft = CustomerCrmJobDraft(widget.job, repeat: widget.repeat);
  late DateTime _date;
  late TimeOfDay _time;
  bool _saving = false;
  bool _detailsOpen = false;
  String? _saveError;
  bool get _editing =>
      !widget.repeat && (widget.job != null || widget.reminder != null);

  @override
  void initState() {
    super.initState();
    _detailsOpen = _editing;
    final now = DateTime.now();
    final original = widget.reminder?.dueAt ?? widget.job?.scheduledAt;
    _date = widget.repeat
        ? widget.job!.nextVisitAt(now)
        : original ?? DateTime(now.year, now.month, now.day + 1);
    _time = original == null
        ? const TimeOfDay(hour: 9, minute: 0)
        : TimeOfDay.fromDateTime(original);
    _initial = _signature;
  }

  late final String _initial;

  /// Everything the user can change; compared with the opening state.
  String get _signature => [
    _title.text,
    _address.text,
    _details.text,
    _date,
    _time,
    _jobDraft.price.text,
    _jobDraft.cost.text,
    _jobDraft.minutes.text,
    _jobDraft.paid.text,
    _jobDraft.tasks.text,
    _jobDraft.paymentDueAt,
    _jobDraft.repeatEveryDays,
  ].join('\u0000');

  /// A tap outside or a back swipe asks first when something changed (06·9).
  Future<void> _leave(bool didPop, Object? _) async {
    if (didPop || _saving) return;
    if (_signature != _initial && !await confirmDiscardChanges(context)) {
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _title.dispose();
    _address.dispose();
    _details.dispose();
    _jobDraft.dispose();
    super.dispose();
  }

  void _fillTemplate(bool garden) {
    setState(() {
      if (_title.text.trim().isEmpty) {
        _title.text = garden
            ? CustomerCrmHe.gardenVisit
            : CustomerCrmHe.serviceVisit;
      }
      if (_jobDraft.tasks.text.trim().isEmpty) {
        _jobDraft.tasks.text = garden
            ? 'לתאם גישה לחצר\nלהביא ציוד גינון\nלבדוק השקיה'
            : 'לתאם הגעה\nלהכין ציוד וחלקים\nלבדוק תקינות בסיום';
      }
      if (garden && _jobDraft.repeatEveryDays == 0) {
        _jobDraft.repeatEveryDays = 14;
      }
    });
  }

  Future<void> _chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2200),
    );
    if (selected != null && mounted) setState(() => _date = selected);
  }

  Future<void> _chooseTime() async {
    final selected = await showTimePicker(context: context, initialTime: _time);
    if (selected != null && mounted) setState(() => _time = selected);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_form.currentState!.validate()) {
      if (widget.isJob && _title.text.trim().isNotEmpty) {
        setState(() => _detailsOpen = true);
      }
      return;
    }
    final scheduled = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );
    if (widget.isJob) {
      final job = _editing
          ? widget.job!.copyWith(
              title: _title.text.trim(),
              address: _address.text.trim(),
              details: _details.text.trim(),
              scheduledAt: scheduled,
              budget: widget.showMoney ? _jobDraft.budget : widget.job!.budget,
              repeatEveryDays: _jobDraft.repeatEveryDays,
              checklist: _jobDraft.checklist,
            )
          : CustomerCrmJob.create(
              customerId: widget.customerId,
              customerName: widget.customerName,
              title: _title.text.trim(),
              address: _address.text.trim(),
              details: _details.text.trim(),
              scheduledAt: scheduled,
              budget: widget.showMoney
                  ? _jobDraft.budget
                  : const CustomerCrmJobBudget(),
              repeatEveryDays: _jobDraft.repeatEveryDays,
              checklist: _jobDraft.checklist,
            );
      setState(() {
        _saving = true;
        _saveError = null;
      });
      try {
        await widget.onSaveJob?.call(job);
        if (mounted) Navigator.pop(context, job);
      } on Object {
        if (mounted) setState(() => _saveError = CustomerCrmHe.saveError);
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    } else {
      final reminder =
          widget.reminder?.copyWith(
            title: _title.text.trim(),
            dueAt: scheduled,
          ) ??
          CustomerCrmReminder.create(
            customerId: widget.customerId,
            customerName: widget.customerName,
            title: _title.text.trim(),
            dueAt: scheduled,
          );
      Navigator.pop(context, reminder);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<Object>(
    canPop: false,
    onPopInvokedWithResult: _leave,
    child: AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        widget.isJob
            ? (_editing ? CustomerCrmHe.editJob : CustomerCrmHe.newJob)
            : (_editing
                  ? CustomerCrmHe.editReminder
                  : CustomerCrmHe.reminderTitle),
      ),
      scrollable: true,
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_saveError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.m),
                child: Text(
                  _saveError!,
                  style: AppText.body.copyWith(color: context.palette.danger),
                ),
              ),
            if (widget.isJob && !_editing)
              Wrap(
                spacing: Space.s,
                children: [
                  TextButton(
                    key: const Key('crm-template-service'),
                    onPressed: () => _fillTemplate(false),
                    child: const Text(CustomerCrmHe.serviceVisit),
                  ),
                  TextButton(
                    key: const Key('crm-template-garden'),
                    onPressed: () => _fillTemplate(true),
                    child: const Text(CustomerCrmHe.gardenVisit),
                  ),
                ],
              ),
            TextFormField(
              key: const Key('crm-work-title'),
              controller: _title,
              autofocus: true,
              maxLength: 120,
              validator: _required,
              decoration: InputDecoration(
                counterText: '',
                labelText: widget.isJob
                    ? CustomerCrmHe.jobTitle
                    : CustomerCrmHe.reminderLabel,
                hintText: widget.isJob ? CustomerCrmHe.jobHint : null,
              ),
            ),
            if (widget.isJob) ...[
              TextFormField(
                key: const Key('crm-work-address'),
                controller: _address,
                maxLength: 250,
                decoration: const InputDecoration(
                  labelText: CustomerCrmHe.address,
                  counterText: '',
                ),
              ),
            ],
            const SizedBox(height: Space.s),
            Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                OutlinedButton.icon(
                  key: const Key('crm-work-date'),
                  onPressed: _chooseDate,
                  icon: const Icon(Iconsax.calendar),
                  label: Text(DateFormat('dd.MM.yy').format(_date)),
                ),
                OutlinedButton.icon(
                  key: const Key('crm-work-time'),
                  onPressed: _chooseTime,
                  icon: const Icon(Iconsax.clock),
                  label: Text(_time.format(context)),
                ),
              ],
            ),
            if (widget.isJob) ...[
              const SizedBox(height: Space.s),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const Key('crm-job-more'),
                  onPressed: () => setState(() => _detailsOpen = !_detailsOpen),
                  icon: Icon(
                    _detailsOpen ? Icons.expand_less : Icons.expand_more,
                  ),
                  label: Text(
                    _detailsOpen
                        ? CustomerCrmHe.lessDetails
                        : CustomerCrmHe.moreDetails,
                  ),
                ),
              ),
              Visibility(
                visible: _detailsOpen,
                maintainState: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      key: const Key('crm-work-details'),
                      controller: _details,
                      maxLength: 1000,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: CustomerCrmHe.details,
                        counterText: '',
                      ),
                    ),
                    CustomerCrmJobFields(
                      key: ValueKey(_jobDraft.repeatEveryDays),
                      draft: _jobDraft,
                      showMoney: widget.showMoney,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text(CommonHe.cancel),
        ),
        FilledButton.icon(
          key: const Key('crm-work-save'),
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Iconsax.tick_circle),
          label: Text(
            _editing
                ? CustomerCrmHe.saveChanges
                : (widget.isJob
                      ? CustomerCrmHe.saveJob
                      : CustomerCrmHe.saveReminder),
          ),
        ),
      ],
    ),
  );
}
