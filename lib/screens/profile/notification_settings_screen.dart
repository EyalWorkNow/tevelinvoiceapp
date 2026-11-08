// הגדרות › התראות (PUSH-001). Built from GET /mobile/push/catalogue — the server's catalogue is
// the single source of truth, so a new kind of notification appears here without an app update.
// Categories on/off, the default-off kinds (e.g. "הלקוח צפה בהצעת המחיר"), quiet hours, and the
// iOS permission state with a way to turn it on.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tevel_push/tevel_push.dart';

import '../../api/client.dart';
import '../../push/push_service.dart';
import '../../ui/theme.dart';
import '../../util/allowed_urls.dart';
import '../../util/labels/labels.dart';

class PushCategoryView {
  const PushCategoryView(this.id, this.label, this.description, this.canDisable);
  final String id;
  final String label;
  final String description;
  final bool canDisable;
}

class PushKindView {
  const PushKindView(this.id, this.category, this.title, this.defaultOn);
  final String id;
  final String category;
  final String title;
  final bool defaultOn;
}

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key, this.api, this.push});

  final ApiClient? api;
  final PushService? push;

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  ApiClient get _api => widget.api ?? ApiClient.instance;
  PushService get _push => widget.push ?? PushService.instance;

  List<PushCategoryView> _categories = const [];
  List<PushKindView> _optIn = const [];
  Set<String> _disabled = {};
  Set<String> _enabledKinds = {};
  bool _quiet = true;
  PushAuthorization _auth = PushAuthorization.notDetermined;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _api.get('/mobile/push/catalogue'),
        _api.get('/mobile/push/preferences'),
      ]);
      final auth = await _push.status();
      final catalogue = results[0];
      final prefs = results[1];
      if (!mounted) return;
      setState(() {
        _categories = [
          for (final c in (catalogue['categories'] as List).cast<Map<String, dynamic>>())
            PushCategoryView(
              c['id'] as String,
              c['label'] as String,
              c['description'] as String,
              c['canDisable'] as bool,
            ),
        ];
        _optIn = [
          for (final k in (catalogue['kinds'] as List).cast<Map<String, dynamic>>())
            if (k['defaultOn'] == false)
              PushKindView(k['id'] as String, k['category'] as String, k['title'] as String, false),
        ];
        _disabled = {...(prefs['disabledCategories'] as List).cast<String>()};
        _enabledKinds = {...(prefs['enabledKinds'] as List).cast<String>()};
        _quiet = prefs['quietHours'] as bool? ?? true;
        _auth = auth;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => (_error = e.messageHe, _loading = false));
    }
  }

  Future<void> _save() async {
    try {
      await _api.put('/mobile/push/preferences', {
        'disabledCategories': _disabled.toList()..sort(),
        'enabledKinds': _enabledKinds.toList()..sort(),
        'quietHours': _quiet,
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.messageHe)));
      await _load(); // back to what the server has
    }
  }

  Future<void> _enable() async {
    if (_auth == PushAuthorization.denied) {
      await launchAllowed(Uri.parse('app-settings:'));
      return;
    }
    await _push.enable(context);
    final auth = await _push.status();
    if (mounted) setState(() => _auth = auth);
  }

  bool get _allowed => _auth == PushAuthorization.authorized || _auth == PushAuthorization.provisional;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(PushHe.settingsTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!, style: AppText.body))
          : ListView(
              key: const Key('push-settings'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (!_allowed)
                  Card(
                    key: const Key('push-permission-card'),
                    child: ListTile(
                      title: const Text(PushHe.offTitle, style: AppText.body),
                      subtitle: Text(
                        _auth == PushAuthorization.denied
                            ? PushHe.offDenied
                            : PushHe.offAsk,
                      ),
                      trailing: FilledButton(
                        key: const Key('push-enable'),
                        onPressed: _enable,
                        child: Text(_auth == PushAuthorization.denied ? PushHe.openSettings : PushHe.enable),
                      ),
                    ),
                  ),
                for (final c in _categories) ...[
                  SwitchListTile.adaptive(
                    key: Key('push-cat-${c.id}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(c.label, style: AppText.body),
                    subtitle: Text(c.canDisable ? c.description : '${c.description} · ${PushHe.alwaysOn}'),
                    value: !_disabled.contains(c.id),
                    onChanged: c.canDisable
                        ? (on) {
                            setState(() => on ? _disabled.remove(c.id) : _disabled.add(c.id));
                            unawaited(_save());
                          }
                        : null,
                  ),
                  for (final k in _optIn.where((k) => k.category == c.id))
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 16),
                      child: SwitchListTile.adaptive(
                        key: Key('push-kind-${k.id}'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(k.title, style: AppText.body),
                        subtitle: const Text(PushHe.defaultOff),
                        value: _enabledKinds.contains(k.id) && !_disabled.contains(c.id),
                        onChanged: _disabled.contains(c.id)
                            ? null
                            : (on) {
                                setState(() => on ? _enabledKinds.add(k.id) : _enabledKinds.remove(k.id));
                                unawaited(_save());
                              },
                      ),
                    ),
                ],
                const Divider(height: 32),
                SwitchListTile.adaptive(
                  key: const Key('push-quiet'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text(PushHe.quietTitle, style: AppText.body),
                  subtitle: const Text(PushHe.quietBody),
                  value: _quiet,
                  onChanged: (on) {
                    setState(() => _quiet = on);
                    unawaited(_save());
                  },
                ),
              ],
            ),
    );
  }
}
