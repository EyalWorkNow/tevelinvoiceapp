// Building blocks of the customer page (כרטיס לקוח v2): section titles with
// "הכל", visit / note / follow-up rows, label-value detail rows and the
// "תזכורות תשלום אוטומטיות" switch. Rows put the label at the start (right)
// and the value / amount at the end (left) of the row.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/collection_reminders_api.dart' show saveReminderHold;
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../state/customer_crm_store.dart';
import '../../state/session.dart';
import '../../ui/ds.dart';
import '../../util/labels/customer_crm_he.dart';
import '../../util/labels/person_page_he.dart';
import '../debts/reminder_hold_tile.dart' show loadReminderHold;
import 'person_logic.dart';

/// "מסמכים ············ הכל".
class PersonSectionTitle extends StatelessWidget {
  const PersonSectionTitle({
    super.key,
    required this.title,
    this.onAll,
    this.allLabel = PersonPageHe.all,
    this.allKey,
  });

  final String title;
  final VoidCallback? onAll;
  final String allLabel;
  final Key? allKey;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.page, Space.l, Space.page, 0),
    child: SizedBox(
      height: Hit.min,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: AppText.title),
            ),
          ),
          if (onAll != null)
            TextButton(key: allKey, onPressed: onAll, child: Text(allLabel)),
        ],
      ),
    ),
  );
}

/// A small status word in a soft pill.
class PersonTag extends StatelessWidget {
  const PersonTag(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.palette.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Text(text, style: AppText.secondary.copyWith(color: c)),
    );
  }
}

class _RowIcon extends StatelessWidget {
  const _RowIcon(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: context.palette.line.withValues(alpha: .6),
      shape: BoxShape.circle,
    ),
    child: Icon(icon, size: 20, color: context.palette.ink),
  );
}

/// One row of "ביקורים ופגישות": when · what · tag.
class PersonVisitRow extends StatelessWidget {
  const PersonVisitRow({
    super.key,
    required this.item,
    required this.now,
    this.onTap,
  });

  final VisitItem item;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final job = item.job;
    final b = item.booking;
    final what = job != null
        ? [job.title, if (job.address.isNotEmpty) job.address].join(' · ')
        : [
            PersonPageHe.meeting,
            if ((b!.notes ?? '').isNotEmpty) b.notes!,
          ].join(' · ');
    final tag = item.tag(now);
    final tone = tag == PersonPageHe.tagOverdue
        ? p.danger
        : tag == PersonPageHe.tagPending
        ? p.warn
        : tag == PersonPageHe.tagActive
        ? p.info
        : p.ok;
    return InkWell(
      key: Key('person-visit-${item.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.page,
          vertical: Space.s,
        ),
        child: Row(
          children: [
            _RowIcon(job != null ? Iconsax.briefcase : Iconsax.calendar_1),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    whenLabel(item.at),
                    style: AppText.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    what,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.secondary.copyWith(color: p.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.s),
            PersonTag(tag, color: tone),
          ],
        ),
      ),
    );
  }
}

/// "לפני שמגיעים": a pinned note, shown above the nearest visit only.
class PersonBeforeArrival extends StatelessWidget {
  const PersonBeforeArrival({super.key, required this.note});
  final CustomerCrmNote note;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.page, Space.xs, Space.page, 0),
    child: Container(
      key: ValueKey('crm-pinned-${note.id}'),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: context.palette.warn.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: BorderDirectional(
          start: BorderSide(color: context.palette.warn, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            CustomerCrmHe.beforeArrival,
            style: AppText.secondary.copyWith(color: context.palette.muted),
          ),
          const SizedBox(height: 2),
          Text(note.text, style: AppText.body),
        ],
      ),
    ),
  );
}

/// An open follow-up: ◯ (complete) · title / when · "באיחור".
class PersonReminderRow extends StatelessWidget {
  const PersonReminderRow({
    super.key,
    required this.reminder,
    required this.now,
    this.onToggle,
    this.onTap,
    this.onDelete,
  });

  final CustomerCrmReminder reminder;
  final DateTime now;
  final VoidCallback? onToggle;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final late = !reminder.completed && !reminder.dueAt.isAfter(now);
    return InkWell(
      key: Key('person-reminder-${reminder.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          Space.s,
          Space.xs,
          Space.page,
          Space.xs,
        ),
        child: Row(
          children: [
            IconButton(
              key: Key('person-reminder-done-${reminder.id}'),
              tooltip: CustomerCrmHe.completeFollowup,
              onPressed: onToggle,
              icon: Icon(
                reminder.completed
                    ? Iconsax.tick_circle
                    : Iconsax.record_circle,
                color: late ? p.danger : p.info,
              ),
            ),
            const SizedBox(width: Space.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reminder.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    whenLabel(reminder.dueAt),
                    style: AppText.secondary.copyWith(color: p.muted),
                  ),
                ],
              ),
            ),
            if (late) ...[
              const SizedBox(width: Space.s),
              PersonTag(PersonPageHe.tagOverdue, color: p.danger),
            ],
            if (onDelete != null) _RowMenu(onEdit: onTap, onDelete: onDelete!),
          ],
        ),
      ),
    );
  }
}

/// A note: icon · text / date (pinned notes marked).
class PersonNoteRow extends StatelessWidget {
  const PersonNoteRow({
    super.key,
    required this.note,
    this.onTap,
    this.onPin,
    this.onDelete,
  });

  final CustomerCrmNote note;
  final VoidCallback? onTap;
  final VoidCallback? onPin;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      key: Key('person-note-${note.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.page,
          vertical: Space.s,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Icon(
                note.pinned ? Icons.push_pin_outlined : Iconsax.note_text,
                size: 20,
                color: p.muted,
              ),
            ),
            const SizedBox(width: Space.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (note.pinned) CustomerCrmHe.beforeArrival,
                      dayWithWeekday(note.createdAt),
                    ].join(' · '),
                    style: AppText.secondary.copyWith(color: p.muted),
                  ),
                ],
              ),
            ),
            if (onDelete != null)
              _RowMenu(
                onEdit: onTap,
                onDelete: onDelete!,
                onPin: onPin,
                pinned: note.pinned,
              ),
          ],
        ),
      ),
    );
  }
}

class _RowMenu extends StatelessWidget {
  const _RowMenu({
    required this.onEdit,
    required this.onDelete,
    this.onPin,
    this.pinned = false,
  });

  final VoidCallback? onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onPin;
  final bool pinned;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: CustomerCrmHe.edit,
    icon: Icon(Icons.more_horiz, size: 22, color: context.palette.muted),
    onSelected: (v) => switch (v) {
      'pin' => onPin?.call(),
      'edit' => onEdit?.call(),
      _ => onDelete(),
    },
    itemBuilder: (_) => [
      if (onPin != null)
        PopupMenuItem(
          value: 'pin',
          child: Text(pinned ? CustomerCrmHe.unpinNote : CustomerCrmHe.pinNote),
        ),
      if (onEdit != null)
        const PopupMenuItem(value: 'edit', child: Text(CustomerCrmHe.edit)),
      const PopupMenuItem(value: 'delete', child: Text(CustomerCrmHe.delete)),
    ],
  );
}

/// "טלפון ··········· 052-4718830": label at the start, value at the end.
class PersonDetailRow extends StatelessWidget {
  const PersonDetailRow({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
    this.valueKey,
    this.ltr = false,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final Key? valueKey;

  /// Phone / e-mail / numbers read left-to-right.
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Hit.row - 8),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.page,
            vertical: Space.s,
          ),
          child: Row(
            children: [
              Text(
                label,
                style: AppText.body.copyWith(
                  color: value.isEmpty ? p.ink : p.muted,
                ),
              ),
              const SizedBox(width: Space.l),
              Expanded(
                child: Text(
                  ltr ? ltrIsolate(value) : value,
                  key: valueKey,
                  textAlign: TextAlign.end,
                  style: AppText.body,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: Space.xs),
                Icon(Icons.chevron_right, size: 20, color: p.muted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "תזכורות תשלום אוטומטיות" (on = the customer gets the automatic
/// collection reminders). Owner / partner only; hidden when the server has
/// no automatic reminders (0111). The stored value is the opposite ("hold").
class PersonAutoRemindersRow extends StatefulWidget {
  const PersonAutoRemindersRow({super.key, required this.customerId});
  final String customerId;

  @override
  State<PersonAutoRemindersRow> createState() => _PersonAutoRemindersRowState();
}

class _PersonAutoRemindersRowState extends State<PersonAutoRemindersRow> {
  bool? _onHold;
  bool _busy = false;

  bool get _allowed => businessContext.caps.can(Cap.settingsBusiness);

  @override
  void initState() {
    super.initState();
    if (_allowed) unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final v = await loadReminderHold(customerId: widget.customerId);
      if (mounted) setState(() => _onHold = v);
    } on Object {
      // Offline / no 0111: the row stays hidden.
    }
  }

  Future<void> _set(bool on) async {
    final before = _onHold;
    setState(() {
      _onHold = !on;
      _busy = true;
    });
    try {
      await saveReminderHold(customerId: widget.customerId, onHold: !on);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _onHold = before);
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hold = _onHold;
    if (!_allowed || hold == null) return const SizedBox.shrink();
    final p = context.palette;
    return Padding(
      key: const Key('reminder-hold-customer'),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.page,
        vertical: Space.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  PersonPageHe.autoReminders,
                  style: AppText.body.copyWith(color: p.muted),
                ),
                Text(
                  PersonPageHe.autoRemindersHint,
                  style: AppText.secondary.copyWith(color: p.muted),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            key: const Key('person-auto-reminders-switch'),
            value: !hold,
            onChanged: _busy || session.offline ? null : _set,
          ),
        ],
      ),
    );
  }
}

/// A collapsed section (כסף ורווחיות / פרטי הלקוח).
class PersonFold extends StatelessWidget {
  const PersonFold({
    super.key,
    required this.title,
    required this.children,
    this.initiallyExpanded = false,
  });

  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      tilePadding: const EdgeInsets.symmetric(horizontal: Space.page),
      childrenPadding: const EdgeInsets.only(bottom: Space.s),
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(title, style: AppText.title),
      children: children,
    ),
  );
}
