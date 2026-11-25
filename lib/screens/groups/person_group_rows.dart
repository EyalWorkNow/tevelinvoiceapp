// V4 §8 · the customer page's "פרטי הלקוח" rows: "קבוצות" (the customer's
// groups; a manager taps to tick groups on / off) and "מאשר דיוור" (marketing
// consent — only consenting customers get a marketing broadcast).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/customer_groups_api.dart';
import '../../state/session.dart';
import '../../ui/ds.dart';
import '../../util/labels/groups_he.dart';
import 'group_screen.dart';
import 'group_sheets.dart';
import 'group_style.dart';

class PersonGroupsRow extends StatefulWidget {
  const PersonGroupsRow({
    super.key,
    required this.customerId,
    required this.customerName,
    required this.canEdit,
  });

  final String customerId;
  final String customerName;
  final bool canEdit;

  @override
  State<PersonGroupsRow> createState() => _PersonGroupsRowState();
}

class _PersonGroupsRowState extends State<PersonGroupsRow> {
  List<GroupSummary>? _groups;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final g = await fetchCustomerGroups(widget.customerId);
      if (mounted) setState(() => _groups = g);
    } on Object {
      // Offline / no 0133 yet: the row stays hidden.
    }
  }

  Future<void> _edit() async {
    final saved = await showCustomerGroupsSheet(
      context,
      customerId: widget.customerId,
      customerName: widget.customerName,
      current: _groups ?? const [],
    );
    if (saved != null && mounted) setState(() => _groups = saved);
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    if (groups == null) return const SizedBox.shrink();
    final p = context.palette;
    return InkWell(
      key: const Key('person-groups'),
      onTap: widget.canEdit && !session.offline
          ? () => unawaited(_edit())
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.page,
          vertical: Space.s,
        ),
        child: Row(
          children: [
            Text(
              GroupsHe.customerGroups,
              style: AppText.body.copyWith(color: p.muted),
            ),
            const SizedBox(width: Space.l),
            Expanded(
              child: groups.isEmpty
                  ? Text(
                      GroupsHe.noGroups,
                      textAlign: TextAlign.end,
                      style: AppText.body,
                    )
                  : Wrap(
                      alignment: WrapAlignment.end,
                      spacing: Space.xs,
                      runSpacing: Space.xs,
                      children: [
                        for (final g in groups)
                          ActionChip(
                            key: Key('person-group-${g.id}'),
                            visualDensity: VisualDensity.compact,
                            backgroundColor: groupPastel(g.color).$1,
                            side: BorderSide.none,
                            label: Text(
                              g.name,
                              style: AppText.secondary.copyWith(
                                color: groupPastel(g.color).$2,
                              ),
                            ),
                            onPressed: () =>
                                unawaited(openGroup(context, g.id)),
                          ),
                      ],
                    ),
            ),
            if (widget.canEdit) ...[
              const SizedBox(width: Space.xs),
              Icon(Icons.chevron_right, size: 20, color: p.muted),
            ],
          ],
        ),
      ),
    );
  }
}

class PersonMarketingRow extends StatefulWidget {
  const PersonMarketingRow({
    super.key,
    required this.customerId,
    required this.initial,
    required this.canEdit,
  });

  final String customerId;
  final bool initial;
  final bool canEdit;

  @override
  State<PersonMarketingRow> createState() => _PersonMarketingRowState();
}

class _PersonMarketingRowState extends State<PersonMarketingRow> {
  late bool _on = widget.initial;
  bool _busy = false;

  @override
  void didUpdateWidget(PersonMarketingRow old) {
    super.didUpdateWidget(old);
    if (old.initial != widget.initial && !_busy) _on = widget.initial;
  }

  Future<void> _set(bool v) async {
    setState(() {
      _on = v;
      _busy = true;
    });
    try {
      await setMarketingConsent(widget.customerId, v);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _on = !v);
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      key: const Key('person-marketing'),
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
                  GroupsHe.marketingConsent,
                  style: AppText.body.copyWith(color: p.muted),
                ),
                Text(
                  GroupsHe.marketingConsentHint,
                  style: AppText.secondary.copyWith(color: p.muted),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            key: const Key('person-marketing-switch'),
            value: _on,
            onChanged: !widget.canEdit || _busy || session.offline
                ? null
                : (v) => unawaited(_set(v)),
          ),
        ],
      ),
    );
  }
}
