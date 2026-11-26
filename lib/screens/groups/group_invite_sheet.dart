// V4 §8 "הזמן קבוצה" — a personal booking link to each member of a group
// (the calendar's personal invites, 7 days), with the progress of the last
// round ("7 מתוך 12 קבעו"). Reusable: the group page opens it, and the
// calendar can open it later with showGroupInviteSheet(context, groupId: …).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/customer_groups_api.dart';
import '../../ui/ds.dart';
import '../../util/labels/groups_he.dart';
import 'group_actions.dart';
import 'group_style.dart';

/// Opens the sheet; true when invites were sent.
Future<bool> showGroupInviteSheet(
  BuildContext context, {
  required String groupId,
  required String groupName,
}) async =>
    await showAppSheet<bool>(
      context,
      builder: (_) => GroupInviteSheet(groupId: groupId, groupName: groupName),
    ) ??
    false;

class GroupInviteSheet extends StatefulWidget {
  const GroupInviteSheet({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;

  @override
  State<GroupInviteSheet> createState() => _GroupInviteSheetState();
}

class _GroupInviteSheetState extends State<GroupInviteSheet> {
  GroupDetail? _detail;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final d = await fetchGroup(widget.groupId);
      if (mounted) setState(() => _detail = d);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    final run = await startGroupAction(
      context,
      groupId: widget.groupId,
      groupName: widget.groupName,
      kind: GroupActionKind.bookingInvite,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (run != null) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final d = _detail;
    final progress = d?.invites;
    return Column(
      key: const Key('group-invite-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(GroupsHe.inviteTitle, subtitle: widget.groupName),
        Text(GroupsHe.inviteBody, style: AppText.body),
        const SizedBox(height: Space.l),
        if (d == null && _error != null)
          ErrorView(error: _error!, onRetry: _load)
        else if (d == null)
          const SkeletonList(rows: 2)
        else
          AppCard(
            child: Row(
              children: [
                Icon(Iconsax.calendar_tick, color: p.ink),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Text(
                    progress == null
                        ? GroupsHe.inviteNone
                        : GroupsHe.booked(progress.booked, progress.sent),
                    key: const Key('group-invite-progress'),
                    style: AppText.body,
                  ),
                ),
                Text(
                  GroupsHe.membersCount(d.status.members),
                  style: AppText.secondary.copyWith(color: p.muted),
                ),
              ],
            ),
          ),
        const SizedBox(height: Space.l),
        FilledButton.icon(
          key: const Key('group-invite-send'),
          onPressed: _busy || d == null ? null : _send,
          icon: const Icon(Iconsax.calendar_add),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: const StadiumBorder(),
          ),
          label: const Text(GroupsHe.inviteSend),
        ),
      ],
    );
  }
}

/// The calendar's "הזמן קבוצה": pick a group (custom or smart), then the
/// invite sheet above. True when invites were sent.
Future<bool> pickGroupAndInvite(BuildContext context) async {
  final g = await showAppSheet<GroupSummary>(
    context,
    builder: (_) => const _GroupPicker(),
  );
  if (g == null || !context.mounted) return false;
  return showGroupInviteSheet(context, groupId: g.id, groupName: g.name);
}

class _GroupPicker extends StatefulWidget {
  const _GroupPicker();

  @override
  State<_GroupPicker> createState() => _GroupPickerState();
}

class _GroupPickerState extends State<_GroupPicker> {
  List<GroupSummary>? _all;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await fetchGroups();
      if (mounted) setState(() => _all = [...list.groups, ...list.smart]);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    return Column(
      key: const Key('group-picker-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetTitle(GroupsHe.inviteGroupTitle),
        if (all == null && _error != null)
          ErrorView(error: _error!, onRetry: _load)
        else if (all == null)
          const SkeletonList(rows: 3)
        else if (all.isEmpty)
          Text(
            GroupsHe.noGroupsYet,
            style: AppText.body.copyWith(color: context.palette.muted),
          )
        else
          for (final g in all)
            ListTile(
              key: Key('group-pick-${g.id}'),
              contentPadding: EdgeInsets.zero,
              leading: GroupBadge(group: g, size: 36),
              title: Text(g.name),
              trailing: Text('${g.memberCount}'),
              onTap: () => Navigator.of(context).pop(g),
            ),
      ],
    );
  }
}
