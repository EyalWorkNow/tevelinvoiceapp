// "יומן" — the owner's calendar (server 0106/0129; spec 2611 §9: rebuilt
// almost 1:1 like iOS Calendar in Tevel's colours and font, right to left,
// weeks from Sunday). Three views:
//   · חודש — months in one continuous scroll; a dot under days with
//     meetings, today in a filled brand circle, blocked dates grey. A tap
//     zooms into that day;
//   · יום — week strip + hour timeline (calendar_day_view.dart): blocks,
//     the red "now" line, working hours white; long-press an empty hour →
//     a new meeting; long-press + drag a meeting → move ("לעדכן את הלקוח?");
//   · רשימה — everything by day, requests waiting for approval first.
// A meeting opens its details sheet (booking_detail_sheet.dart); "+" opens
// "פגישה חדשה" (new_booking_sheet.dart). "היום" is always in the top bar.
// The data and the phone sync are unchanged (calendar_sync.dart /
// device_calendar.dart / calendar_api.dart); months outside the sync window
// are fetched on demand. Reached from ניהול (the bottom navbar is unchanged)
// and from booking notifications (/calendar).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/client.dart' show ApiException;
import '../../router.dart' show openPerson;
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../ui/app_page_route.dart';
import '../../ui/ds.dart';
import '../../ui/widgets/notch_notice.dart' show NoticeMotion;
import '../../util/allowed_urls.dart';
import '../../util/labels/calendar_he.dart';
import '../../util/phone.dart';
import '../document/dialogs.dart' show toast;
import '../document/sheets/s6_share.dart' show textSharer;
import 'booking_detail_sheet.dart';
import 'calendar_api.dart';
import 'calendar_day_view.dart';
import 'calendar_layout.dart';
import 'calendar_list_view.dart';
import 'calendar_month_view.dart';
import 'calendar_settings_screen.dart';
import 'calendar_sync.dart';
import 'device_calendar.dart';
import 'new_booking_sheet.dart';

Future<void> openCalendar(BuildContext context) => Navigator.of(context).push(
  AppPageRoute<void>(
    builder: (_) => const CalendarScreen(),
    settings: const RouteSettings(name: '/calendar'),
  ),
);

/// The ניהול entry: owner / partner (business:configure), as on the server.
bool mayUseCalendar(Caps caps) => caps.can(Cap.settingsBusiness);

enum CalendarMode { month, day, list }

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
/// PENDING requests are listed apart ([pendingBookings]) unless
/// [includePending] (the day timeline shows them in place).
List<AgendaItem> agendaItems(
  CalendarAgenda a,
  DateTime from,
  int days, {
  bool includePending = false,
}) {
  final start = _day(from);
  final end = start.add(Duration(days: days));
  bool inRange(DateTime s, DateTime e) =>
      s.toLocal().isBefore(end) && e.toLocal().isAfter(start);
  final seenBusy = <String>{};
  final items = <AgendaItem>[
    for (final b in a.bookings)
      if ((includePending || !b.pending) && inRange(b.startsAt, b.endsAt))
        AgendaItem.booking(b),
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

/// Requests still waiting for the owner (not yet past), soonest first.
List<Booking> pendingBookings(CalendarAgenda a, DateTime now) => [
  for (final b in a.bookings)
    if (b.pending && b.endsAt.isAfter(now)) b,
]..sort((x, y) => x.startsAt.compareTo(y.startsAt));

/// [base] with [extra] agendas merged in (bookings by id — [base] wins —
/// and busy blocks); months outside the sync window come from [extra].
CalendarAgenda mergeAgendas(
  CalendarAgenda? base,
  Iterable<CalendarAgenda> extra,
) {
  final bookings = <String, Booking>{};
  final busy = <String, BusyBlock>{};
  for (final a in [...extra, ?base]) {
    for (final b in a.bookings) {
      bookings[b.id] = b;
    }
    for (final x in a.busy) {
      busy['${x.start.toIso8601String()}|${x.end.toIso8601String()}|${x.mine}'] =
          x;
    }
  }
  return CalendarAgenda(
    bookings: bookings.values.toList(),
    busy: busy.values.toList(),
    enabled: base?.enabled ?? true,
    notifyNewBooking: base?.notifyNewBooking ?? true,
    reminderMinutes: base?.reminderMinutes ?? 15,
    busySyncedAt: base?.busySyncedAt,
  );
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, this.sync, this.initialMode, this.clock});

  /// Injected in tests; the app-wide [calendarSync] otherwise.
  final CalendarSync? sync;

  /// Opens on this view (month by default).
  final CalendarMode? initialMode;

  /// "Now" (tests / screenshots); DateTime.now otherwise.
  final DateTime Function()? clock;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalendarSync get _sync => widget.sync ?? calendarSync;
  DateTime _now() => (widget.clock ?? DateTime.now)();
  late CalendarMode _mode = widget.initialMode ?? CalendarMode.month;
  CalendarMode _beforeList = CalendarMode.month;
  late DateTime _selected = _day(_now());
  CalendarSettings? _settings;
  final Set<String> _busy = {};
  final Map<String, CalendarAgenda> _extra = {};
  final Set<String> _loading = {};
  Alignment _zoomFrom = Alignment.center;
  final _monthKey = GlobalKey<CalendarMonthViewState>();
  final _dayKey = GlobalKey<CalendarDayViewState>();
  final _listScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _sync.addListener(_changed);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _sync.removeListener(_changed);
    _listScroll.dispose();
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
      // The views below show the connection error.
    }
    await _sync.sync(force: true);
  }

  Future<void> _reload() async {
    _extra.clear();
    await _sync.sync(force: true);
  }

  CalendarAgenda get _agenda => mergeAgendas(_sync.agenda, _extra.values);

  /// Loads a month the sync window does not cover (−1 day … +60 days).
  void _ensureMonth(DateTime month) {
    final now = _now();
    final from = addMonths(month, 0).subtract(const Duration(days: 7));
    final to = addMonths(month, 1).add(const Duration(days: 7));
    final covered =
        !from.isBefore(now.subtract(const Duration(days: 1))) &&
        !to.isAfter(now.add(CalendarSync.horizon));
    final key = '${month.year}-${month.month}';
    if (covered || _extra.containsKey(key) || !_loading.add(key)) return;
    unawaited(() async {
      try {
        final a = await fetchCalendarAgenda(from, to);
        if (mounted) setState(() => _extra[key] = a);
      } on Object {
        // A month that fails stays empty; the next visit tries again.
      } finally {
        _loading.remove(key);
      }
    }());
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
            style: TextButton.styleFrom(foregroundColor: c.palette.danger),
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
      await _reload();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(b.id));
    }
  }

  /// Runs [action] on [b] (approve / decline / block), then re-syncs.
  Future<void> _act(
    Booking b,
    Future<Booking> Function(String) action,
    String done,
  ) async {
    if (_busy.contains(b.id)) return;
    setState(() => _busy.add(b.id));
    try {
      await action(b.id);
      // Approved here: no "new booking" notice for it on the next sync.
      _sync.prefs?.seen.add(b.id);
      if (mounted) toast(context, done, motion: NoticeMotion.calendar);
      await _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'BOOKING_NOT_PENDING') {
        toast(context, CalendarHe.error(e.code));
        unawaited(_reload());
      } else {
        showErrorSnack(context, e);
      }
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(b.id));
    }
  }

  Future<void> _block(Booking b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(CalendarHe.blockTitle),
        content: Text('${b.clientName}\n\n${CalendarHe.blockBody}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text(CalendarHe.keep),
          ),
          TextButton(
            key: const Key('calendar-block-confirm'),
            style: TextButton.styleFrom(foregroundColor: c.palette.danger),
            onPressed: () => Navigator.pop(c, true),
            child: const Text(CalendarHe.blockConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _act(b, blockBookingClient, CalendarHe.blocked);
  }

  void _approve(Booking b) =>
      unawaited(_act(b, approveBooking, CalendarHe.approved));

  void _decline(Booking b) =>
      unawaited(_act(b, declineBooking, CalendarHe.declined));

  Future<void> _details(AgendaItem item) async {
    final b = item.booking;
    if (b == null) return;
    final action = await showBookingDetailSheet(
      context,
      b,
      canOpenCustomer: true,
    );
    if (!mounted || action == null) return;
    switch (action) {
      case BookingAction.approve:
        _approve(b);
      case BookingAction.decline:
        _decline(b);
      case BookingAction.block:
        await _block(b);
      case BookingAction.cancel:
        await _cancel(b);
      case BookingAction.openCustomer:
        await openPerson(context, b.customerId!);
    }
  }

  Future<void> _newBooking({DateTime? at}) async {
    final booked = await showNewBookingSheet(context, at: at);
    if (booked == null || !mounted) return;
    _sync.prefs?.seen.add(booked.id);
    toast(context, CalendarHe.booked, motion: NoticeMotion.calendar);
    await _reload();
  }

  /// Drag-to-move: asks "לעדכן את הלקוח?", then moves (with or without the
  /// e-mail). True when it moved.
  Future<bool> _move(Booking b, DateTime start) async {
    final notify = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(CalendarHe.moveTitle),
        content: Text(CalendarHe.moveBody(b.clientName, bookingWhen(start))),
        actions: [
          TextButton(
            key: const Key('calendar-move-back'),
            onPressed: () => Navigator.pop(c),
            child: const Text(CalendarHe.moveBack),
          ),
          TextButton(
            key: const Key('calendar-move-quiet'),
            onPressed: () => Navigator.pop(c, false),
            child: const Text(CalendarHe.moveQuiet),
          ),
          FilledButton(
            key: const Key('calendar-move-notify'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text(CalendarHe.moveNotify),
          ),
        ],
      ),
    );
    if (notify == null || !mounted) return false;
    try {
      await moveBooking(b.id, start, notify: notify);
      if (mounted) {
        HapticFeedback.lightImpact();
        toast(
          context,
          notify ? CalendarHe.movedNotified : CalendarHe.moved,
          motion: NoticeMotion.calendar,
        );
      }
      await _reload();
      return true;
    } on ApiException catch (e) {
      if (mounted) {
        toast(
          context,
          e.code == 'SLOT_TAKEN'
              ? CalendarHe.slotBusy
              : CalendarHe.error(e.code),
          motion: NoticeMotion.error,
        );
      }
      return false;
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
      return false;
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
    final minutes = _now().difference(at).inMinutes;
    return CalendarHe.syncedAgo(minutes < 1 ? 'עכשיו' : 'לפני $minutes דק׳');
  }

  void _openDay(DateTime day, Offset origin) {
    final size = MediaQuery.sizeOf(context);
    setState(() {
      _zoomFrom = Alignment(
        (origin.dx / size.width) * 2 - 1,
        (origin.dy / size.height) * 2 - 1,
      );
      _selected = day;
      _mode = CalendarMode.day;
    });
  }

  void _today() {
    final today = _day(_now());
    HapticFeedback.selectionClick();
    switch (_mode) {
      case CalendarMode.month:
        unawaited(_monthKey.currentState?.showMonth(monthOf(today)));
      case CalendarMode.day:
        _dayKey.currentState?.showDay(today);
      case CalendarMode.list:
        if (_listScroll.hasClients) {
          unawaited(
            _listScroll.animateTo(
              0,
              duration: context.motion(300),
              curve: Curves.easeOut,
            ),
          );
        }
    }
    setState(() => _selected = today);
  }

  void _toggleList() {
    setState(() {
      if (_mode == CalendarMode.list) {
        _mode = _beforeList;
      } else {
        _beforeList = _mode;
        _mode = CalendarMode.list;
      }
    });
  }

  List<(int, int)> _working(DateTime day) =>
      workingMinutes(_settings?.weeklyHours ?? const [], day);

  bool _blocked(DateTime day) =>
      isBlockedDay(_settings?.blockedDates ?? const [], day);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final agenda = _agenda;
    final loaded = _sync.agenda != null;
    final today = _day(_now());
    final enabled = _settings?.enabled ?? _sync.agenda?.enabled ?? true;
    final pending = loaded
        ? pendingBookings(agenda, _now())
        : const <Booking>[];
    final prefs = _sync.prefs;
    Widget body;
    if (!loaded && _sync.lastError != null) {
      body = ErrorView(
        error: _sync.lastError!,
        onRetry: () => unawaited(_sync.sync(force: true)),
      );
    } else if (!loaded) {
      body = const Center(child: CircularProgressIndicator.adaptive());
    } else {
      body = switch (_mode) {
        CalendarMode.month => Column(
          key: const ValueKey('month'),
          children: [
            const WeekdayHeader(),
            Expanded(
              child: CalendarMonthView(
                key: _monthKey,
                today: today,
                focusMonth: monthOf(_selected),
                marks: marksByDay(agenda.bookings),
                isBlocked: _blocked,
                onDay: _openDay,
                onMonthVisible: _ensureMonth,
              ),
            ),
          ],
        ),
        CalendarMode.day => CalendarDayView(
          key: _dayKey,
          day: _selected,
          today: today,
          now: _now,
          itemsFor: (d) => [
            for (final i in agendaItems(agenda, d, 1, includePending: true))
              if (i.booking == null || !i.booking!.closed) i,
          ],
          workingFor: _working,
          isBlocked: _blocked,
          onDayChanged: (d) {
            setState(() => _selected = d);
            _ensureMonth(monthOf(d));
          },
          onTapItem: (i) => unawaited(_details(i)),
          onLongPressEmpty: (at) => unawaited(_newBooking(at: at)),
          onMove: _move,
        ),
        CalendarMode.list => CalendarListView(
          key: const ValueKey('list'),
          scroll: _listScroll,
          today: today,
          pending: pending,
          days: _listDays(agenda, today),
          busyIds: _busy,
          onTap: (i) => unawaited(_details(i)),
          onApprove: _approve,
          onDecline: _decline,
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
                  style: AppText.caption.copyWith(fontSize: 13, color: p.muted),
                ),
              ),
            ],
          ),
        ),
      };
    }
    final zoom = context.motion(320);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _topBar(context, today),
            OfflineBanner(visible: businessContext.offline),
            if (!enabled)
              _Banner(
                key: const Key('calendar-off'),
                icon: Iconsax.info_circle,
                color: p.warn,
                text: CalendarHe.offNotice,
                action: CalendarHe.turnOn,
                actionKey: const Key('calendar-turn-on'),
                onAction: () => unawaited(_turnOn()),
              ),
            if (_sync.device.supported && prefs != null && !prefs.connected)
              _Banner(
                key: const Key('calendar-connect-card'),
                icon: Iconsax.calendar_add,
                color: p.ink,
                text: _sync.access == CalendarAccess.denied
                    ? CalendarHe.denied
                    : CalendarHe.connect,
                action: CalendarHe.connectButton,
                actionKey: const Key('calendar-connect'),
                onAction: () => unawaited(_connect()),
              ),
            if (pending.isNotEmpty && _mode != CalendarMode.list)
              _PendingPill(count: pending.length, onTap: _toggleList),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _reload,
                notificationPredicate: (n) =>
                    _mode != CalendarMode.day && n.depth == 0,
                child: AnimatedSwitcher(
                  duration: zoom,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) {
                    final day = child.key == _dayKey;
                    return FadeTransition(
                      opacity: anim,
                      child: ScaleTransition(
                        alignment: day ? _zoomFrom : Alignment.center,
                        scale: Tween<double>(
                          begin: day ? .55 : 1.06,
                          end: 1,
                        ).animate(anim),
                        child: child,
                      ),
                    );
                  },
                  child: body,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Days from today on with something (cancelled ones are listed faded).
  List<(DateTime, List<AgendaItem>)> _listDays(
    CalendarAgenda agenda,
    DateTime today,
  ) {
    final byDay = <DateTime, List<AgendaItem>>{};
    for (final i in agendaItems(agenda, today, 400)) {
      byDay.putIfAbsent(_day(i.startsAt), () => []).add(i);
    }
    final keys = byDay.keys.toList()..sort();
    return [for (final k in keys) (k, byDay[k]!)];
  }

  Widget _topBar(BuildContext context, DateTime today) {
    final p = context.palette;
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final day = _mode == CalendarMode.day;
    Widget lead;
    if (day) {
      lead = TextButton.icon(
        key: const Key('calendar-back-month'),
        style: TextButton.styleFrom(
          foregroundColor: p.ink,
          padding: const EdgeInsetsDirectional.only(start: 4, end: 10),
        ),
        onPressed: () {
          HapticFeedback.selectionClick();
          setState(() => _mode = CalendarMode.month);
        },
        icon: const Icon(Iconsax.arrow_right_3, size: 20),
        label: Text(
          CalendarHe.months[_selected.month - 1],
          style: AppText.headline.copyWith(fontSize: 19),
        ),
      );
    } else {
      lead = Semantics(
        header: true,
        child: Text(CalendarHe.title, style: AppText.displayTitle),
      );
    }
    Widget icon(
      Key key,
      IconData i,
      String tip,
      VoidCallback onTap, {
      bool on = false,
    }) => IconButton(
      key: key,
      tooltip: tip,
      onPressed: onTap,
      style: IconButton.styleFrom(
        backgroundColor: on ? p.charcoal : DesignTokens.control,
        minimumSize: const Size(42, 42),
      ),
      icon: Icon(i, size: 20, color: on ? p.onCharcoal : p.ink),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.page - 4,
        Space.s,
        Space.page - 4,
        Space.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: lead,
            ),
          ),
          TextButton(
            key: const Key('calendar-today'),
            style: TextButton.styleFrom(
              foregroundColor: p.ink,
              backgroundColor: DesignTokens.control,
              shape: const StadiumBorder(),
              minimumSize: const Size(56, 42),
            ),
            onPressed: _today,
            child: Text(
              CalendarHe.today,
              style: AppText.secondary.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 2),
          icon(
            const Key('calendar-list-toggle'),
            Iconsax.task_square,
            CalendarHe.listView,
            _toggleList,
            on: _mode == CalendarMode.list,
          ),
          const SizedBox(width: 2),
          icon(
            const Key('calendar-add'),
            Iconsax.add,
            CalendarHe.newMeeting,
            () => unawaited(_newBooking(at: day ? _selected : null)),
          ),
          const SizedBox(width: 2),
          MoreMenu(
            key: const Key('calendar-more'),
            items: [
              MoreMenuItem(
                label: CalendarHe.share,
                icon: Iconsax.link_21,
                onSelected: () => unawaited(_share()),
              ),
              MoreMenuItem(
                label: CalendarHe.hoursButton,
                icon: Iconsax.setting_2,
                onSelected: () async {
                  await openCalendarSettings(context, sync: _sync);
                  if (mounted) unawaited(_refresh());
                },
              ),
            ],
          ),
          if (canPop && !day) ...[
            const SizedBox(width: 2),
            const DesignBackButton(),
          ],
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
    required this.action,
    required this.actionKey,
    required this.onAction,
  });

  final IconData icon;
  final Color color;
  final String text;
  final String action;
  final Key actionKey;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        Space.page,
        Space.xs,
        Space.page,
        Space.xs,
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(
        Space.m,
        Space.xs,
        Space.xs,
        Space.xs,
      ),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.line),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: Space.s),
          Expanded(
            child: Text(
              text,
              style: AppText.caption.copyWith(fontSize: 13.5, color: p.ink),
            ),
          ),
          TextButton(key: actionKey, onPressed: onAction, child: Text(action)),
        ],
      ),
    );
  }
}

class _PendingPill extends StatelessWidget {
  const _PendingPill({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.page,
        Space.xs,
        Space.page,
        Space.xs,
      ),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Material(
          color: p.tint(p.warn),
          shape: const StadiumBorder(),
          child: InkWell(
            key: const Key('calendar-pending-pill'),
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.m,
                vertical: 6,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Iconsax.clock, size: 16, color: p.warn),
                  const SizedBox(width: Space.xs),
                  Text(
                    CalendarHe.pendingCount(count),
                    style: AppText.caption.copyWith(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: p.warn,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
    this.onApprove,
    this.onDecline,
    this.onBlock,
  });

  final Booking booking;
  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback? onApprove;
  final VoidCallback? onDecline;
  final VoidCallback? onBlock;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final b = booking;
    final cancelled = b.closed;
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
                const SizedBox(width: Space.s),
                Expanded(
                  child: b.pending
                      ? Text(
                          CalendarHe.pending,
                          key: Key('booking-pending-${b.id}'),
                          textAlign: TextAlign.end,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.secondary.copyWith(color: p.warn),
                        )
                      : cancelled
                      ? Text(
                          CalendarHe.closedLabel(b.status, b.cancelledBy),
                          key: Key('booking-cancelled-${b.id}'),
                          textAlign: TextAlign.end,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.secondary.copyWith(color: p.danger),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: Space.s),
            Text(b.clientName, style: AppText.headline),
            if (b.pending)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Text(
                  [
                    bookingWhen(b.startsAt),
                    if (b.expiresAt != null)
                      CalendarHe.pendingUntil(bookingWhen(b.expiresAt!)),
                  ].join(' · '),
                  style: AppText.secondary.copyWith(color: p.muted),
                ),
              ),
            if (b.notes != null && b.notes!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Text(
                  b.notes!,
                  style: AppText.secondary.copyWith(color: p.muted),
                ),
              ),
            if (b.pending) ...[
              const SizedBox(height: Space.s),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      key: Key('booking-approve-${b.id}'),
                      onPressed: busy ? null : onApprove,
                      child: const Text(CalendarHe.approve),
                    ),
                  ),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: OutlinedButton(
                      key: Key('booking-decline-${b.id}'),
                      onPressed: busy ? null : onDecline,
                      child: const Text(CalendarHe.decline),
                    ),
                  ),
                ],
              ),
            ],
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
                  if (b.clientEmail.isNotEmpty)
                    _Action(
                      icon: Iconsax.sms,
                      label: CalendarHe.email,
                      onTap: () => unawaited(
                        launchAllowed(
                          Uri(scheme: 'mailto', path: b.clientEmail),
                        ),
                      ),
                    ),
                  if (!b.pending)
                    _Action(
                      key: Key('booking-cancel-${b.id}'),
                      icon: Iconsax.close_circle,
                      label: CalendarHe.cancelBooking,
                      danger: true,
                      onTap: busy ? null : onCancel,
                    ),
                  if (onBlock != null)
                    _Action(
                      key: Key('booking-block-${b.id}'),
                      icon: Iconsax.user_remove,
                      label: CalendarHe.blockClient,
                      danger: true,
                      onTap: busy ? null : onBlock,
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
