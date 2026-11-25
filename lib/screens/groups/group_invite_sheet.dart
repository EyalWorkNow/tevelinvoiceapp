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
