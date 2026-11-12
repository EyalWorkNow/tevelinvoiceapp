import 'package:flutter/material.dart';

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
              const Text('המכשיר רשום והשרת מוגדר לשליחת התראות'),
            const SizedBox(height: Space.l),
            const Text(SystemNoticesHe.outside, style: AppText.body),
            const SizedBox(height: Space.s),
            const Text(SystemNoticesHe.explanation),
            if (systemNotices.syncError != null) ...[
              const SizedBox(height: Space.l),
              const Text(SystemNoticesHe.connectionError),
              TextButton(
                onPressed: _busy ? null : () => _change(true),
                child: const Text(CommonHe.retry),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}
