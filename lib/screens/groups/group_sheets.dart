// V4 §8 · the group sheets: new / edit group (name + colour), "לאיזו קבוצה?"
// (multi-select → add to a group, or a new one), the customer's groups
// (checkboxes, from the customer page) and "הוסף חברים" (pick customers).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/customer_groups_api.dart';
import '../../api/customers_api.dart';
import '../../api/models/models.dart';
import '../../ui/ds.dart';
import '../../util/labels/people_he.dart';
import '../../util/labels/groups_he.dart';
import '../../util/phone.dart';
import 'group_style.dart';

/// New group ([existing] null) or edit. Returns the saved group.
Future<GroupSummary?> showGroupEditorSheet(
  BuildContext context, {
  GroupSummary? existing,
}) => showAppSheet<GroupSummary>(
  context,
  builder: (_) => _GroupEditor(existing: existing),
);

class _GroupEditor extends StatefulWidget {
  const _GroupEditor({this.existing});
  final GroupSummary? existing;

  @override
  State<_GroupEditor> createState() => _GroupEditorState();
}

class _GroupEditorState extends State<_GroupEditor> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late String _color = widget.existing?.color ?? groupColorKeys.first;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = GroupsHe.nameRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final e = widget.existing;
      final saved = e == null
          ? await createGroup(name: name, color: _color)
          : await updateGroup(e.id, name: name, color: _color);
      if (mounted) Navigator.of(context).pop(saved);
    } on Object catch (err) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnack(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      key: const Key('group-editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(
          widget.existing == null ? GroupsHe.editorNew : GroupsHe.editorEdit,
        ),
        TextField(
          key: const Key('group-name'),
          controller: _name,
          autofocus: widget.existing == null,
          maxLength: 40,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: GroupsHe.name,
            hintText: GroupsHe.nameHint,
            errorText: _error,
          ),
          onSubmitted: (_) => unawaited(_save()),
        ),
        const SizedBox(height: Space.m),
        Text(GroupsHe.color, style: AppText.body.copyWith(color: p.muted)),
        const SizedBox(height: Space.s),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final key in groupColorKeys)
              Semantics(
                label: GroupsHe.colorName(key),
                selected: key == _color,
                button: true,
                excludeSemantics: true,
                child: InkWell(
                  key: Key('group-color-$key'),
                  customBorder: const CircleBorder(),
                  onTap: () => setState(() => _color = key),
                  child: Container(
                    width: Hit.min,
                    height: Hit.min,
                    decoration: BoxDecoration(
                      color: groupPastel(key).$1,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: key == _color
                            ? groupPastel(key).$2
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: key == _color
                        ? Icon(Icons.check, color: groupPastel(key).$2)
                        : null,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.xl),
        FilledButton(
          key: const Key('group-save'),
          onPressed: _busy ? null : _save,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: const StadiumBorder(),
          ),
          child: Text(
            widget.existing == null ? GroupsHe.create : GroupsHe.save,
          ),
        ),
      ],
    );
  }
}

/// "לאיזו קבוצה?": one of the custom groups, or a new one (created here).
Future<GroupSummary?> showPickGroupSheet(
  BuildContext context, {
  required List<GroupSummary> groups,
  String? subtitle,
}) async {
  final picked = await showAppSheet<Object>(
    context,
    builder: (sheet) => Column(
      key: const Key('group-pick'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(GroupsHe.pickGroupTitle, subtitle: subtitle),
        ListTile(
          key: const Key('group-pick-new'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Iconsax.add_circle),
          title: const Text(GroupsHe.newGroup),
          onTap: () => Navigator.of(sheet).pop('new'),
        ),
        for (final g in groups)
          ListTile(
            key: Key('group-pick-${g.id}'),
            contentPadding: EdgeInsets.zero,
            leading: GroupBadge(group: g, size: 40),
            title: Text(g.name),
            subtitle: Text(GroupsHe.membersCount(g.memberCount)),
            onTap: () => Navigator.of(sheet).pop(g),
          ),
      ],
    ),
  );
  if (picked is GroupSummary) return picked;
  if (picked == 'new' && context.mounted) {
    return showGroupEditorSheet(context);
  }
  return null;
}

/// The customer page's groups: a checkbox per custom group. Returns the
/// customer's groups after save (null = cancelled).
Future<List<GroupSummary>?> showCustomerGroupsSheet(
  BuildContext context, {
  required String customerId,
  required String customerName,
  required List<GroupSummary> current,
}) => showAppSheet<List<GroupSummary>>(
  context,
  builder: (_) => _CustomerGroups(
    customerId: customerId,
    customerName: customerName,
    current: current,
  ),
);

class _CustomerGroups extends StatefulWidget {
  const _CustomerGroups({
    required this.customerId,
    required this.customerName,
    required this.current,
  });

  final String customerId;
  final String customerName;
  final List<GroupSummary> current;

  @override
  State<_CustomerGroups> createState() => _CustomerGroupsState();
}

class _CustomerGroupsState extends State<_CustomerGroups> {
  List<GroupSummary>? _all;
  late final Set<String> _chosen = {for (final g in widget.current) g.id};
  bool _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final list = await fetchGroups();
      if (mounted) setState(() => _all = list.groups);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final saved = await saveCustomerGroups(
        widget.customerId,
        _chosen.toList(),
      );
      if (mounted) Navigator.of(context).pop(saved);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final p = context.palette;
    return Column(
      key: const Key('customer-groups-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(GroupsHe.customerGroupsTitle, subtitle: widget.customerName),
        if (all == null && _error != null)
          ErrorView(error: _error!, onRetry: _load)
        else if (all == null)
          const SkeletonList(rows: 3)
        else if (all.isEmpty)
          Text(
            GroupsHe.noGroupsYet,
            style: AppText.body.copyWith(color: p.muted),
          )
        else
          for (final g in all)
            CheckboxListTile(
              key: Key('customer-group-${g.id}'),
              contentPadding: EdgeInsets.zero,
              value: _chosen.contains(g.id),
              onChanged: (v) => setState(
                () => v == true ? _chosen.add(g.id) : _chosen.remove(g.id),
              ),
              secondary: GroupBadge(group: g, size: 36),
              title: Text(g.name),
            ),
        if (all != null && all.isNotEmpty) ...[
          const SizedBox(height: Space.l),
          FilledButton(
            key: const Key('customer-groups-save'),
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: const StadiumBorder(),
            ),
            child: const Text(GroupsHe.save),
          ),
        ],
      ],
    );
  }
}

/// "הוסף חברים": active customers not yet in the group, with search and
/// checkboxes. Returns the chosen ids (empty / null = nothing).
Future<List<String>?> showAddMembersSheet(
  BuildContext context, {
  required Set<String> already,
}) => showAppSheet<List<String>>(
  context,
  builder: (_) => _AddMembers(already: already),
);

class _AddMembers extends StatefulWidget {
  const _AddMembers({required this.already});
  final Set<String> already;

  @override
  State<_AddMembers> createState() => _AddMembersState();
}

class _AddMembersState extends State<_AddMembers> {
  List<Customer>? _all;
  Object? _error;
  final _q = TextEditingController();
  final Set<String> _chosen = {};

  @override
  void initState() {
    super.initState();
    _q.addListener(() => setState(() {}));
    unawaited(_load());
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await fetchCustomerList();
      if (mounted) setState(() => _all = list.active);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final q = _q.text.trim();
    final rows = [
      for (final c in all ?? const <Customer>[])
        if (!widget.already.contains(c.id) && customerMatches(c, q)) c,
    ];
    return Column(
      key: const Key('group-add-members'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetTitle(GroupsHe.addMembers),
        TextField(
          key: const Key('group-add-search'),
          controller: _q,
          decoration: const InputDecoration(
            hintText: PeopleHe.search,
            prefixIcon: Icon(Iconsax.search_normal_1),
          ),
        ),
        const SizedBox(height: Space.s),
        if (all == null && _error != null)
          ErrorView(error: _error!, onRetry: _load)
        else if (all == null)
          const SkeletonList(rows: 4)
        else
          for (final c in rows.take(200))
            CheckboxListTile(
              key: Key('group-add-${c.id}'),
              contentPadding: EdgeInsets.zero,
              value: _chosen.contains(c.id),
              onChanged: (v) => setState(
                () => v == true ? _chosen.add(c.id) : _chosen.remove(c.id),
              ),
              title: Text(c.name),
              subtitle: (c.phone ?? '').isEmpty
                  ? null
                  : Text(ltrIsolate(formatPhoneHe(c.phone))),
            ),
        const SizedBox(height: Space.l),
        FilledButton(
          key: const Key('group-add-save'),
          onPressed: _chosen.isEmpty
              ? null
              : () => Navigator.of(context).pop(_chosen.toList()),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: const StadiumBorder(),
          ),
          child: Text(
            _chosen.isEmpty
                ? GroupsHe.addMembers
                : '${GroupsHe.addMembers} (${_chosen.length})',
          ),
        ),
      ],
    );
  }
}
