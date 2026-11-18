import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../router.dart' show BusinessSection, openBusinessSection;
import '../../util/labels/notifications_he.dart';

import '../../state/system_notices.dart';
import '../../util/labels/system_notices_he.dart';
import '../../util/labels/common_he.dart';
import '../../ui/ds.dart';
import '../../ui/widgets/notch_notice.dart';
import 'business_template.dart';

class SystemNoticeSettings extends StatefulWidget {
  const SystemNoticeSettings({super.key});
  @override
  State<SystemNoticeSettings> createState() => _SystemNoticeSettingsState();
}

class _SystemNoticeSettingsState extends State<SystemNoticeSettings> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    systemNotices.refresh().catchError((Object error) {
      if (mounted) showErrorSnack(context, error);
    });
  }

  Future<void> _change(bool enabled) async {
    setState(() => _busy = true);
    try {
      if (enabled) {
        await systemNotices.enable();
      } else {
        await systemNotices.disable();
      }
    } on Object catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retry() async {
    setState(() => _busy = true);
    try {
      await systemNotices.retryRegistration();
      if (mounted) {
        ScaffoldMessenger.of(context).showNotchNotice(
          const SnackBar(content: Text(SystemNoticesHe.retryDone)),
        );
      }
    } on Object catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testLocal() async {
    setState(() => _busy = true);
    try {
      await systemNotices.testLocal();
      if (mounted) {
        ScaffoldMessenger.of(context).showNotchNotice(
          const SnackBar(content: Text(SystemNoticesHe.testLocalQueued)),
        );
      }
    } on Object catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => BusinessPage(
    title: SystemNoticesHe.title,
    children: [
      ListenableBuilder(
        listenable: systemNotices,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile.adaptive(
              value: systemNotices.enabled,
              onChanged: _busy || !systemNotices.supported ? null : _change,
              title: const Text(SystemNoticesHe.enabled),
              subtitle: const Text(SystemNoticesHe.summary),
            ),
            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: Space.s),
            OutlinedButton.icon(
              onPressed: _busy ? null : _testLocal,
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text(SystemNoticesHe.testLocal),
            ),
            const SizedBox(height: Space.xs),
            Text(SystemNoticesHe.testLocalHint, style: AppText.secondary),
            if (systemNotices.enabled && systemNotices.deliveryConfigured)
              const Text(SystemNoticesHe.deliveryReady),
            const SizedBox(height: Space.s),
            BusinessRow(
              key: const Key('system-notices-prefs'),
              label: NotificationPrefsHe.row,
              value: NotificationPrefsHe.rowHint,
              icon: Iconsax.setting_4,
              onTap: () => openBusinessSection(context, BusinessSection.alerts),
            ),
            const SizedBox(height: Space.l),
            const Text(SystemNoticesHe.outside, style: AppText.body),
            const SizedBox(height: Space.s),
            const Text(SystemNoticesHe.explanation),
            if (systemNotices.syncError != null) ...[
              const SizedBox(height: Space.l),
              Text(systemNotices.problemHe ?? SystemNoticesHe.connectionError),
              if (!systemNotices.mfaRequired)
                TextButton(
                  onPressed: _busy ? null : () => _change(true),
                  child: const Text(CommonHe.retry),
                ),
            ],
            if (systemNotices.supported) ...[
              const SizedBox(height: Space.l),
              PushStatusPanel(
                diagnostics: systemNotices.diagnostics,
                busy: _busy,
                onRetry: _retry,
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

/// "סטטוס התראות": iOS permission, Apple token, server registration and the
/// last error code (never a token or a credential), plus "נסה לרשום שוב".
class PushStatusPanel extends StatelessWidget {
  const PushStatusPanel({
    super.key,
    required this.diagnostics,
    required this.busy,
    required this.onRetry,
  });

  final PushDiagnostics diagnostics;
  final bool busy;
  final VoidCallback onRetry;

  static String permissionHe(String? value) => switch (value) {
    'authorized' ||
    'provisional' ||
    'ephemeral' => SystemNoticesHe.permissionAllowed,
    'denied' => SystemNoticesHe.permissionDenied,
    'notDetermined' => SystemNoticesHe.permissionNotAsked,
    _ => SystemNoticesHe.permissionUnknown,
  };

  static String serverHe(PushDiagnostics d) => d.registered
      ? SystemNoticesHe.registered
      : d.businessRegistered || d.catalogueRegistered
      ? SystemNoticesHe.partlyRegistered
      : SystemNoticesHe.notRegistered;

  @override
  Widget build(BuildContext context) {
    final d = diagnostics;
    Widget row(String key, String label, String value) => Padding(
      key: Key('push-status-$key'),
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: AppText.secondary)),
          const SizedBox(width: Space.s),
          Expanded(child: Text(value, style: AppText.body)),
        ],
      ),
    );
    return Column(
      key: const Key('push-status'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(SystemNoticesHe.status, style: AppText.body),
        const SizedBox(height: Space.xs),
        row(
          'permission',
          SystemNoticesHe.statusPermission,
          permissionHe(d.osAuthorization),
        ),
        row(
          'token',
          SystemNoticesHe.statusToken,
          d.tokenReceived ? SystemNoticesHe.yes : SystemNoticesHe.no,
        ),
        row('server', SystemNoticesHe.statusServer, serverHe(d)),
        if (d.serverDeliveryConfigured != null)
          row(
            'delivery',
            SystemNoticesHe.statusDelivery,
            d.serverDeliveryConfigured!
                ? SystemNoticesHe.deliveryOn
                : SystemNoticesHe.deliveryOff,
          ),
        if (d.lastError != null)
          row('error', SystemNoticesHe.statusError, d.lastError!),
        const SizedBox(height: Space.xs),
        OutlinedButton.icon(
          key: const Key('push-status-retry'),
          onPressed: busy ? null : onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text(SystemNoticesHe.retryRegister),
        ),
      ],
    );
  }
}
