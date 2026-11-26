// וואטסאפ עסקי (ניהול → עוד הגדרות, owner / partner with business:configure).
// Three states:
//  * NOT_CONNECTED: what it is (your number, monthly quota, consent only,
//    Meta templates) + "חיבור מספר וואטסאפ" → a one-time Embedded Signup page
//    in the in-app Safari view; the status refreshes on resume and every few
//    seconds while that page may still be open (SFSafariViewController
//    reports no dismissal).
//  * CONNECTED: number, verified name, quality, quota bar, the templates
//    with status pills, "תבנית חדשה", and "ניתוק" (with a confirm).
//  * ERROR: the server's message + "חיבור מחדש".

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/client.dart';
import '../../api/whatsapp_business_api.dart';
import '../../state/session.dart';
import '../../ui/ds.dart';
import '../../ui/widgets/notch_notice.dart';
import '../../util/allowed_urls.dart';
import '../../util/labels/common_he.dart';
import '../../util/labels/status_he.dart' show Tone;
import '../../util/labels/whatsapp_business_he.dart';
import 'wa_template_sheet.dart';
import 'wa_widgets.dart';

Future<void> openWaBusiness(BuildContext context) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    settings: const RouteSettings(name: '/business/whatsapp'),
    builder: (_) => const WhatsAppBusinessScreen(),
  ),
);

/// How often the status is re-read while the connect page may be open.
Duration waConnectPollEvery = const Duration(seconds: 5);

class WhatsAppBusinessScreen extends StatefulWidget {
  const WhatsAppBusinessScreen({super.key});

  @override
  State<WhatsAppBusinessScreen> createState() => _WhatsAppBusinessScreenState();
}

class _WhatsAppBusinessScreenState extends State<WhatsAppBusinessScreen>
    with WidgetsBindingObserver {
  WaBusinessStatus? _status;
  List<WaTemplate>? _templates;
  Object? _error;
  bool _busy = false;
  Timer? _poll;
  DateTime? _pollUntil;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load(quiet: true));
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _error = null);
    try {
      final s = await fetchWaStatus();
      waStatus.value = s;
      List<WaTemplate>? templates;
      if (s.connected) templates = await fetchWaTemplates();
      if (!mounted) return;
      setState(() {
        _status = s;
        _templates = templates;
        _error = null;
      });
      if (s.connected) _stopPolling();
    } on Object catch (e) {
      if (mounted && !quiet) setState(() => _error = e);
    }
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
    _pollUntil = null;
  }

  void _startPolling() {
    _poll?.cancel();
    _pollUntil = DateTime.now().add(const Duration(minutes: 15));
    _poll = Timer.periodic(waConnectPollEvery, (_) {
      final until = _pollUntil;
      if (!mounted || until == null || DateTime.now().isAfter(until)) {
        _stopPolling();
        if (mounted) setState(() {});
        return;
      }
      unawaited(_load(quiet: true));
    });
    setState(() {});
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      final uri = await createWaConnectLink();
      await openWaConnectPage(uri, apiOrigin: ApiClient.baseUrl);
      if (!mounted) return;
      _startPolling();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text(WaHe.disconnectTitle),
        content: const Text(WaHe.disconnectBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text(CommonHe.cancel),
          ),
          FilledButton(
            key: const Key('wa-disconnect-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: d.palette.danger,
              foregroundColor: d.palette.onDanger,
            ),
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text(WaHe.disconnectConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await disconnectWa();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showNotchNotice(const SnackBar(content: Text(WaHe.disconnected)));
      await _load();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newTemplate() async {
    final t = await showWaTemplateSheet(context);
    if (t == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showNotchNotice(const SnackBar(content: Text(WaHe.templateSent)));
    await _load(quiet: true);
  }

  Future<void> _openTemplate(WaTemplate t) async {
    if (!await showWaTemplateDetails(context, t) || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showNotchNotice(const SnackBar(content: Text(WaHe.templateDeleted)));
    await _load(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    return Scaffold(
      key: const Key('wa-business'),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const WaHeader(WaHe.title),
            OfflineBanner(visible: session.offline),
            Expanded(
              child: s == null
                  ? (_error != null
                        ? ErrorView(error: _error!, onRetry: _load)
                        : const SingleChildScrollView(child: SkeletonList()))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        key: const Key('wa-business-list'),
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                          Space.page,
                          Space.s,
                          Space.page,
                          Space.xxl,
                        ),
                        children: switch (s) {
                          _ when !s.available => [_unavailable(context)],
                          _ when s.status == waConnected => _connected(
                            context,
                            s,
                          ),
                          _ when s.status == waError => _errorState(context, s),
                          _ => _notConnected(context),
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _unavailable(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.xl),
    child: Text(
      WaHe.unavailable,
      key: const Key('wa-unavailable'),
      style: AppText.body.copyWith(color: context.palette.muted),
    ),
  );

  Widget _connectButton(String label) => FilledButton.icon(
    key: const Key('wa-connect'),
    onPressed: _busy || session.offline ? null : () => unawaited(_connect()),
    icon: const Icon(Iconsax.whatsapp),
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      shape: const StadiumBorder(),
    ),
    label: Text(label),
  );

  Widget _waiting(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.m),
    child: Row(
      key: const Key('wa-waiting'),
      children: [
        const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: Space.s),
        Expanded(
          child: Text(
            WaHe.waitingForConnect,
            style: AppText.secondary.copyWith(color: context.palette.muted),
          ),
        ),
      ],
    ),
  );

  List<Widget> _notConnected(BuildContext context) {
    final p = context.palette;
    return [
      AppCard(
        key: const Key('wa-intro'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Iconsax.whatsapp, color: p.whatsapp, size: 28),
                const SizedBox(width: Space.m),
                const Expanded(
                  child: Text(WaHe.introTitle, style: AppText.headline),
                ),
              ],
            ),
            const SizedBox(height: Space.m),
            for (final line in WaHe.introPoints)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.s),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Icon(Iconsax.tick_circle, size: 18, color: p.ok),
                    ),
                    const SizedBox(width: Space.s),
                    Expanded(child: Text(line, style: AppText.body)),
                  ],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: Space.xl),
      _connectButton(WaHe.connect),
      const SizedBox(height: Space.s),
      Text(
        WaHe.connectHint,
        style: AppText.secondary.copyWith(color: p.muted),
        textAlign: TextAlign.center,
      ),
      if (_poll != null) _waiting(context),
    ];
  }

  List<Widget> _errorState(BuildContext context, WaBusinessStatus s) {
    final p = context.palette;
    return [
      AppCard(
        key: const Key('wa-error'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Iconsax.warning_2, color: p.danger, size: 26),
                const SizedBox(width: Space.m),
                const Expanded(
                  child: Text(WaHe.errorTitle, style: AppText.headline),
                ),
              ],
            ),
            const SizedBox(height: Space.s),
            Text(
              s.errorMessage ?? WaHe.errorFallback,
              key: const Key('wa-error-message'),
              style: AppText.body,
            ),
          ],
        ),
      ),
      const SizedBox(height: Space.xl),
      _connectButton(WaHe.reconnect),
      if (_poll != null) _waiting(context),
    ];
  }

  List<Widget> _connected(BuildContext context, WaBusinessStatus s) {
    final p = context.palette;
    final templates = _templates ?? const <WaTemplate>[];
    final heavy = s.quotaFraction >= 0.9;
    return [
      AppCard(
        key: const Key('wa-connected'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Iconsax.whatsapp, color: p.whatsapp, size: 28),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Text(
                    s.verifiedName ?? s.phoneDisplay ?? WaHe.title,
                    style: AppText.headline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: Space.s),
                const WaPill(WaHe.connected, Tone.ok),
              ],
            ),
            const SizedBox(height: Space.s),
            if (s.phoneDisplay != null)
              WaValueRow(
                key: const Key('wa-number'),
                label: WaHe.number,
                value: s.phoneDisplay!,
                ltrValue: true,
              ),
            if (s.verifiedName != null)
              WaValueRow(label: WaHe.verifiedName, value: s.verifiedName!),
            WaValueRow(
              key: const Key('wa-quality'),
              label: WaHe.quality,
              value: WaHe.qualityLabel(s.qualityRating),
            ),
            if (s.coexistence) ...[
              const SizedBox(height: Space.s),
              Text(
                WaHe.coexistence,
                key: const Key('wa-coexistence'),
                style: AppText.secondary.copyWith(color: p.muted),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: Space.m),
      AppCard(
        key: const Key('wa-quota'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WaValueRow(
              label: WaHe.quotaTitle,
              value: WaHe.quotaLine(s.usedThisMonth, s.monthlyQuota),
              valueStyle: AppText.headline,
            ),
            const SizedBox(height: Space.s),
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.chip),
              child: LinearProgressIndicator(
                key: const Key('wa-quota-bar'),
                value: s.quotaFraction,
                minHeight: 8,
                backgroundColor: p.line,
                color: heavy ? p.warn : p.ok,
              ),
            ),
            const SizedBox(height: Space.s),
            Text(
              WaHe.quotaLeft(s.quotaLeft),
              style: AppText.secondary.copyWith(color: p.muted),
            ),
          ],
        ),
      ),
      const SizedBox(height: Space.l),
      Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: const Text(WaHe.templates, style: AppText.title),
            ),
          ),
          TextButton.icon(
            key: const Key('wa-template-new'),
            onPressed: session.offline ? null : () => unawaited(_newTemplate()),
            icon: const Icon(Iconsax.add),
            label: const Text(WaHe.newTemplate),
          ),
        ],
      ),
      const SizedBox(height: Space.s),
      if (templates.isEmpty)
        Text(
          WaHe.noTemplates,
          key: const Key('wa-templates-empty'),
          style: AppText.body.copyWith(color: p.muted),
        ),
      for (final t in templates) ...[
        _TemplateRow(
          key: Key('wa-template-${t.id}'),
          template: t,
          onTap: () => unawaited(_openTemplate(t)),
        ),
        const SizedBox(height: Space.s),
      ],
      const SizedBox(height: Space.xl),
      Center(
        child: TextButton.icon(
          key: const Key('wa-disconnect'),
          onPressed: _busy || session.offline
              ? null
              : () => unawaited(_disconnect()),
          style: TextButton.styleFrom(foregroundColor: p.danger),
          icon: const Icon(Iconsax.logout),
          label: const Text(WaHe.disconnect),
        ),
      ),
    ];
  }
}

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({super.key, required this.template, required this.onTap});

  final WaTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = template;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.card,
        vertical: Space.m,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  t.bodyText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body,
                ),
              ),
              const SizedBox(width: Space.m),
              WaPill(WaHe.templateStatus(t.status), waTemplateTone(t.status)),
            ],
          ),
          if (t.rejectedReason != null) ...[
            const SizedBox(height: Space.xs),
            Text(
              WaHe.rejected(t.rejectedReason!),
              style: AppText.secondary.copyWith(color: p.danger),
            ),
          ],
        ],
      ),
    );
  }
}
