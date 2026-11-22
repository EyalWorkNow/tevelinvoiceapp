// "סוגי התראות" (owner 2026-11-18): per-category on/off for the phone
// notifications, from the server's catalogue (GET /mobile/push/catalogue) and
// the user's preferences (GET/PUT /mobile/push/preferences). Reached from
// B → התראות and from the bell's "עדכונים" screen (gear). Categories the
// server marks canDisable=false (אבטחה) stay on and cannot be switched.
// "עדכונים ומבצעים מתבל": the user's own §30A marketing consent
// (GET/PUT /mobile/push/marketing-consent, invoice#61), default off, hidden on
// a server without the endpoint.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/push_preferences_api.dart';
import '../../state/accountant_store.dart';
import '../../state/business_context.dart';
import '../../util/labels/accountant_he.dart';
import '../../ui/ds.dart';
import '../../ui/widgets/notch_notice.dart';
import '../../util/labels/notifications_he.dart';
import 'business_template.dart';

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  List<PushCategory>? _categories;
  PushPreferences? _prefs;
  Object? _error;
  String? _saving;

  /// null: the server has no consent endpoint (or it failed) — no switch.
  MarketingConsent? _consent;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final consent = fetchMarketingConsent().then<MarketingConsent?>(
        (c) => c,
        onError: (Object _) => null,
      );
      final results = await Future.wait<Object>([
        fetchPushCategories(),
        fetchPushPreferences(),
      ]);
      final c = await consent;
      if (!mounted) return;
      setState(() {
        _categories = results[0] as List<PushCategory>;
        _prefs = results[1] as PushPreferences;
        _consent = c;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _toggle(PushCategory c, bool on) async {
    final before = _prefs;
    if (before == null || _saving != null) return;
    setState(() {
      _saving = c.id;
      _prefs = before.withCategory(c.id, on); // optimistic
    });
    try {
      final saved = await savePushPreferences(_prefs!);
      if (!mounted) return;
      setState(() => _prefs = saved);
      ScaffoldMessenger.of(context).showNotchNotice(
        const SnackBar(content: Text(NotificationPrefsHe.saved)),
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _prefs = before);
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  /// Accountant push kinds (feature 4), muted one by one.
  Future<void> _toggleKind(String kind, bool on) async {
    final before = _prefs;
    if (before == null || _saving != null) return;
    setState(() {
      _saving = kind;
      _prefs = before.withKind(kind, on);
    });
    try {
      final saved = await savePushPreferences(_prefs!);
      if (!mounted) return;
      // An older server drops disabledKinds: keep what the user chose.
      if (saved.servesKinds) setState(() => _prefs = saved);
      ScaffoldMessenger.of(context).showNotchNotice(
        const SnackBar(content: Text(NotificationPrefsHe.saved)),
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _prefs = before);
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  Future<void> _toggleMarketing(bool on) async {
    final before = _consent;
    if (before == null || _saving != null) return;
    setState(() {
      _saving = 'marketing';
      _consent = MarketingConsent(granted: on, text: before.text);
    });
    try {
      final saved = await saveMarketingConsent(on);
      if (!mounted) return;
      setState(
        () => _consent = MarketingConsent(
          granted: saved.granted,
          text: saved.text.isEmpty ? before.text : saved.text,
        ),
      );
      ScaffoldMessenger.of(context).showNotchNotice(
        const SnackBar(content: Text(NotificationPrefsHe.saved)),
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _consent = before);
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories;
    final prefs = _prefs;
    if (categories == null || prefs == null) {
      return Scaffold(
        appBar: AppBar(title: const Text(NotificationPrefsHe.title)),
        body: SafeArea(
          child: _error == null
              ? const SkeletonList(rows: 6)
              : ErrorView(error: _error!, onRetry: () => unawaited(_load())),
        ),
      );
    }
    return BusinessPage(
      key: const Key('notification-prefs'),
      title: NotificationPrefsHe.title,
      onRefresh: _load,
      children: [
        Text(NotificationPrefsHe.intro, style: AppText.secondary),
        const SizedBox(height: Space.s),
        for (final c in categories)
          SwitchListTile.adaptive(
            key: Key('notification-pref-${c.id}'),
            value: !c.canDisable || prefs.isOn(c.id),
            onChanged: !c.canDisable || _saving != null
                ? null
                : (on) => unawaited(_toggle(c, on)),
            title: Text(c.label),
            subtitle: Text(
              c.canDisable
                  ? c.description
                  : '${c.description}\n${NotificationPrefsHe.alwaysOn}',
            ),
          ),
        if (accountantStore.isAccountant ||
            businessContext.caps.homeIsReports) ...[
          const SizedBox(height: Space.m),
          Text(AccountantHe.prefsTitle, style: AppText.headline),
          for (final (kind, title, hint) in const [
            (
              'ACCOUNTANT_ACCESS_APPROVED',
              AccountantHe.prefApproved,
              AccountantHe.prefApprovedHint,
            ),
            (
              'ACCOUNTANT_CORRECTION_ANSWERED',
              AccountantHe.prefCorrection,
              AccountantHe.prefCorrectionHint,
            ),
            (
              'ACCOUNTANT_EXPENSES_DIGEST',
              AccountantHe.prefDigest,
              AccountantHe.prefDigestHint,
            ),
          ])
            SwitchListTile.adaptive(
              key: Key('notification-kind-$kind'),
              value: prefs.kindOn(kind),
              onChanged: _saving != null
                  ? null
                  : (on) => unawaited(_toggleKind(kind, on)),
              title: Text(title),
              subtitle: Text(hint),
            ),
        ],
        if (_consent case final consent?)
          SwitchListTile.adaptive(
            key: const Key('notification-pref-marketing'),
            value: consent.granted,
            onChanged: _saving != null
                ? null
                : (on) => unawaited(_toggleMarketing(on)),
            title: const Text(NotificationPrefsHe.marketing),
            subtitle: Text(
              consent.text.isEmpty
                  ? NotificationPrefsHe.marketingHint
                  : consent.text,
            ),
          ),
      ],
    );
  }
}
