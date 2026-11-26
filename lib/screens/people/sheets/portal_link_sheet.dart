// "שלח קישור לאזור האישי" (server 0135): the customer's permanent personal
// link — WhatsApp (to the customer's phone when known), the share sheet, or
// copy. Opened from the customer page "עוד" sheet and from the details row.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../../api/customer_portal_api.dart';
import '../../../ui/ds.dart';
import '../../../ui/widgets/notch_notice.dart';
import '../../../util/allowed_urls.dart';
import '../../../util/labels/portal_he.dart';
import '../../../util/phone.dart';
import '../../document/sheets/s6_share.dart' show textSharer;

/// Opens the sheet; [regenerate] first replaces the link (the old one dies).
/// Returns the link shown (null when it could not be made).
Future<PortalLink?> showPortalLinkSheet(
  BuildContext context, {
  required String customerId,
  required String name,
  String? phone,
  String? email,
  bool regenerate = false,
}) => showAppSheet<PortalLink>(
  context,
  builder: (_) => PortalLinkSheet(
    customerId: customerId,
    name: name,
    phone: phone,
    email: email,
    regenerate: regenerate,
  ),
);

class PortalLinkSheet extends StatefulWidget {
  const PortalLinkSheet({
    super.key,
    required this.customerId,
    required this.name,
    this.phone,
    this.email,
    this.regenerate = false,
  });

  final String customerId;
  final String name;
  final String? phone;
  final String? email;
  final bool regenerate;

  @override
  State<PortalLinkSheet> createState() => _PortalLinkSheetState();
}

class _PortalLinkSheetState extends State<PortalLinkSheet> {
  PortalLink? _link;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final link = widget.regenerate
          ? await regeneratePortalLink(widget.customerId)
          : await ensurePortalLink(widget.customerId);
      if (mounted) setState(() => _link = link);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String get _text {
    final l = _link!;
    final t = l.whatsappText;
    return t == null || t.isEmpty ? l.url : t;
  }

  Future<void> _whatsapp() async {
    HapticFeedback.selectionClick();
    await launchAllowed(whatsAppUri(phone: waPhone(widget.phone), text: _text));
  }

  Future<void> _share() async {
    HapticFeedback.selectionClick();
    await textSharer(_text);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _link!.url));
    HapticFeedback.lightImpact();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showNotchNotice(const SnackBar(content: Text(PortalHe.copied)));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final link = _link;
    final error = _error;
    final email = (widget.email ?? '').trim();
    return Column(
      key: const Key('portal-link-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(
          PortalHe.sheetTitle,
          subtitle: PortalHe.sheetSubtitle(widget.name),
        ),
        if (error != null)
          ErrorView(error: error, onRetry: _load)
        else if (link == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xl),
            child: Column(
              children: [
                const CircularProgressIndicator.adaptive(),
                const SizedBox(height: Space.m),
                Text(
                  PortalHe.loading,
                  style: AppText.secondary.copyWith(color: p.muted),
                ),
              ],
            ),
          )
        else ...[
          Container(
            key: const Key('portal-link-url'),
            padding: const EdgeInsets.all(Space.m),
            decoration: BoxDecoration(
              color: p.canvas,
              borderRadius: BorderRadius.circular(Space.m),
            ),
            child: Row(
              children: [
                Icon(Iconsax.link_2, size: 20, color: p.muted),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Text(
                    link.url,
                    textDirection: TextDirection.ltr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.s),
          if (email.isNotEmpty)
            Text(
              PortalHe.codeHint(ltrIsolate(email)),
              style: AppText.secondary.copyWith(color: p.muted),
            ),
          Text(
            link.lastLoginAt == null
                ? PortalHe.neverLoggedIn
                : PortalHe.lastLogin(PortalHe.when(link.lastLoginAt!)),
            key: const Key('portal-link-last-login'),
            style: AppText.secondary.copyWith(color: p.muted),
          ),
          const SizedBox(height: Space.l),
          FilledButton.icon(
            key: const Key('portal-link-whatsapp'),
            style: FilledButton.styleFrom(
              backgroundColor: p.whatsapp,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(Hit.min + 8),
            ),
            onPressed: () => unawaited(_whatsapp()),
            icon: const Icon(Iconsax.message),
            label: const Text(PortalHe.sendWhatsapp),
          ),
          const SizedBox(height: Space.s),
          OutlinedButton.icon(
            key: const Key('portal-link-share'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(Hit.min + 8),
            ),
            onPressed: () => unawaited(_share()),
            icon: const Icon(Iconsax.export_1),
            label: const Text(PortalHe.share),
          ),
          const SizedBox(height: Space.xs),
          TextButton.icon(
            key: const Key('portal-link-copy'),
            onPressed: () => unawaited(_copy()),
            icon: const Icon(Iconsax.copy),
            label: const Text(PortalHe.copy),
          ),
        ],
      ],
    );
  }
}
