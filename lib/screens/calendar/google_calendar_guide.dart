// 2611 §3א "חבר יומן גוגל": Google Calendar through the iPhone's own accounts
// (EventKit, device_calendar.dart) — no Google sign-in in the app. Three steps
// (add the Google account in the iPhone's settings → turn on "יומנים" → come
// back and tick the calendar); the screen re-reads the phone's calendars when
// the app comes back to the foreground and shows the Google ones it found.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../ui/ds.dart';
import '../../util/allowed_urls.dart';
import '../../util/labels/calendar_he.dart';
import 'calendar_sync.dart';
import 'device_calendar.dart';

/// A Google calendar on the iPhone: its account (EventKit source title) is the
/// Gmail address or "Gmail" / "Google".
bool isGoogleCalendar(DeviceCalendarInfo c) {
  final a = c.account.toLowerCase();
  return a.contains('gmail') || a.contains('google');
}

List<DeviceCalendarInfo> googleCalendars(List<DeviceCalendarInfo> all) => [
  for (final c in all)
    if (isGoogleCalendar(c)) c,
];

Future<void> openGoogleCalendarGuide(
  BuildContext context, {
  CalendarSync? sync,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    settings: const RouteSettings(name: '/calendar/google'),
    builder: (_) => GoogleCalendarGuideScreen(sync: sync),
  ),
);

class GoogleCalendarGuideScreen extends StatefulWidget {
  const GoogleCalendarGuideScreen({super.key, this.sync});

  final CalendarSync? sync;

  @override
  State<GoogleCalendarGuideScreen> createState() =>
      _GoogleCalendarGuideScreenState();
}

class _GoogleCalendarGuideScreenState extends State<GoogleCalendarGuideScreen>
    with WidgetsBindingObserver {
  CalendarSync get _sync => widget.sync ?? calendarSync;
  CalendarAccess? _access;
  List<DeviceCalendarInfo> _google = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync.addListener(_changed);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sync.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Back from the iPhone's settings: the new account is there now.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  Future<void> _load() async {
    if (!_sync.device.supported) {
      if (mounted) setState(() => _access = CalendarAccess.unsupported);
      return;
    }
    await _sync.loadPrefs();
    final access = await _sync.device.status();
    final cals = access == CalendarAccess.full
        ? await _sync.device.calendars()
        : const <DeviceCalendarInfo>[];
    if (!mounted) return;
    setState(() {
      _access = access;
      _google = googleCalendars(cals);
    });
  }

  Future<void> _allow() async {
    setState(() => _busy = true);
    try {
      await _sync.connect();
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(DeviceCalendarInfo c, bool on) async {
    if (_sync.prefs?.connected != true) await _sync.connect();
    final read = [...?_sync.prefs?.read];
    if (on) {
      if (!read.contains(c.id)) read.add(c.id);
    } else {
      read.remove(c.id);
    }
    await _sync.choose(read: read);
  }

  Future<void> _openSettings() => launchAllowed(Uri.parse('app-settings:'));

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final access = _access;
    return Scaffold(
      appBar: AppBar(title: const Text(CalendarHe.googleTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          key: const Key('google-guide'),
          padding: const EdgeInsets.fromLTRB(
            Space.page,
            Space.m,
            Space.page,
            Space.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(CalendarHe.googleIntro, style: AppText.body),
              const SizedBox(height: Space.l),
              if (access == CalendarAccess.unsupported)
                Text(
                  CalendarHe.googleUnsupported,
                  style: AppText.secondary.copyWith(color: p.muted),
                )
              else ...[
                ..._status(context, access),
                const SizedBox(height: Space.l),
                const _Step(
                  n: 1,
                  title: CalendarHe.googleStep1Title,
                  body: CalendarHe.googleStep1Body,
                ),
                const _Step(
                  n: 2,
                  title: CalendarHe.googleStep2Title,
                  body: CalendarHe.googleStep2Body,
                ),
                const _Step(
                  n: 3,
                  title: CalendarHe.googleStep3Title,
                  body: CalendarHe.googleStep3Body,
                ),
                const SizedBox(height: Space.m),
                OutlinedButton.icon(
                  key: const Key('google-open-settings'),
                  onPressed: () => unawaited(_openSettings()),
                  icon: const Icon(Iconsax.setting_2, size: 20),
                  label: const Text(CalendarHe.googleOpenSettings),
                ),
                const SizedBox(height: Space.l),
                Text(
                  CalendarHe.googleTeam,
                  style: AppText.secondary.copyWith(color: p.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _status(BuildContext context, CalendarAccess? access) {
    final p = context.palette;
    if (access == null) return const [SkeletonList(rows: 1)];
    if (access == CalendarAccess.notDetermined ||
        access == CalendarAccess.writeOnly) {
      return [
        FilledButton.icon(
          key: const Key('google-allow'),
          onPressed: _busy ? null : () => unawaited(_allow()),
          icon: const Icon(Iconsax.calendar_tick, size: 20),
          label: const Text(CalendarHe.googleAllowAccess),
        ),
      ];
    }
    if (access == CalendarAccess.denied ||
        access == CalendarAccess.restricted) {
      return [
        Text(
          CalendarHe.googleDenied,
          key: const Key('google-denied'),
          style: AppText.body.copyWith(color: p.danger),
        ),
      ];
    }
    if (_google.isEmpty) {
      return [
        Text(
          CalendarHe.googleNotFound,
          key: const Key('google-not-found'),
          style: AppText.body.copyWith(color: p.muted),
        ),
      ];
    }
    final read = _sync.prefs?.connected == true
        ? (_sync.prefs?.read ?? const <String>[])
        : const <String>[];
    return [
      AppCard(
        key: const Key('google-found'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Iconsax.tick_circle, color: p.ok, size: 22),
                const SizedBox(width: Space.s),
                const Expanded(
                  child: Text(CalendarHe.googleFound, style: AppText.headline),
                ),
              ],
            ),
            const SizedBox(height: Space.xs),
            Text(
              CalendarHe.googleFoundHint,
              style: AppText.secondary.copyWith(color: p.muted),
            ),
            for (final c in _google)
              CheckboxListTile(
                key: Key('google-calendar-${c.id}'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: read.contains(c.id),
                title: Text(c.title),
                subtitle: Text(c.account, textDirection: TextDirection.ltr),
                onChanged: (v) => unawaited(_toggle(c, v == true)),
              ),
          ],
        ),
      ),
    ];
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.title, required this.body});

  final int n;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.m),
      child: Semantics(
        label: '$n. $title. $body',
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: p.charcoal,
              child: Text(
                '$n',
                style: AppText.body.copyWith(
                  color: p.onCharcoal,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.headline),
                  const SizedBox(height: 2),
                  Text(body, style: AppText.secondary.copyWith(color: p.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
