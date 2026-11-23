// "יומן" sync — runs on app start/resume, every 5 minutes while open, when a
// phone calendar changes, and on pull-to-refresh:
//
//   1. the phone's chosen calendars → BUSY intervals (start/end only, next 60
//      days) → PUT /calendar/busy (replaces this install's blocks);
//   2. GET /calendar/agenda → confirmed bookings are written into the chosen
//      phone calendar (moved → updated, cancelled → removed);
//   3. a booking this phone has not seen → the notch animation (if the owner
//      wants "פגישה חדשה נקבעה");
//   4. local reminders N minutes before each meeting — only when server push
//      is not active on this phone (otherwise the server's push does it).
//
// Busy times are only as fresh as the last sync: a calendar edited while the
// app is closed reaches the server on the next open (documented limitation).

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../router.dart' show go;
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../state/session.dart';
import '../../state/system_notices.dart';
import '../../ui/widgets/notch_notice.dart';
import '../../util/labels/calendar_he.dart';
import 'calendar_api.dart';
import 'device_calendar.dart';

/// Per user + business, on this phone only.
class CalendarPrefs {
  CalendarPrefs({
    this.connected = false,
    List<String>? read,
    this.write,
    String? source,
    Map<String, SyncedEvent>? events,
    List<String>? seen,
    this.seenInitialised = false,
  }) : read = read ?? [],
       source = source ?? _newSource(),
       events = events ?? {},
       seen = seen ?? [];

  factory CalendarPrefs.fromJson(Map<String, dynamic> j) => CalendarPrefs(
    connected: j['connected'] == true,
    read: [for (final r in (j['read'] as List? ?? const [])) r as String],
    write: j['write'] as String?,
    source: j['source'] as String?,
    events: {
      for (final e in ((j['events'] as Map?) ?? const {}).entries)
        e.key as String: SyncedEvent.fromJson(e.value as Map<String, dynamic>),
    },
    seen: [for (final s in (j['seen'] as List? ?? const [])) s as String],
    seenInitialised: j['seenInitialised'] == true,
  );

  bool connected;
  List<String> read;
  String? write;
  final String source;
  final Map<String, SyncedEvent> events;
  final List<String> seen;
  bool seenInitialised;

  static String _newSource() {
    final r = Random.secure();
    const abc =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return 'ios-${List.generate(20, (_) => abc[r.nextInt(abc.length)]).join()}';
  }

  Map<String, dynamic> toJson() => {
    'connected': connected,
    'read': read,
    'write': write,
    'source': source,
    'events': {for (final e in events.entries) e.key: e.value.toJson()},
    'seen': seen,
    'seenInitialised': seenInitialised,
  };
}

/// A booking this phone wrote into a phone calendar.
class SyncedEvent {
  const SyncedEvent(this.eventId, this.sequence);
  factory SyncedEvent.fromJson(Map<String, dynamic> j) =>
      SyncedEvent(j['eventId'] as String, (j['sequence'] as num).toInt());
  final String eventId;
  final int sequence;
  Map<String, dynamic> toJson() => {'eventId': eventId, 'sequence': sequence};
}

/// Storage for [CalendarPrefs] (secure storage on the phone; a map in tests).
abstract class CalendarPrefsStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SecureCalendarPrefsStore implements CalendarPrefsStore {
  static const _storage = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

/// A notice for a booking this phone sees for the first time.
typedef BookingNoticeSink = void Function(Booking booking);

/// A notice that a meeting starts soon (the in-app reminder).
typedef SoonNoticeSink = void Function(Booking booking);

/// "יום ג׳ 17.11 · 10:00" in the phone's (Israel) time.
String bookingWhen(DateTime at) {
  final l = at.toLocal();
  final dd = l.day.toString().padLeft(2, '0');
  final mm = l.month.toString().padLeft(2, '0');
  final hh = l.hour.toString().padLeft(2, '0');
  final mi = l.minute.toString().padLeft(2, '0');
  return 'יום ${CalendarHe.days[l.weekday % 7]} $dd.$mm · $hh:$mi';
}

String hhmm(DateTime at) {
  final l = at.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

class CalendarSync extends ChangeNotifier with WidgetsBindingObserver {
  CalendarSync({
    DeviceCalendarPort? device,
    CalendarPrefsStore? store,
    DateTime Function()? clock,
    this.notice,
    this.soonNotice,
  }) : device = device ?? MethodChannelDeviceCalendar(),
       store = store ?? SecureCalendarPrefsStore(),
       _clock = clock ?? DateTime.now;

  final DeviceCalendarPort device;
  final CalendarPrefsStore store;
  final DateTime Function() _clock;

  /// Shows a new-booking notice; default: the notch animation.
  BookingNoticeSink? notice;

  /// Shows "the next meeting is soon" while the app is open; default: notch.
  SoonNoticeSink? soonNotice;

  static const horizon = Duration(days: 60);
  static const _minInterval = Duration(seconds: 20);

  CalendarAgenda? agenda;
  CalendarAccess access = CalendarAccess.notDetermined;
  DateTime? lastSyncAt;
  Object? lastError;
  bool syncing = false;
  CalendarPrefs? _prefs;
  String? _prefsKey;
  Future<void>? _running;
  bool _again = false;
  Timer? _timer;
  Timer? _soonTimer;
  final Set<String> _reminded = {};
  bool _installed = false;

  CalendarPrefs? get prefs => _prefs;

  String? get _key {
    final user = session.account?.userId;
    final business = session.business?.businessId;
    if (user == null || business == null) return null;
    return 'calendar_prefs_${user}_$business';
  }

  bool get _allowed =>
      session.status == SessionStatus.signedIn &&
      businessContext.can(Cap.settingsBusiness);

  void install() {
    if (_installed) return;
    _installed = true;
    WidgetsBinding.instance.addObserver(this);
    session.addListener(_onSession);
    device.onChanged = () => unawaited(sync(force: true));
    // A bookingNew push in the foreground: re-sync, and the notch names the
    // client and the time (instead of the generic text).
    systemNotices.foregroundHandlers['bookingNew'] = (_) {
      unawaited(sync(force: true));
      return true;
    };
    // A request waiting for approval: re-sync (the agenda shows it on top)
    // and the generic notch, whose tap opens the calendar.
    systemNotices.foregroundHandlers['bookingPending'] = (_) {
      unawaited(sync(force: true));
      return false;
    };
    // While the app is open the in-app timer shows the richer reminder.
    systemNotices.foregroundHandlers['bookingSoon'] = (_) {
      unawaited(sync(force: true));
      return true;
    };
    _timer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(sync());
      }
    });
    _onSession();
  }

  void _onSession() {
    if (_key != _prefsKey) {
      _prefs = null;
      _prefsKey = null;
      agenda = null;
      lastSyncAt = null;
      notifyListeners();
    }
    if (session.status == SessionStatus.signedIn) unawaited(sync());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(sync(force: true));
  }

  Future<CalendarPrefs?> loadPrefs() async {
    final key = _key;
    if (key == null) return null;
    if (_prefsKey == key && _prefs != null) return _prefs;
    final raw = await store.read(key);
    CalendarPrefs prefs;
    try {
      prefs = raw == null
          ? CalendarPrefs()
          : CalendarPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      prefs = CalendarPrefs();
    }
    _prefs = prefs;
    _prefsKey = key;
    return prefs;
  }

  Future<void> _savePrefs() async {
    final key = _prefsKey;
    final prefs = _prefs;
    if (key == null || prefs == null) return;
    while (prefs.seen.length > 300) {
      prefs.seen.removeAt(0);
    }
    await store.write(key, jsonEncode(prefs.toJson()));
  }

  /// Asks iOS for full calendar access and, when granted, picks sensible
  /// defaults: read every calendar, write into the phone's default one.
  Future<CalendarAccess> connect() async {
    final prefs = await loadPrefs();
    access = await device.requestAccess();
    if (prefs != null &&
        (access == CalendarAccess.full || access == CalendarAccess.writeOnly)) {
      final calendars = access == CalendarAccess.full
          ? await device.calendars()
          : <DeviceCalendarInfo>[];
      prefs.connected = true;
      if (prefs.read.isEmpty) prefs.read = [for (final c in calendars) c.id];
      prefs.write ??= calendars
          .where((c) => c.writable && c.isDefault)
          .map((c) => c.id)
          .firstOrNull;
      await _savePrefs();
    }
    notifyListeners();
    await sync(force: true);
    return access;
  }

  Future<void> choose({
    List<String>? read,
    String? write,
    bool clearWrite = false,
  }) async {
    final prefs = await loadPrefs();
    if (prefs == null) return;
    if (read != null) prefs.read = read;
    if (write != null) prefs.write = write;
    if (clearWrite) prefs.write = null;
    await _savePrefs();
    notifyListeners();
    await sync(force: true);
  }

  /// "נתק": stop reading the phone, remove this phone's busy blocks on the
  /// server. Events already written stay in the phone calendar.
  Future<void> disconnect() async {
    final prefs = await loadPrefs();
    if (prefs == null) return;
    prefs.connected = false;
    await _savePrefs();
    await clearBusyBlocks(prefs.source);
    await device.scheduleReminders(const []);
    notifyListeners();
    await sync(force: true);
  }

  /// One sync at a time; a request during a run schedules one more run.
  Future<void> sync({bool force = false}) {
    if (!_allowed) return Future.value();
    if (!force &&
        lastSyncAt != null &&
        _clock().difference(lastSyncAt!) < _minInterval) {
      return Future.value();
    }
    if (_running != null) {
      _again = true;
      return _running!;
    }
    final run = _syncLoop();
    _running = run;
    return run.whenComplete(() => _running = null);
  }

  Future<void> _syncLoop() async {
    do {
      _again = false;
      await _syncOnce();
    } while (_again);
  }

  Future<void> _syncOnce() async {
    final prefs = await loadPrefs();
    if (prefs == null || !_allowed) return;
    final business = session.business?.businessId;
    syncing = true;
    notifyListeners();
    try {
      final now = _clock();
      access = device.supported
          ? await device.status()
          : CalendarAccess.unsupported;
      // 1. busy times from the phone (start/end only).
      if (prefs.connected && access == CalendarAccess.full) {
        final busy = await device.busy(now, now.add(horizon), prefs.read);
        await uploadBusyBlocks(prefs.source, [
          for (final b in busy) BusyBlock(b.start, b.end),
        ]);
      }
      // 2. the agenda (bookings + everyone's busy blocks).
      final a = await fetchCalendarAgenda(
        now.subtract(const Duration(days: 1)),
        now.add(horizon),
      );
      // The business was switched meanwhile: drop this result.
      if (session.business?.businessId != business) return;
      agenda = a;
      // 3. write bookings into the phone calendar.
      final canWrite =
          prefs.connected &&
          prefs.write != null &&
          (access == CalendarAccess.full || access == CalendarAccess.writeOnly);
      if (canWrite) await _writeBack(prefs, a, now);
      // 4. new bookings → notch (first run only marks what exists as seen).
      _noticeNew(prefs, a, now);
      // 5. local reminders when server push is not active here.
      await _reminders(a, now, business);
      _armSoon(a);
      await _savePrefs();
      lastSyncAt = _clock();
      lastError = null;
    } on Object catch (e) {
      lastError = e;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> _writeBack(
    CalendarPrefs prefs,
    CalendarAgenda a,
    DateTime now,
  ) async {
    final byId = {for (final b in a.bookings) b.id: b};
    for (final b in a.bookings) {
      if (!b.confirmed || b.endsAt.isBefore(now)) continue;
      final known = prefs.events[b.id];
      if (known != null && known.sequence == b.sequence) continue;
      final id = await device.upsertEvent(
        bookingId: b.id,
        eventId: known?.eventId,
        calendarId: prefs.write,
        start: b.startsAt,
        end: b.endsAt,
        title: CalendarHe.eventTitle(b.clientName),
        notes: CalendarHe.eventNotes(
          phone: b.clientPhone,
          email: b.clientEmail,
          notes: b.notes,
        ),
      );
      if (id != null) prefs.events[b.id] = SyncedEvent(id, b.sequence);
    }
    for (final entry in prefs.events.entries.toList()) {
      final b = byId[entry.key];
      if (b != null && b.confirmed) continue;
      // Cancelled → remove. Missing from the window (past) → just forget it.
      if (b != null) await device.deleteEvent(entry.value.eventId);
      prefs.events.remove(entry.key);
    }
  }

  void _noticeNew(CalendarPrefs prefs, CalendarAgenda a, DateTime now) {
    final fresh = [
      for (final b in a.bookings)
        if (b.confirmed &&
            b.startsAt.isAfter(now) &&
            !prefs.seen.contains(b.id))
          b,
    ];
    prefs.seen.addAll(fresh.map((b) => b.id));
    if (!prefs.seenInitialised) {
      prefs.seenInitialised = true;
      return;
    }
    if (!a.notifyNewBooking) return;
    for (final b in fresh) {
      (notice ?? _notch)(b);
    }
  }

  static void _notch(Booking b) {
    notchNoticeKey.currentState?.show(
      SnackBar(
        content: Text(
          '${CalendarHe.newBooking}\n${CalendarHe.newBookingNamed(b.clientName, bookingWhen(b.startsAt))}',
        ),
        action: SnackBarAction(
          label: CalendarHe.open,
          onPressed: () => unawaited(go('/calendar')),
        ),
      ),
      motion: NoticeMotion.calendar,
    );
  }

  bool get _serverPushActive =>
      systemNotices.enabled && systemNotices.deliveryConfigured;

  Future<void> _reminders(
    CalendarAgenda a,
    DateTime now,
    String? business,
  ) async {
    if (business == null || !device.supported) return;
    final minutes = a.reminderMinutes;
    final items = minutes <= 0 || _serverPushActive
        ? const <LocalReminder>[]
        : [
            for (final b in a.bookings)
              if (b.confirmed &&
                  b.startsAt.subtract(Duration(minutes: minutes)).isAfter(now))
                LocalReminder(
                  id: '${b.id}-${b.sequence}',
                  at: b.startsAt.subtract(Duration(minutes: minutes)),
                  title: CalendarHe.soon,
                  body: CalendarHe.soonBody(b.clientName, hhmm(b.startsAt)),
                  businessId: business,
                ),
          ];
    await device.scheduleReminders(items);
  }

  /// In-app reminder: N minutes before the next meeting, the notch — no OS
  /// notification permission needed while the app is open.
  void _armSoon(CalendarAgenda a) {
    _soonTimer?.cancel();
    final minutes = a.reminderMinutes;
    if (minutes <= 0) return;
    final now = _clock();
    final lead = Duration(minutes: minutes);
    Booking? next;
    for (final b in a.bookings) {
      if (!b.confirmed || !b.startsAt.isAfter(now)) continue;
      if (_reminded.contains('${b.id}-${b.sequence}')) continue;
      if (next == null || b.startsAt.isBefore(next.startsAt)) next = b;
    }
    if (next == null) return;
    final booking = next;
    final at = booking.startsAt.subtract(lead);
    void fire() {
      if (WidgetsBinding.instance.lifecycleState != null &&
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return; // the OS notification / push covers the background
      }
      if (!_reminded.add('${booking.id}-${booking.sequence}')) return;
      (soonNotice ?? _soonNotch)(booking);
      final current = agenda;
      if (current != null) _armSoon(current);
    }

    if (!at.isAfter(now)) {
      fire();
    } else {
      _soonTimer = Timer(at.difference(now), fire);
    }
  }

  static void _soonNotch(Booking b) {
    notchNoticeKey.currentState?.show(
      SnackBar(
        content: Text(
          '${CalendarHe.soon}\n${CalendarHe.soonBody(b.clientName, hhmm(b.startsAt))}',
        ),
        action: SnackBarAction(
          label: CalendarHe.open,
          onPressed: () => unawaited(go('/calendar')),
        ),
      ),
      motion: NoticeMotion.calendar,
    );
  }

  @override
  void dispose() {
    _soonTimer?.cancel();
    _timer?.cancel();
    session.removeListener(_onSession);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

final calendarSync = CalendarSync();
