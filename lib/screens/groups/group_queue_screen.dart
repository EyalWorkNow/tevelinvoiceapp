// V4 §8 · "שליחה בוואטסאפ" — a group run's WhatsApp tap queue (owner
// decision: one tap per customer, no automatic WhatsApp). Each row opens
// WhatsApp with the server's ready text (personal amount / {שם} / link);
// the send is recorded on the server (POST …/sent), "דלג" dismisses it.
// The same pattern as the collection-reminders batch.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/customer_groups_api.dart';
import '../../state/session.dart';
import '../../ui/ds.dart';
import '../../util/allowed_urls.dart';
import '../../util/labels/groups_he.dart';
import '../../util/phone.dart';
import '../../util/still_here.dart';
import '../document/sheets/s6_share.dart' show textSharer;

Future<void> openGroupQueue(BuildContext context, GroupRun run) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => GroupQueueScreen(run: run)));

class GroupQueueScreen extends StatefulWidget {
  const GroupQueueScreen({super.key, required this.run});
  final GroupRun run;

  @override
  State<GroupQueueScreen> createState() => _GroupQueueScreenState();
}

class _GroupQueueScreenState extends State<GroupQueueScreen> {
  late List<GroupRunItem> _items = widget.run.queue;
  final Set<String> _busy = {};

  Future<void> _reload() async {
    try {
      final run = await fetchGroupRun(widget.run.id);
      if (mounted) setState(() => _items = run.queue);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  void _drop(String id) =>
      setState(() => _items = [..._items.where((i) => i.id != id)]);

  Future<void> _send(GroupRunItem item) async {
    setState(() => _busy.add(item.id));
    try {
      final text = item.text ?? '';
      final wa = waPhone(item.phone);
      var opened = false;
      if (wa != null) {
        opened = await launchAllowed(whatsAppUri(phone: wa, text: text));
      }
      if (!opened) await textSharer(text);
      if (!mounted || !stillHere(context)) return;
      await markGroupItemSent(widget.run.id, item.id);
      if (!mounted) return;
      _drop(item.id);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(item.id));
    }
  }

  Future<void> _skip(GroupRunItem item) async {
    setState(() => _busy.add(item.id));
    try {
      await dismissGroupItem(widget.run.id, item.id);
      if (mounted) _drop(item.id);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      key: const Key('group-queue'),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.page,
                Space.m,
                Space.page,
                Space.s,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: const Text(
                        GroupsHe.queueTitle,
                        style: AppText.displayTitle,
                      ),
                    ),
                  ),
                  const DesignBackButton(),
                ],
              ),
            ),
            OfflineBanner(visible: session.offline),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _reload,
                child: _items.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: Space.xxl),
                          EmptyState(
                            key: Key('group-queue-empty'),
                            icon: Iconsax.tick_circle,
                            title: GroupsHe.queueEmpty,
                            message: GroupsHe.queueEmptyBody,
                          ),
                        ],
                      )
                    : ListView(
                        key: const Key('group-queue-list'),
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                          Space.page,
                          Space.s,
                          Space.page,
                          Space.xl,
                        ),
                        children: [
                          Text(
                            GroupsHe.queueHint,
                            style: AppText.secondary.copyWith(color: p.muted),
                          ),
                          const SizedBox(height: Space.m),
                          for (final i in _items) ...[
                            _QueueCard(
                              key: Key('group-queue-item-${i.id}'),
                              item: i,
                              busy: _busy.contains(i.id) || session.offline,
                              onSend: () => unawaited(_send(i)),
                              onSkip: () => unawaited(_skip(i)),
                            ),
                            const SizedBox(height: Space.m),
                          ],
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({
    super.key,
    required this.item,
    required this.busy,
    required this.onSend,
    required this.onSkip,
  });

  final GroupRunItem item;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final amount = item.amountMinor;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.name,
                  style: AppText.headline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (amount != null && amount > BigInt.zero)
                AmountText(amount, style: AppText.amountCard),
            ],
          ),
          if ((item.text ?? '').isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Text(
              item.text!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppText.secondary.copyWith(color: p.muted),
            ),
          ],
          const SizedBox(height: Space.m),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label: GroupsHe.queueA11y(item.name),
                  button: true,
                  excludeSemantics: true,
                  child: FilledButton.icon(
                    key: Key('group-queue-send-${item.id}'),
                    onPressed: busy ? null : onSend,
                    icon: const Icon(Iconsax.message),
                    label: const Text(GroupsHe.queueSend),
                  ),
                ),
              ),
              const SizedBox(width: Space.s),
              TextButton(
                key: Key('group-queue-skip-${item.id}'),
                onPressed: busy ? null : onSkip,
                child: const Text(GroupsHe.queueSkip),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
