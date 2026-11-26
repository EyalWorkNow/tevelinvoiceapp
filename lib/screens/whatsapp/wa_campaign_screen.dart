// וואטסאפ עסקי — one campaign (the counts, each recipient with a status pill
// at the row's end; refreshes every 5 seconds while SENDING) and a group's
// previous campaigns ("קמפיינים קודמים").

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/whatsapp_business_api.dart';
import '../../ui/ds.dart';
import '../../util/labels/status_he.dart' show Tone;
import '../../util/labels/whatsapp_business_he.dart';
import 'wa_widgets.dart';

/// Refresh period while a campaign is SENDING (tests shorten it).
Duration waCampaignRefreshEvery = const Duration(seconds: 5);

Future<void> openWaCampaign(BuildContext context, String id) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: '/whatsapp-campaign/$id'),
        builder: (_) => WaCampaignScreen(id: id),
      ),
    );

Future<void> openWaCampaigns(
  BuildContext context, {
  required String groupId,
  required String groupName,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    settings: RouteSettings(name: '/group/$groupId/whatsapp-campaigns'),
    builder: (_) => WaCampaignsScreen(groupId: groupId, groupName: groupName),
  ),
);

Widget waCampaignPill(WaCampaign c) => c.sending
    ? const WaPill(WaHe.sending, Tone.info)
    : const WaPill(WaHe.done, Tone.ok);

class WaCampaignScreen extends StatefulWidget {
  const WaCampaignScreen({super.key, required this.id});
  final String id;

  @override
  State<WaCampaignScreen> createState() => _WaCampaignScreenState();
}

class _WaCampaignScreenState extends State<WaCampaignScreen> {
  WaCampaign? _campaign;
  Object? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c = await fetchWaCampaign(widget.id);
      if (!mounted) return;
      setState(() {
        _campaign = c;
        _error = null;
      });
      _schedule(c);
    } on Object catch (e) {
      if (!mounted) return;
      // A failed background refresh keeps the last numbers on screen.
      if (_campaign == null) setState(() => _error = e);
      _schedule(_campaign);
    }
  }

  void _schedule(WaCampaign? c) {
    _timer?.cancel();
    _timer = null;
    if (c != null && c.sending) {
      _timer = Timer(waCampaignRefreshEvery, () => unawaited(_load()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _campaign;
    return Scaffold(
      key: const Key('wa-campaign'),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const WaHeader(WaHe.campaign),
            Expanded(
              child: c == null
                  ? (_error != null
                        ? ErrorView(error: _error!, onRetry: _load)
                        : const SingleChildScrollView(child: SkeletonList()))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _content(context, c),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, WaCampaign c) {
    final p = context.palette;
    final n = c.counts;
    return ListView(
      key: const Key('wa-campaign-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        Space.page,
        Space.s,
        Space.page,
        Space.xxl,
      ),
      children: [
        AppCard(
          key: const Key('wa-campaign-summary'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      waDateTime(c.createdAt),
                      style: AppText.secondary.copyWith(color: p.muted),
                    ),
                  ),
                  waCampaignPill(c),
                ],
              ),
              if ((c.bodyText ?? '').isNotEmpty) ...[
                const SizedBox(height: Space.m),
                WaBubble(bodyText: c.bodyText!),
              ],
              if (c.sending) ...[
                const SizedBox(height: Space.s),
                Text(
                  WaHe.autoRefresh,
                  key: const Key('wa-campaign-refreshing'),
                  style: AppText.secondary.copyWith(color: p.muted),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Space.m),
        AppCard(
          key: const Key('wa-campaign-counts'),
          child: Column(
            children: [
              _count(WaHe.countQueued, n.queued, 'queued'),
              _count(WaHe.countSent, n.sent, 'sent'),
              _count(WaHe.countDelivered, n.delivered, 'delivered'),
              _count(WaHe.countRead, n.read, 'read'),
              _count(
                WaHe.countFailed,
                n.failed,
                'failed',
                color: n.failed > 0 ? p.danger : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.l),
        Semantics(
          header: true,
          child: const Text(WaHe.recipientsTitle, style: AppText.title),
        ),
        const SizedBox(height: Space.s),
        for (final r in c.recipients) _RecipientRow(recipient: r),
      ],
    );
  }

  Widget _count(String label, int value, String key, {Color? color}) =>
      WaValueRow(
        key: Key('wa-count-$key'),
        label: label,
        value: '$value',
        valueStyle: AppText.headline.copyWith(color: color),
      );
}

class _RecipientRow extends StatelessWidget {
  const _RecipientRow({required this.recipient});
  final WaRecipient recipient;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = recipient;
    return Container(
      key: Key('wa-recipient-${r.customerId}'),
      constraints: const BoxConstraints(minHeight: Hit.min),
      padding: const EdgeInsets.symmetric(vertical: Space.s),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PersonName(r.name),
                if (r.errorMessage != null)
                  Text(
                    r.errorMessage!,
                    style: AppText.secondary.copyWith(color: p.danger),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Space.m),
          WaPill(WaHe.recipientStatus(r.status), waRecipientTone(r.status)),
        ],
      ),
    );
  }
}

class WaCampaignsScreen extends StatefulWidget {
  const WaCampaignsScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;

  @override
  State<WaCampaignsScreen> createState() => _WaCampaignsScreenState();
}

class _WaCampaignsScreenState extends State<WaCampaignsScreen> {
  List<WaCampaign>? _campaigns;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final list = await fetchGroupWaCampaigns(widget.groupId);
      if (mounted) {
        setState(() {
          _campaigns = list;
          _error = null;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _open(WaCampaign c) async {
    await openWaCampaign(context, c.id);
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final list = _campaigns;
    final p = context.palette;
    return Scaffold(
      key: const Key('wa-campaigns'),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WaHeader(WaHe.previous, subtitle: widget.groupName),
            Expanded(
              child: list == null
                  ? (_error != null
                        ? ErrorView(error: _error!, onRetry: _load)
                        : const SingleChildScrollView(child: SkeletonList()))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                          Space.page,
                          Space.s,
                          Space.page,
                          Space.xxl,
                        ),
                        children: [
                          if (list.isEmpty)
                            const EmptyState(
                              icon: Iconsax.message_text,
                              title: WaHe.previous,
                              message: WaHe.noCampaigns,
                            ),
                          for (final c in list) ...[
                            AppCard(
                              key: Key('wa-campaign-row-${c.id}'),
                              onTap: () => unawaited(_open(c)),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (c.bodyText ?? '').isNotEmpty
                                              ? waPreviewText(
                                                  c.bodyText!,
                                                  WaHe.sampleName,
                                                )
                                              : c.templateName,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppText.body,
                                        ),
                                        const SizedBox(height: Space.xs),
                                        Text(
                                          '${waDateTime(c.createdAt)} · '
                                          '${WaHe.campaignLine(c.counts.accepted, c.counts.total)}',
                                          style: AppText.secondary.copyWith(
                                            color: p.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: Space.m),
                                  waCampaignPill(c),
                                ],
                              ),
                            ),
                            const SizedBox(height: Space.s),
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
