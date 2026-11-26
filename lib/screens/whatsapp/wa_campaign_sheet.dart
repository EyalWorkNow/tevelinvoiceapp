// וואטסאפ עסקי — from a group (when the business's number is connected):
//  1. the choice: "שליחה אוטומטית מהמספר שלך" or "תור הקשה לכל לקוח";
//  2. the campaign sheet: pick an approved template (none → a link to create
//     one), the server's preview (who gets it, who is skipped and why, the
//     quota left), send with a confirm — once, under an Idempotency-Key that
//     a retry of the same confirm re-sends.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/client.dart';
import '../../api/whatsapp_business_api.dart';
import '../../state/session.dart';
import '../../ui/ds.dart';
import '../../util/labels/common_he.dart';
import '../../util/labels/whatsapp_business_he.dart';
import 'wa_widgets.dart';
import 'whatsapp_business_screen.dart';

enum WaSendChoice { auto, queue }

Future<WaSendChoice?> showWaSendChoice(BuildContext context) =>
    showAppSheet<WaSendChoice>(
      context,
      builder: (sheet) => Column(
        key: const Key('wa-choice'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetTitle(WaHe.choiceTitle),
          _ChoiceCard(
            key: const Key('wa-choice-auto'),
            icon: Iconsax.flash_1,
            title: WaHe.choiceAuto,
            hint: WaHe.choiceAutoHint,
            onTap: () => Navigator.of(sheet).pop(WaSendChoice.auto),
          ),
          const SizedBox(height: Space.m),
          _ChoiceCard(
            key: const Key('wa-choice-queue'),
            icon: Iconsax.message,
            title: WaHe.choiceQueue,
            hint: WaHe.choiceQueueHint,
            onTap: () => Navigator.of(sheet).pop(WaSendChoice.queue),
          ),
        ],
      ),
    );

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.tint(p.ink),
      borderRadius: BorderRadius.circular(Radii.card / 2),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.card),
          child: Row(
            children: [
              Icon(icon, color: p.ink, size: 26),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.headline),
                    const SizedBox(height: Space.xs),
                    Text(
                      hint,
                      style: AppText.secondary.copyWith(color: p.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.s),
              Icon(Icons.chevron_left, color: p.muted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// The campaign sheet. Returns the new campaign's id (null = cancelled).
Future<String?> showWaCampaignSheet(
  BuildContext context, {
  required String groupId,
  required String groupName,
}) => showAppSheet<String>(
  context,
  builder: (_) => WaCampaignSheet(groupId: groupId, groupName: groupName),
);

class WaCampaignSheet extends StatefulWidget {
  const WaCampaignSheet({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;

  @override
  State<WaCampaignSheet> createState() => _WaCampaignSheetState();
}

class _WaCampaignSheetState extends State<WaCampaignSheet> {
  List<WaTemplate>? _templates;
  Object? _loadError;
  WaTemplate? _selected;
  WaCampaignPreview? _preview;
  bool _previewing = false;
  bool _sending = false;
  String? _sendError;

  /// One key per confirmed template: a retry re-sends it.
  String? _key;
  String? _keyFor;

  @override
  void initState() {
    super.initState();
    unawaited(_loadTemplates());
  }

  Future<void> _loadTemplates() async {
    setState(() => _loadError = null);
    try {
      final all = await fetchWaTemplates();
      if (!mounted) return;
      final approved = [
        for (final t in all)
          if (t.approved) t,
      ];
      setState(() => _templates = all);
      if (_selected == null && approved.length == 1) {
        unawaited(_select(approved.single));
      }
    } on Object catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  Future<void> _select(WaTemplate t) async {
    setState(() {
      _selected = t;
      _preview = null;
      _previewing = true;
      _sendError = null;
    });
    try {
      final p = await previewWaCampaign(widget.groupId, t.id);
      if (!mounted || _selected?.id != t.id) return;
      setState(() => _preview = p);
    } on Object catch (e) {
      if (mounted && _selected?.id == t.id) {
        setState(() => _sendError = waErrorText(e));
      }
    } finally {
      if (mounted && _selected?.id == t.id) {
        setState(() => _previewing = false);
      }
    }
  }

  Future<void> _createTemplate() async {
    await openWaBusiness(context);
    if (mounted) await _loadTemplates();
  }

  Future<void> _send() async {
    final t = _selected;
    final p = _preview;
    if (t == null || p == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        key: const Key('wa-campaign-confirm'),
        title: Text(WaHe.confirmTitle(p.recipients)),
        content: const Text(WaHe.confirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text(CommonHe.cancel),
          ),
          FilledButton(
            key: const Key('wa-campaign-confirm-ok'),
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text(WaHe.send),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (_keyFor != t.id) {
      _key = ApiClient.newIdempotencyKey();
      _keyFor = t.id;
    }
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      final id = await startWaCampaign(
        widget.groupId,
        t.id,
        idempotencyKey: _key!,
      );
      if (mounted) Navigator.of(context).pop(id);
    } on Object catch (e) {
      if (!mounted) return;
      // A refusal (409 …) is final for this key; a network error keeps it.
      if (!(e is ApiException && e.isNetwork)) _keyFor = null;
      setState(() {
        _sending = false;
        _sendError = waErrorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final templates = _templates;
    final approved = [
      for (final t in templates ?? const <WaTemplate>[])
        if (t.approved) t,
    ];
    final pending = (templates ?? const <WaTemplate>[]).any(
      (t) => t.status == 'PENDING',
    );
    final preview = _preview;
    final canSend =
        preview != null &&
        preview.canSend &&
        preview.recipients > 0 &&
        !_sending &&
        !_previewing &&
        !session.offline;
    return Column(
      key: const Key('wa-campaign-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(WaHe.campaignTitle, subtitle: widget.groupName),
        if (_loadError != null)
          ErrorView(error: _loadError!, onRetry: _loadTemplates)
        else if (templates == null)
          const SkeletonList(rows: 3)
        else if (approved.isEmpty) ...[
          Text(
            WaHe.noApproved,
            key: const Key('wa-campaign-none'),
            style: AppText.body,
          ),
          if (pending) ...[
            const SizedBox(height: Space.xs),
            Text(
              WaHe.pendingNote,
              style: AppText.secondary.copyWith(color: p.muted),
            ),
          ],
          const SizedBox(height: Space.l),
          OutlinedButton.icon(
            key: const Key('wa-campaign-create-template'),
            onPressed: () => unawaited(_createTemplate()),
            icon: const Icon(Iconsax.add),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: const StadiumBorder(),
            ),
            label: const Text(WaHe.createTemplate),
          ),
        ] else ...[
          Text(WaHe.pickTemplate, style: AppText.body.copyWith(color: p.muted)),
          const SizedBox(height: Space.s),
          for (final t in approved) _templateOption(context, t),
          if (_selected != null) ...[
            const SizedBox(height: Space.m),
            WaBubble(bodyText: _selected!.bodyText),
          ],
          const SizedBox(height: Space.m),
          if (_previewing)
            Text(
              WaHe.checking,
              key: const Key('wa-campaign-checking'),
              style: AppText.secondary.copyWith(color: p.muted),
            ),
          if (preview != null) _previewBlock(context, preview),
          if (_sendError != null) ...[
            const SizedBox(height: Space.s),
            Text(
              _sendError!,
              key: const Key('wa-campaign-error'),
              style: AppText.body.copyWith(color: p.danger),
            ),
          ],
          const SizedBox(height: Space.l),
          FilledButton.icon(
            key: const Key('wa-campaign-send'),
            onPressed: canSend ? () => unawaited(_send()) : null,
            icon: const Icon(Iconsax.send_2),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: const StadiumBorder(),
            ),
            label: Text(
              preview != null && preview.recipients > 0
                  ? WaHe.recipients(preview.recipients)
                  : WaHe.send,
            ),
          ),
        ],
      ],
    );
  }

  Widget _templateOption(BuildContext context, WaTemplate t) {
    final p = context.palette;
    final on = _selected?.id == t.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: Material(
        color: on ? p.tint(p.ok) : p.tint(p.ink),
        borderRadius: BorderRadius.circular(Radii.card / 2),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('wa-campaign-template-${t.id}'),
          onTap: _sending ? null : () => unawaited(_select(t)),
          child: Padding(
            padding: const EdgeInsets.all(Space.m),
            child: Row(
              children: [
                Icon(
                  on ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: on ? p.ok : p.muted,
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Text(
                    t.bodyText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _previewBlock(BuildContext context, WaCampaignPreview preview) {
    final p = context.palette;
    final lines = waPreviewLines(preview);
    final block = preview.canSend ? null : waBlockText(preview.blockReason);
    return Column(
      key: const Key('wa-campaign-preview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < lines.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.xs),
            child: Text(
              lines[i],
              style: i == 0
                  ? AppText.headline
                  : AppText.body.copyWith(color: p.muted),
            ),
          ),
        if (block != null) ...[
          const SizedBox(height: Space.xs),
          Text(
            block,
            key: const Key('wa-campaign-block'),
            style: AppText.body.copyWith(color: p.danger),
          ),
        ],
      ],
    );
  }
}
