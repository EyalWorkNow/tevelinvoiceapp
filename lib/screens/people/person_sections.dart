// Building blocks of the customer page (כרטיס לקוח v2): section titles with
// "הכל", visit / note / follow-up rows and label-value detail rows. Rows put the label at the start (right)
// and the value / amount at the end (left) of the row.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/customer_portal_api.dart';
import '../../state/customer_crm_store.dart';
import '../../state/session.dart';
import '../../ui/ds.dart';
import '../../ui/widgets/notch_notice.dart';
import '../../util/labels/common_he.dart';
import '../../util/labels/customer_crm_he.dart';
import '../../util/labels/person_page_he.dart';
import '../../util/labels/portal_he.dart';
import 'person_logic.dart';
import 'sheets/portal_link_sheet.dart';

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
      const PopupMenuDivider(),
      PopupMenuItem(
        value: 'delete',
        child: Text(
          CustomerCrmHe.delete,
          style: TextStyle(color: context.palette.danger),
        ),
      ),
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

/// 0135 "אזור אישי": shown once the customer has a live link — status, last
/// sign-in, and (tap) send again · new link · revoke. Loads when the folded
/// "פרטי הלקוח" opens; hidden while loading, without a link, or on error.
class PersonPortalRow extends StatefulWidget {
  const PersonPortalRow({
    super.key,
    required this.customerId,
    required this.name,
    this.phone,
    this.email,
  });

  final String customerId;
  final String name;
  final String? phone;
  final String? email;

  @override
  State<PersonPortalRow> createState() => _PersonPortalRowState();
}

class _PersonPortalRowState extends State<PersonPortalRow> {
  PortalLink? _link;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final link = await fetchPortalLink(widget.customerId);
      if (mounted) setState(() => _link = link);
    } on Object {
      // Offline / older server: the row stays hidden.
    }
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text(CommonHe.cancel),
            ),
            TextButton(
              key: const Key('portal-confirm'),
              onPressed: () => Navigator.pop(c, true),
              style: TextButton.styleFrom(
                foregroundColor: context.palette.danger,
              ),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _manage() async {
    if (_busy) return;
    final p = context.palette;
    final chosen = await showAppSheet<String>(
      context,
      builder: (sheet) => Column(
        key: const Key('portal-manage-sheet'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetTitle(PortalHe.manageTitle, subtitle: widget.name),
          for (final (id, icon, label, hint) in [
            ('resend', Iconsax.send_2, PortalHe.resend, null),
            (
              'regenerate',
              Iconsax.refresh,
              PortalHe.regenerate,
              PortalHe.regenerateHint,
            ),
            ('revoke', Iconsax.link_1, PortalHe.revoke, null),
          ])
            ListTile(
              key: Key('portal-$id'),
              minTileHeight: Hit.row - 8,
              contentPadding: EdgeInsets.zero,
              enabled: !session.offline,
              leading: Icon(icon, color: id == 'revoke' ? p.danger : p.ink),
              title: Text(
                label,
                style: AppText.body.copyWith(
                  color: id == 'revoke' ? p.danger : null,
                ),
              ),
              subtitle: hint == null
                  ? null
                  : Text(
                      hint,
                      style: AppText.secondary.copyWith(color: p.muted),
                    ),
              onTap: () => Navigator.of(sheet).pop(id),
            ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    if (chosen == 'revoke') {
      if (!await _confirm(
        PortalHe.revokeConfirmTitle,
        PortalHe.revokeConfirmBody,
        PortalHe.revoke,
      )) {
        return;
      }
      setState(() => _busy = true);
      try {
        await revokePortalLink(widget.customerId);
        if (!mounted) return;
        setState(() => _link = null);
        ScaffoldMessenger.of(
          context,
        ).showNotchNotice(const SnackBar(content: Text(PortalHe.revoked)));
      } on Object catch (e) {
        if (mounted) showErrorSnack(context, e);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    final regenerate = chosen == 'regenerate';
    if (regenerate &&
        !await _confirm(
          PortalHe.regenerateConfirmTitle,
          PortalHe.regenerateConfirmBody,
          PortalHe.regenerate,
        )) {
      return;
    }
    if (!mounted) return;
    await showPortalLinkSheet(
      context,
      customerId: widget.customerId,
      name: widget.name,
      phone: widget.phone,
      email: widget.email,
      regenerate: regenerate,
    );
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final link = _link;
    if (link == null) return const SizedBox.shrink();
    final last = link.lastLoginAt;
    return PersonDetailRow(
      key: const Key('person-portal'),
      valueKey: const Key('person-portal-value'),
      label: PortalHe.rowLabel,
      value: last == null
          ? '${PortalHe.rowActive} · ${PortalHe.neverLoggedIn}'
          : '${PortalHe.rowActive} · ${PortalHe.lastLogin(PortalHe.when(last))}',
      onTap: _busy ? null : () => unawaited(_manage()),
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

/// A page header that stays on top: once the list below scrolls it turns
/// compact and gets a bottom hairline, so the content never looks cut
/// under it (2611 customer page #4).
class ScrollEdgeHeader extends StatelessWidget {
  const ScrollEdgeHeader({
    super.key,
    required this.scrolled,
    required this.child,
  });

  final bool scrolled;
  final Widget child;

  /// Collapses after [_collapseAt] px, opens again only back at the top, so
  /// the header's own size change never flips it back and forth.
  static bool next(bool scrolled, ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return scrolled;
    final px = n.metrics.pixels;
    if (!scrolled && px > _collapseAt) return true;
    if (scrolled && px <= 1) return false;
    return scrolled;
  }

  static const double _collapseAt = 16;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedContainer(
      key: const Key('scroll-edge-header'),
      duration: context.motion(180),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: scrolled ? p.line : p.line.withValues(alpha: 0),
          ),
        ),
      ),
      child: child,
    );
  }
}
