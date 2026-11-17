// "יומן" — the owner's agenda (server migration 0106). Bookings that clients
// made from the public link, next to the busy blocks synced from the phone's
// calendars; a day or a week at a time. "שתף קישור לקביעת פגישה" shares the
// public link (WhatsApp / share sheet / copy). Reached from ניהול (the bottom
// navbar is unchanged) and from booking notifications (/calendar).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../ui/app_page_route.dart';
import '../../ui/ds.dart';
import '../../ui/widgets/notch_notice.dart' show NoticeMotion;
import '../../util/allowed_urls.dart';
import '../../util/labels/calendar_he.dart';
import '../../util/phone.dart';
import '../business/business_template.dart';
import '../document/dialogs.dart' show toast;
import '../document/sheets/s6_share.dart' show textSharer;
import 'calendar_api.dart';
import 'calendar_settings_screen.dart';
import 'calendar_sync.dart';
import 'device_calendar.dart';

Future<void> openCalendar(BuildContext context) => Navigator.of(context).push(
  AppPageRoute<void>(
    builder: (_) => const CalendarScreen(),
    settings: const RouteSettings(name: '/calendar'),
  ),
);

/// The ניהול entry: owner / partner (business:configure), as on the server.
bool mayUseCalendar(Caps caps) => caps.can(Cap.settingsBusiness);

enum AgendaView { day, week }

/// One row of the agenda: a booking or a busy block.
class AgendaItem {
  const AgendaItem.booking(Booking this.booking) : busy = null;
  const AgendaItem.busyBlock(BusyBlock this.busy) : booking = null;

  final Booking? booking;
  final BusyBlock? busy;

  DateTime get startsAt => booking?.startsAt ?? busy!.start;
  DateTime get endsAt => booking?.endsAt ?? busy!.end;
}

DateTime _day(DateTime d) {
  final l = d.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// The agenda for [from, from + days) (local days), sorted; busy blocks that
/// exactly cover a confirmed booking (the booking written into the phone) are
/// dropped — the server already ignores those, older blocks may remain.
List<AgendaItem> agendaItems(CalendarAgenda a, DateTime from, int days) {
  final start = _day(from);
  final end = start.add(Duration(days: days));
  bool inRange(DateTime s, DateTime e) =>
      s.toLocal().isBefore(end) && e.toLocal().isAfter(start);
  final seenBusy = <String>{};
  final items = <AgendaItem>[
    for (final b in a.bookings)
      if (inRange(b.startsAt, b.endsAt)) AgendaItem.booking(b),
    for (final x in a.busy)
      if (inRange(x.start, x.end) &&
          // Two phones / calendars with the same busy time: one row.
          seenBusy.add(
            '${x.start.toIso8601String()}|${x.end.toIso8601String()}',
          ) &&
          !a.bookings.any(
            (b) => b.confirmed && b.startsAt == x.start && b.endsAt == x.end,
          ))
        AgendaItem.busyBlock(x),
  ]..sort((x, y) => x.startsAt.compareTo(y.startsAt));
  return items;
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, this.sync});

  /// Injected in tests; the app-wide [calendarSync] otherwise.
  final CalendarSync? sync;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalendarSync get _sync => widget.sync ?? calendarSync;
  AgendaView _view = AgendaView.day;
  DateTime _anchor = DateTime.now();
  CalendarSettings? _settings;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _sync.addListener(_changed);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _sync.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    await _sync.loadPrefs();
    try {
      final s = await fetchCalendarSettings();
      if (mounted) setState(() => _settings = s);
    } on Object {
      // The agenda below shows the connection error.
    }
    await _sync.sync(force: true);
  }

  Future<void> _share() async {
    final s = _settings ?? await fetchCalendarSettings();
    if (!mounted) return;
    final text = CalendarHe.shareText(
      businessContext.displayName,
      s.bookingUrl,
    );
    await showAppSheet<void>(
      context,
      builder: (sheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetTitle(CalendarHe.share),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s),
            child: SelectableText(
              s.bookingUrl,
              key: const Key('calendar-link'),
              textDirection: TextDirection.ltr,
              style: AppText.secondary,
            ),
          ),
          if (!s.enabled)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: Text(
                CalendarHe.offNotice,
                style: AppText.secondary.copyWith(color: sheet.palette.warn),
              ),
            ),
          PrimaryButton(
            key: const Key('calendar-share-whatsapp'),
            label: CalendarHe.shareWhatsapp,
            icon: Iconsax.message,
            onPressed: () {
              Navigator.of(sheet).pop();
              unawaited(launchAllowed(whatsAppUri(text: text)));
            },
          ),
          const SizedBox(height: Space.s),
          OutlinedButton.icon(
            key: const Key('calendar-share-other'),
            icon: const Icon(Iconsax.share),
            label: const Text(CalendarHe.shareOther),
            onPressed: () {
              Navigator.of(sheet).pop();
              unawaited(textSharer(text));
            },
          ),
          TextButton.icon(
            key: const Key('calendar-copy'),
            icon: const Icon(Iconsax.copy),
            label: const Text(CalendarHe.copy),
            onPressed: () {
              unawaited(Clipboard.setData(ClipboardData(text: s.bookingUrl)));
              Navigator.of(sheet).pop();
              toast(context, CalendarHe.copied);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _cancel(Booking b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(CalendarHe.cancelTitle),
        content: Text(
          '${b.clientName} · ${bookingWhen(b.startsAt)}\n\n${CalendarHe.cancelBody}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text(CalendarHe.keep),
          ),
          TextButton(
            key: const Key('calendar-cancel-confirm'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text(CalendarHe.cancelConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy.add(b.id));
    try {
      await cancelBookingAsOwner(b.id);
      if (mounted) {
        toast(
          context,
          CalendarHe.cancelledToast,
          motion: NoticeMotion.calendar,
        );
      }
      await _sync.sync(force: true);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(b.id));
    }
  }

  Future<void> _connect() async {
    final access = await _sync.connect();
    if (!mounted) return;
    if (access == CalendarAccess.denied ||
        access == CalendarAccess.restricted) {
      toast(context, CalendarHe.denied, motion: NoticeMotion.error);
    }
  }

  Future<void> _turnOn() async {
    try {
      final s = await saveCalendarSettings({'enabled': true});
      if (mounted) setState(() => _settings = s);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  String _syncLine() {
    final at = _sync.lastSyncAt;
    final prefs = _sync.prefs;
    if (prefs == null || !prefs.connected) return CalendarHe.notSynced;
    if (_sync.lastError != null) return CalendarHe.syncFailed;
    if (at == null) return CalendarHe.synced;
    final minutes = DateTime.now().difference(at).inMinutes;
    return CalendarHe.syncedAgo(minutes < 1 ? 'עכשיו' : 'לפני $minutes דק׳');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final agenda = _sync.agenda;
    final prefs = _sync.prefs;
    final from = _view == AgendaView.day
        ? _day(_anchor)
        : _day(_anchor).subtract(Duration(days: _day(_anchor).weekday % 7));
    final days = _view == AgendaView.day ? 1 : 7;
    final items = agenda == null
        ? const <AgendaItem>[]
        : agendaItems(agenda, from, days);
    final enabled = _settings?.enabled ?? agenda?.enabled ?? true;
    return BusinessPage(
      title: CalendarHe.title,
      onRefresh: () => _sync.sync(force: true),
      header: Row(
        children: [
          Icon(
            prefs?.connected == true
                ? Iconsax.refresh_circle
                : Iconsax.calendar_remove,
            size: 16,
            color: p.muted,
          ),
          const SizedBox(width: Space.xs),
          Expanded(
            child: Text(
              _syncLine(),
              key: const Key('calendar-sync-line'),
              style: AppText.secondary.copyWith(color: p.muted),
            ),
          ),
          if (_sync.syncing)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator.adaptive(strokeWidth: 2),
            ),
          IconButton(
            key: const Key('calendar-settings'),
            tooltip: CalendarHe.settings,
            icon: const Icon(Iconsax.setting_2),
            onPressed: () async {
              await openCalendarSettings(context, sync: _sync);
              if (mounted) unawaited(_refresh());
            },
          ),
        ],
      ),
      bottom: BottomActionArea(
        child: PrimaryButton(
          key: const Key('calendar-share'),
          label: CalendarHe.share,
          icon: Iconsax.link_21,
          offline: businessContext.offline,
          onPressed: () => unawaited(_share()),
        ),
      ),
      children: [
        if (!enabled)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: AppCard(
              key: const Key('calendar-off'),
              child: Row(
                children: [
                  Icon(Iconsax.info_circle, color: p.warn),
                  const SizedBox(width: Space.s),
                  const Expanded(child: Text(CalendarHe.offNotice)),
                  TextButton(
                    key: const Key('calendar-turn-on'),
                    onPressed: () => unawaited(_turnOn()),
                    child: const Text(CalendarHe.turnOn),
                  ),
                ],
              ),
            ),
          ),
        if (_sync.device.supported && prefs != null && !prefs.connected)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: _ConnectCard(
              denied: _sync.access == CalendarAccess.denied,
              onConnect: () => unawaited(_connect()),
            ),
          ),
        ChipRow<AgendaView>(
          key: const Key('calendar-view'),
          padding: EdgeInsets.zero,
          options: const [
            ChipOption(AgendaView.day, CalendarHe.viewDay),
            ChipOption(AgendaView.week, CalendarHe.viewWeek),
          ],
          selected: _view,
          onSelected: (v) => setState(() => _view = v),
        ),
        const SizedBox(height: Space.s),
        _DateNav(
          label: _rangeLabel(from, days),
          onPrev: () =>
              setState(() => _anchor = _anchor.subtract(Duration(days: days))),
          onNext: () =>
              setState(() => _anchor = _anchor.add(Duration(days: days))),
          onToday: () => setState(() => _anchor = DateTime.now()),
        ),
        const SizedBox(height: Space.s),
        if (agenda == null && _sync.lastError != null)
          ErrorView(
            error: _sync.lastError!,
            onRetry: () => unawaited(_sync.sync(force: true)),
          )
        else if (agenda == null)
          const Padding(
            padding: EdgeInsets.only(top: Space.xl),
            child: Center(child: CircularProgressIndicator.adaptive()),
          )
        else if (items.isEmpty)
          const EmptyState(
            icon: Iconsax.calendar_1,
            title: CalendarHe.empty,
            message: CalendarHe.emptyBody,
          )
        else
          ..._grouped(items, from, days),
      ],
    );
  }

  String _rangeLabel(DateTime from, int days) {
    String d(DateTime x) =>
        '${x.day.toString().padLeft(2, '0')}.${x.month.toString().padLeft(2, '0')}';
    final today = _day(DateTime.now());
    if (days == 1) {
      final name = from == today
          ? CalendarHe.today
          : from == today.add(const Duration(days: 1))
          ? CalendarHe.tomorrow
          : 'יום ${CalendarHe.days[from.weekday % 7]}';
      return '$name · ${d(from)}';
    }
    return '${d(from)} – ${d(from.add(Duration(days: days - 1)))}';
  }

  List<Widget> _grouped(List<AgendaItem> items, DateTime from, int days) {
    final out = <Widget>[];
    for (var i = 0; i < days; i++) {
      final day = from.add(Duration(days: i));
      final today = [
        for (final item in items)
          if (_day(item.startsAt) == day ||
              (days == 1 && item.startsAt.isBefore(day)))
            item,
      ];
      if (today.isEmpty) continue;
      if (days > 1) {
        out.add(
          Padding(
            padding: const EdgeInsets.only(top: Space.m, bottom: Space.xs),
            child: Text(
              'יום ${CalendarHe.days[day.weekday % 7]} · ${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}',
              style: AppText.headline,
            ),
          ),
        );
      }
      for (final item in today) {
        out.add(
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: item.booking != null
                ? BookingCard(
                    booking: item.booking!,
                    busy: _busy.contains(item.booking!.id),
                    onCancel: () => unawaited(_cancel(item.booking!)),
                  )
                : _BusyRow(block: item.busy!),
          ),
        );
      }
    }
    return out;
  }
}

class _DateNav extends StatelessWidget {
  const _DateNav({
    required this.label,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(
        key: const Key('calendar-prev'),
        icon: const Icon(Iconsax.arrow_right_3),
        onPressed: onPrev,
      ),
      Expanded(
        child: GestureDetector(
          onTap: onToday,
          child: Text(
            label,
            key: const Key('calendar-range'),
            textAlign: TextAlign.center,
            style: AppText.headline,
          ),
        ),
      ),
      IconButton(
        key: const Key('calendar-next'),
        icon: const Icon(Iconsax.arrow_left_2),
        onPressed: onNext,
      ),
    ],
  );
}

class _ConnectCard extends StatelessWidget {
  const _ConnectCard({required this.denied, required this.onConnect});
  final bool denied;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      key: const Key('calendar-connect-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Iconsax.calendar_add, color: p.ink),
              const SizedBox(width: Space.s),
              const Expanded(
                child: Text(CalendarHe.connect, style: AppText.headline),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            denied ? CalendarHe.denied : CalendarHe.connectBody,
            style: AppText.secondary.copyWith(color: p.muted),
          ),
          const SizedBox(height: Space.s),
          FilledButton(
            key: const Key('calendar-connect'),
            onPressed: onConnect,
            child: const Text(CalendarHe.connectButton),
          ),
        ],
      ),
    );
  }
}

class _BusyRow extends StatelessWidget {
  const _BusyRow({required this.block});
  final BusyBlock block;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.card,
        vertical: Space.m,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: p.line),
      ),
      child: Row(
        children: [
          Icon(Iconsax.lock_1, size: 16, color: p.muted),
          const SizedBox(width: Space.s),
          Text(
            '${hhmm(block.start)}–${hhmm(block.end)}',
            textDirection: TextDirection.ltr,
            style: AppText.secondary.copyWith(color: p.muted),
          ),
          const SizedBox(width: Space.s),
          Expanded(
            child: Text(
              block.mine ? CalendarHe.busyBlock : CalendarHe.busyOther,
              style: AppText.secondary.copyWith(color: p.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class BookingCard extends StatelessWidget {
  const BookingCard({
    super.key,
    required this.booking,
    required this.busy,
    required this.onCancel,
  });

  final Booking booking;
  final bool busy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final b = booking;
    final cancelled = !b.confirmed;
    final wa = waPhone(b.clientPhone);
    final minutes = b.endsAt.difference(b.startsAt).inMinutes;
    return Opacity(
      opacity: cancelled ? .55 : 1,
      child: AppCard(
        key: Key('booking-${b.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.s,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: DesignTokens.green.withValues(
                      alpha: cancelled ? .1 : .22,
                    ),
                    borderRadius: BorderRadius.circular(Radii.chip),
                  ),
                  child: Text(
                    '${hhmm(b.startsAt)}–${hhmm(b.endsAt)}',
                    textDirection: TextDirection.ltr,
                    style: AppText.secondary.copyWith(
                      color: p.ink,
                      fontWeight: FontWeight.w600,
                      decoration: cancelled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                const SizedBox(width: Space.s),
                Text(
                  CalendarHe.minutes(minutes),
                  style: AppText.secondary.copyWith(color: p.muted),
                ),
                const Spacer(),
                if (cancelled)
                  Text(
                    CalendarHe.cancelledBy(b.cancelledBy),
                    key: Key('booking-cancelled-${b.id}'),
                    style: AppText.secondary.copyWith(color: p.danger),
                  ),
              ],
            ),
            const SizedBox(height: Space.s),
            Text(b.clientName, style: AppText.headline),
            if (b.notes != null && b.notes!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Text(
                  b.notes!,
                  style: AppText.secondary.copyWith(color: p.muted),
                ),
              ),
            if (!cancelled) ...[
              const SizedBox(height: Space.s),
              Wrap(
                spacing: Space.xs,
                children: [
                  _Action(
                    icon: Iconsax.call,
                    label: CalendarHe.call,
                    onTap: () => unawaited(
                      launchAllowed(Uri(scheme: 'tel', path: b.clientPhone)),
                    ),
                  ),
                  if (wa != null)
                    _Action(
                      icon: Iconsax.message,
                      label: CalendarHe.whatsapp,
                      onTap: () => unawaited(
                        launchAllowed(whatsAppUri(phone: wa, text: '')),
                      ),
                    ),
                  _Action(
                    icon: Iconsax.sms,
                    label: CalendarHe.email,
                    onTap: () => unawaited(
                      launchAllowed(Uri(scheme: 'mailto', path: b.clientEmail)),
                    ),
                  ),
                  _Action(
                    key: Key('booking-cancel-${b.id}'),
                    icon: Iconsax.close_circle,
                    label: CalendarHe.cancelBooking,
                    danger: true,
                    onTap: busy ? null : onCancel,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: danger ? p.danger : p.ink),
      label: Text(
        label,
        style: AppText.secondary.copyWith(color: danger ? p.danger : p.ink),
      ),
    );
  }
}
