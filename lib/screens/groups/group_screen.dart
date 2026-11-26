// V4 §8 · דף קבוצה — built like the customer page (person_screen.dart):
//  1. Header: the group's name (+ "מתעדכנת לבד" for a smart group); ⋯ for a
//     custom group: עריכת שם וצבע · מחיקת קבוצה (red; customers stay).
//  2. Status card: how many members, how many owe and the total (money.view),
//     how many lack a phone / an e-mail / are inactive, and the last booking
//     invite round ("7 מתוך 12 קבעו").
//  3. "פעולות מהירות": בקשת תשלום לכולם · הודעת תפוצה · מסמך לכולם · קישור
//     לקביעת פגישה · שליחת כרטסת · הוסף חברים — each by permission (an
//     employee sees the group but sends nothing). The smart "לא פעילים"
//     group has no send actions (inactive members are skipped anyway).
//  4. Members: name · phone · "חייב לך ₪X" at the row's end; tap → the
//     customer page; a manager swipes a member out of a custom group.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/customer_groups_api.dart';
import '../../router.dart' show openPerson;
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../ui/ds.dart';
import '../../ui/widgets/notch_notice.dart';
import '../../ui/widgets/quick_action_grid.dart';
import '../../util/labels/common_he.dart';
import '../../util/labels/groups_he.dart';
import '../../util/labels/people_he.dart';
import '../calendar/calendar_screen.dart' show mayUseCalendar;
import 'group_actions.dart';
import 'group_invite_sheet.dart';
import 'group_sheets.dart';
import 'group_style.dart';

Future<void> openGroup(
  BuildContext context,
  String id, {
  GroupActionKind? startAction,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    settings: RouteSettings(name: '/group/$id'),
    builder: (_) => GroupScreen(id: id, startAction: startAction),
  ),
);

/// Which group actions this member may run (pure; tested).
List<String> groupActionIds(Caps caps, {required String? smart}) {
  final manage = caps.can(Cap.customerManage);
  final send = manage && caps.can(Cap.docSend);
  final money = caps.can(Cap.moneyView);
  if (smart == smartInactive) return const [];
  return [
    if (send && money) 'payment',
    if (send) 'broadcast',
    if (manage && caps.can(Cap.docDraft)) 'document',
    if (mayUseCalendar(caps)) 'invite',
    if (send && money) 'statement',
    if (manage && smart == null) 'add',
  ];
}

GroupActionKind? groupActionKind(String id) => switch (id) {
  'payment' => GroupActionKind.paymentRequest,
  'broadcast' => GroupActionKind.broadcast,
  'document' => GroupActionKind.document,
  'invite' => GroupActionKind.bookingInvite,
  'statement' => GroupActionKind.statement,
  _ => null,
};

const _orbColors = <String, (Color, Color)>{
  'payment': (Color(0xFFCFF5DE), Color(0xFF2F5B47)),
  'broadcast': (Color(0xFFD8EFE2), Color(0xFF3E6250)),
  'document': (Color(0xFFE8D9EF), Color(0xFF614A68)),
  'invite': (Color(0xFFD6EDF5), Color(0xFF385D6E)),
  'statement': (Color(0xFFF3E9A9), Color(0xFF58623B)),
  'add': (Color(0xFFE6D4F4), Color(0xFF624D73)),
};

const _icons = <String, IconData>{
  'payment': Iconsax.money_send,
  'broadcast': Iconsax.messages_2,
  'document': Iconsax.receipt_add,
  'invite': Iconsax.calendar_add,
  'statement': Iconsax.receipt_item,
  'add': Iconsax.profile_add,
};

String _label(String id) => switch (id) {
  'payment' => GroupsHe.actPayment,
  'broadcast' => GroupsHe.actBroadcast,
  'document' => GroupsHe.actDocument,
  'invite' => GroupsHe.actInvite,
  'statement' => GroupsHe.actStatement,
  'add' => GroupsHe.addMembers,
  _ => id,
};

class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key, required this.id, this.startAction});

  final String id;

  /// Runs once after the first load (a quick action from multi-select).
  final GroupActionKind? startAction;

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  GroupDetail? _detail;
  Object? _error;
  bool _started = false;

  Caps get _caps => businessContext.caps;
  bool get _manage => _caps.can(Cap.customerManage);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await fetchGroup(widget.id);
      if (!mounted) return;
      setState(() => _detail = d);
      final start = widget.startAction;
      if (start != null && !_started) {
        _started = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_action(start));
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String get _name {
    final d = _detail;
    return d == null ? '' : groupDisplayName(d.group);
  }

  Future<void> _action(GroupActionKind kind) async {
    if (kind == GroupActionKind.bookingInvite) {
      if (await showGroupInviteSheet(
            context,
            groupId: widget.id,
            groupName: _name,
          ) &&
          mounted) {
        unawaited(_load());
      }
      return;
    }
    final run = await startGroupAction(
      context,
      groupId: widget.id,
      groupName: _name,
      kind: kind,
    );
    if (run != null && mounted) unawaited(_load());
  }

  Future<void> _run(String id) async {
    final kind = groupActionKind(id);
    if (kind != null) return _action(kind);
    if (id == 'add') await _addMembers();
  }

  Future<void> _addMembers() async {
    final d = _detail;
    if (d == null) return;
    final ids = await showAddMembersSheet(
      context,
      already: {for (final m in d.members) m.id},
    );
    if (ids == null || ids.isEmpty || !mounted) return;
    try {
      await addGroupMembers(widget.id, ids);
      if (!mounted) return;
      _toast(GroupsHe.addedToGroup(ids.length, _name));
      unawaited(_load());
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _edit() async {
    final d = _detail;
    if (d == null) return;
    final saved = await showGroupEditorSheet(context, existing: d.group);
    if (saved != null && mounted) unawaited(_load());
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text(GroupsHe.deleteTitle),
        content: Text(GroupsHe.deleteBody(_name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text(CommonHe.cancel),
          ),
          FilledButton(
            key: const Key('group-delete-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: context.palette.danger,
            ),
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text(GroupsHe.deleteConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await deleteGroup(widget.id);
      if (!mounted) return;
      _toast(GroupsHe.deleted);
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<bool> _remove(GroupMember m) async {
    try {
      await removeGroupMember(widget.id, m.id);
      if (!mounted) return true;
      _toast(GroupsHe.removed(m.name));
      unawaited(_load());
      return true;
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
      return false;
    }
  }

  void _toast(String text) => ScaffoldMessenger.of(
    context,
  ).showNotchNotice(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context),
            Expanded(
              child: d == null
                  ? (_error != null
                        ? ErrorView(error: _error!, onRetry: _load)
                        : const SingleChildScrollView(child: SkeletonList()))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _content(context, d),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final p = context.palette;
    final d = _detail;
    final custom = d != null && !d.group.isSmart;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.page,
        Space.m,
        Space.page,
        Space.s,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (d != null) ...[
            GroupBadge(group: d.group, size: 44),
            const SizedBox(width: Space.m),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  // A long name shrinks to one line, never wraps under the badge.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      _name,
                      style: AppText.displayTitle,
                      maxLines: 1,
                    ),
                  ),
                ),
                if (d != null && d.group.isSmart)
                  Text(
                    GroupsHe.smartBadge,
                    style: AppText.secondary.copyWith(color: p.muted),
                  ),
              ],
            ),
          ),
          if (custom && _manage)
            MoreMenu(
              items: [
                MoreMenuItem(
                  label: GroupsHe.edit,
                  icon: Iconsax.edit,
                  onSelected: () => unawaited(_edit()),
                ),
                MoreMenuItem(
                  label: GroupsHe.delete,
                  icon: Iconsax.trash,
                  destructive: true,
                  onSelected: () => unawaited(_delete()),
                ),
              ],
            ),
          const SizedBox(width: 8),
          const DesignBackButton(),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, GroupDetail d) {
    final actions = groupActionIds(_caps, smart: d.group.smart);
    return ListView(
      key: const Key('group-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: Space.m, bottom: Space.xxl),
      children: [
        _statusCard(context, d),
        if (actions.isNotEmpty) _quickActions(context, actions),
        if (actions.isEmpty) _noActions(context, d),
        ..._members(context, d),
      ],
    );
  }

  Widget _noActions(BuildContext context, GroupDetail d) {
    final p = context.palette;
    final text = d.group.smart == smartInactive
        ? GroupsHe.inactiveNoActions
        : GroupsHe.employeeNoActions;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.page, Space.l, Space.page, 0),
      child: Text(
        text,
        key: const Key('group-no-actions'),
        style: AppText.secondary.copyWith(color: p.muted),
      ),
    );
  }

  Widget _statusCard(BuildContext context, GroupDetail d) {
    final p = context.palette;
    final s = d.status;
    final money = _caps.can(Cap.moneyView) && s.owingMinor != null;
    final gaps = [
      if (s.noPhone > 0) GroupsHe.noPhone(s.noPhone),
      if (s.noEmail > 0) GroupsHe.noEmail(s.noEmail),
      if (s.inactive > 0 && d.group.smart != smartInactive)
        GroupsHe.inactive(s.inactive),
    ];
    final invites = d.invites;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.page),
      child: AppCard(
        key: const Key('group-status'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              GroupsHe.membersLine(s.members),
              key: const Key('group-members-count'),
              style: AppText.headline,
            ),
            if (money) ...[
              const SizedBox(height: Space.s),
              if (s.owing > 0)
                Row(
                  key: const Key('group-owing'),
                  children: [
                    Expanded(
                      child: Text(
                        GroupsHe.owingLine(s.owing),
                        style: AppText.body,
                      ),
                    ),
                    AmountText(
                      s.owingMinor!,
                      style: AppText.amountCard,
                      color: p.warn,
                    ),
                  ],
                )
              else
                Text(
                  GroupsHe.nobodyOwes,
                  style: AppText.body.copyWith(color: p.muted),
                ),
            ],
            if (gaps.isNotEmpty) ...[
              const SizedBox(height: Space.xs),
              Text(
                gaps.join(' · '),
                key: const Key('group-gaps'),
                style: AppText.secondary.copyWith(color: p.muted),
              ),
            ],
            if (invites != null) ...[
              Divider(color: p.line, height: Space.xl),
              Row(
                children: [
                  Icon(Iconsax.calendar_tick, size: 20, color: p.ink),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: Text(
                      GroupsHe.booked(invites.booked, invites.sent),
                      key: const Key('group-invites'),
                      style: AppText.body,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _quickActions(BuildContext context, List<String> ids) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.page, Space.l, Space.page, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(GroupsHe.quickActions, style: AppText.title),
        const SizedBox(height: Space.s),
        QuickActionGrid(
          key: const Key('group-actions'),
          keyPrefix: 'group-action',
          actions: [
            for (final id in ids)
              QuickAction(
                id: id,
                label: _label(id),
                icon: _icons[id]!,
                color: _orbColors[id]!.$1,
                ink: _orbColors[id]!.$2,
                enabled: !businessContext.offline,
                onTap: () => unawaited(_run(id)),
              ),
          ],
        ),
      ],
    ),
  );

  List<Widget> _members(BuildContext context, GroupDetail d) {
    final p = context.palette;
    final removable = _manage && !d.group.isSmart;
    final money = _caps.can(Cap.moneyView);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.page, Space.l, Space.page, 0),
        child: SizedBox(
          height: Hit.min,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Semantics(
              header: true,
              child: const Text(GroupsHe.membersTitle, style: AppText.title),
            ),
          ),
        ),
      ),
      if (d.members.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.page),
          child: Text(
            d.group.isSmart ? GroupsHe.emptySmart : GroupsHe.emptyMembers,
            key: const Key('group-members-empty'),
            style: AppText.body.copyWith(color: p.muted),
          ),
        ),
      for (final m in d.members)
        _memberRow(context, m, removable: removable, money: money),
    ];
  }

  Widget _memberRow(
    BuildContext context,
    GroupMember m, {
    required bool removable,
    required bool money,
  }) {
    final owed = m.balanceMinor;
    final row = PersonRow(
      key: Key('group-member-${m.id}'),
      name: m.name,
      subtitle: m.phone ?? m.email,
      badge: m.archived ? GroupsHe.inactiveBadge : null,
      amountLabel: money && owed != null && owed > BigInt.zero
          ? PeopleHe.owesYou
          : null,
      amountMinor: money && owed != null && owed > BigInt.zero ? owed : null,
      onTap: () => unawaited(openPerson(context, m.id)),
    );
    if (!removable) return row;
    final p = context.palette;
    return Dismissible(
      key: Key('group-member-swipe-${m.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: p.danger,
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsets.symmetric(horizontal: Space.page),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              GroupsHe.removeMember,
              style: AppText.body.copyWith(color: p.onDanger),
            ),
            const SizedBox(width: Space.s),
            Icon(Iconsax.user_minus, color: p.onDanger),
          ],
        ),
      ),
      confirmDismiss: (_) => _remove(m),
      child: row,
    );
  }
}
